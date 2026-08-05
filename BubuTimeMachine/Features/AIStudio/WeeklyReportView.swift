import SwiftUI
import SwiftData
import UIKit

// MARK: - 布布周报
/// 只展示服务端证据约束后的派生作品，不在本地新增事实模型。
struct WeeklyReportView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt, order: .reverse)
    private var entries: [Entry]

    private let previewMode: Bool
    @State private var report: WeeklyReport?
    @State private var history: [WeeklyReport] = []
    @State private var isLoading: Bool
    @State private var operation: Operation?
    @State private var errorMessage: String?
    @State private var operationError: String?
    @State private var confirmArchive = false
    @State private var showAdvancedSettings = false
    @State private var jumpEntry: Entry?
    @State private var sourceDetail: WeeklyReportSource?
    @State private var actionTask: Task<Void, Never>?

    private enum Operation {
        case generating
        case archiving
    }

    private var theme: Color { env.theme.theme.primary }

    init(previewReport: WeeklyReport? = nil) {
        previewMode = previewReport != nil
        _report = State(initialValue: previewReport)
        _isLoading = State(initialValue: previewReport == nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                content
            }
            .padding()
            .bubuContentColumn()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("布布周报")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $jumpEntry) { EntryDetailView(entry: $0) }
        .sheet(item: $sourceDetail) { source in sourceSheet(source) }
        .sheet(isPresented: $showAdvancedSettings) {
            NavigationStack {
                AdvancedSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showAdvancedSettings = false }
                        }
                    }
            }
        }
        .alert("收进档案？", isPresented: $confirmArchive) {
            Button("收进档案") { archive() }
            Button("再看看", role: .cancel) {}
        } message: {
            Text("这只会把周报标为已归档，不会改动照片、时光、健康或成长数据。")
        }
        .alert("操作没有完成", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("知道了") { operationError = nil }
        } message: {
            Text(operationError ?? "请稍后再试。")
        }
        .task(id: env.aiServiceRevision) { await load(expectedRevision: env.aiServiceRevision) }
        .onDisappear { actionTask?.cancel() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            BubuMascotBadge(size: 62, expression: .reading)
            VStack(alignment: .leading, spacing: 5) {
                Text("把一周轻轻收好")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("每一段都附有出处，原声会原样保留；材料不足就不生成。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(theme.opacity(0.08), in: RoundedRectangle(
            cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    @ViewBuilder
    private var content: some View {
        if !previewMode && !env.config.isAIConfigured {
            stateCard(icon: "house.and.flag.fill", title: "先连接家里的 AI 服务",
                      message: "周报只在家里的 mini 上整理。配置完成后再回来，不会把家庭记录发给第三方。",
                      actionTitle: "打开高级设置") { showAdvancedSettings = true }
        } else if isLoading {
            loadingState
        } else if let report {
            reportContent(report)
        } else if let errorMessage {
            stateCard(icon: "exclamationmark.triangle.fill", title: "这次没有生成周报",
                      message: errorMessage, actionTitle: "再试一次") {
                Task { await load(expectedRevision: env.aiServiceRevision) }
            }
        } else {
            stateCard(icon: "calendar.badge.plus", title: "还没有周报",
                      message: "周报需要一周的真实记录和至少一段原声。资料不足时不会凑内容。",
                      actionTitle: "生成上周周报") { generate() }
        }
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(BubuTheme.Color.softFill).frame(height: 18)
            RoundedRectangle(cornerRadius: 10).fill(BubuTheme.Color.softFill).frame(height: 64)
            RoundedRectangle(cornerRadius: 10).fill(BubuTheme.Color.softFill).frame(height: 64)
        }
        .redacted(reason: .placeholder)
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(
            cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .accessibilityLabel("正在读取周报")
    }

    @ViewBuilder
    private func reportContent(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(weekText(report))
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text(report.status == "archived" ? "已收进档案" : "等待你确认")
                        .font(BubuTheme.Font.scaled(12, weight: .medium))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                Spacer()
                if history.count > 1 {
                    Menu {
                        ForEach(history) { item in
                            Button {
                                self.report = item
                            } label: {
                                Text("\(weekText(item)) · \(item.status == "archived" ? "已归档" : "待确认")")
                            }
                        }
                    } label: {
                        Label("往期周报", systemImage: "clock.arrow.circlepath")
                            .font(BubuTheme.Font.scaled(12, weight: .semibold))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                            .frame(minHeight: 44)
                    }
                    .accessibilityHint("选择以前生成的周报")
                }
            }
        }
        .padding(.horizontal, 4)

        ForEach(report.sections) { section in
            sectionCard(section, report: report)
        }

        if report.status != "archived" {
            Button { confirmArchive = true } label: {
                HStack(spacing: 8) {
                    if operation == .archiving { ProgressView().tint(BubuTheme.Color.background) }
                    Label(operation == .archiving ? "正在收进档案" : "收进档案",
                          systemImage: "archivebox.fill")
                }
                    .font(BubuTheme.Font.body.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(.plain)
            .foregroundStyle(BubuTheme.Color.background)
            .background(BubuTheme.Color.warmBrown, in: RoundedRectangle(
                cornerRadius: BubuTheme.Radius.button, style: .continuous))
            .disabled(operation != nil)
        }
    }

    private func sectionCard(_ section: WeeklyReportSection, report: WeeklyReport) -> some View {
        let sources = section.sourceIds.compactMap { id in
            report.sourceRefs.first(where: { $0.sourceId == id })
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text(section.text)
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            if !sources.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(sources) { source in
                        Button { open(source) } label: {
                            Label(source.title, systemImage: sourceIcon(source))
                                .font(BubuTheme.Font.scaled(11, weight: .semibold))
                                .foregroundStyle(BubuTheme.Color.warmBrown)
                                .lineLimit(2)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .background(theme.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("查看这段周报的引用摘要或原始时光")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(
            cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func stateCard(
        icon: String, title: String, message: String,
        actionTitle: String? = nil, action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(BubuTheme.Font.scaled(24, weight: .semibold))
                .foregroundStyle(theme)
            Text(title).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            Text(message).font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText).lineSpacing(4)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 8) {
                        if operation == .generating { ProgressView().tint(BubuTheme.Color.background) }
                        Text(operation == .generating ? "正在整理上周周报" : actionTitle)
                    }
                    .font(BubuTheme.Font.body.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BubuTheme.Color.background)
                .background(BubuTheme.Color.warmBrown, in: RoundedRectangle(
                    cornerRadius: BubuTheme.Radius.button, style: .continuous))
                .disabled(operation != nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(
            cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func open(_ source: WeeklyReportSource) {
        if source.collection == "entries",
           let id = UUID(uuidString: source.localId),
           let entry = entries.first(where: { $0.id == id }) {
            jumpEntry = entry
        } else {
            sourceDetail = source
        }
    }

    private func sourceSheet(_ source: WeeklyReportSource) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label(source.title, systemImage: sourceIcon(source))
                        .font(BubuTheme.Font.headline)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    if let date = Self.date(from: source.happenedAt) {
                        Text(BubuDateFormat.yearMonthDay(date))
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    Text(source.excerpt.isEmpty ? "原记录没有补充文字。" : source.excerpt)
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .lineSpacing(5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(BubuTheme.Color.background.ignoresSafeArea())
            .navigationTitle("周报出处")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sourceDetail = nil } } }
        }
    }

    private func sourceIcon(_ source: WeeklyReportSource) -> String {
        switch source.kind {
        case "voice": return "waveform"
        case "growth": return "ruler"
        case "milestone": return "star.fill"
        case "meal", "snack": return "fork.knife"
        case "sleep": return "moon.zzz.fill"
        default: return "text.quote"
        }
    }

    private func weekText(_ report: WeeklyReport) -> String {
        guard let start = Self.date(from: report.weekStart),
              let end = Self.date(from: report.weekEnd) else { return "最近一周" }
        let inclusiveEnd = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
        return "\(BubuDateFormat.yearMonthDay(start)) 至 \(BubuDateFormat.yearMonthDay(inclusiveEnd))"
    }

    private static func date(from text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
    }

    private func load(expectedRevision: Int) async {
        guard !previewMode else { return }
        actionTask?.cancel()
        guard env.config.isAIConfigured else {
            isLoading = false
            report = nil
            return
        }
        isLoading = true
        errorMessage = nil
        let service = env.aiService
        do {
            let fetchedReport = try await service.latestWeeklyReport()
            guard !Task.isCancelled, env.aiServiceRevision == expectedRevision else { return }
            report = fetchedReport
            isLoading = false

            var fetchedHistory = (try? await service.weeklyReportHistory()) ?? []
            guard !Task.isCancelled, env.aiServiceRevision == expectedRevision else { return }
            if let newest = fetchedHistory.first {
                // history 是后取得的新快照；另一设备刚生成/归档时，以它为准，避免旧 latest 覆盖新状态。
                report = newest
            } else if let fetchedReport {
                fetchedHistory = [fetchedReport]
            }
            history = fetchedHistory
        } catch {
            guard !Self.isCancellation(error), !Task.isCancelled,
                  env.aiServiceRevision == expectedRevision else { return }
            errorMessage = "家里的周报服务暂时没有回应。稍后再试，不会影响已有记录。"
            report = nil
        }
        guard !Task.isCancelled, env.aiServiceRevision == expectedRevision else { return }
        isLoading = false
    }

    private func generate() {
        guard operation == nil else { return }
        operation = .generating
        errorMessage = nil
        let service = env.aiService
        let revision = env.aiServiceRevision
        actionTask?.cancel()
        actionTask = Task { @MainActor in
            defer {
                operation = nil
                actionTask = nil
            }
            do {
                let generated = try await service.generateWeeklyReport()
                guard !Task.isCancelled, env.aiServiceRevision == revision else { return }
                report = generated
                upsertHistory(generated)
                BubuHaptics.success()
                UIAccessibility.post(notification: .announcement, argument: "上周周报已经整理好")
            } catch {
                guard !Self.isCancellation(error), !Task.isCancelled,
                      env.aiServiceRevision == revision else { return }
                errorMessage = Self.readable(error)
                UIAccessibility.post(notification: .announcement, argument: "周报暂时没有生成")
            }
        }
    }

    private func archive() {
        guard let id = report?.id, operation == nil else { return }
        operation = .archiving
        let service = env.aiService
        let revision = env.aiServiceRevision
        actionTask?.cancel()
        actionTask = Task { @MainActor in
            defer {
                operation = nil
                actionTask = nil
            }
            do {
                let archived = try await service.archiveWeeklyReport(id: id)
                guard !Task.isCancelled, env.aiServiceRevision == revision else { return }
                report = archived
                upsertHistory(archived)
                BubuHaptics.success()
                UIAccessibility.post(notification: .announcement, argument: "周报已收进档案")
            } catch {
                guard !Self.isCancellation(error), !Task.isCancelled,
                      env.aiServiceRevision == revision else { return }
                operationError = "暂时没能收进档案。原周报还在，稍后再试即可。"
                UIAccessibility.post(notification: .announcement, argument: "周报没有收进档案")
            }
        }
    }

    private func upsertHistory(_ item: WeeklyReport) {
        history.removeAll { $0.id == item.id }
        history.insert(item, at: 0)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private static func readable(_ error: Error) -> String {
        let text = String(describing: error)
        if text.contains("原声") || text.contains("证据") || text.contains("记录") {
            return "上周的真实材料还不够，至少需要几条记录和一段原声。我不会用想象补齐。"
        }
        return "家里的周报服务暂时没有回应。已有记录不会受影响。"
    }
}

#if DEBUG
extension WeeklyReport {
    static let visualSample: WeeklyReport = {
        let momentID = "entries:4F95B83D-40BC-4DA6-9DAB-4C84FC5CF22A"
        let voiceID = "voicememos:8791FB2B-7EA9-43A5-A347-B837FC2BCB4F"
        let growthID = "growthmeasurements:2A064D10-2478-4802-8C38-32D632253546"
        let sources = [
            WeeklyReportSource(sourceId: momentID, collection: "entries", recordId: "entryrecord1",
                               localId: "4F95B83D-40BC-4DA6-9DAB-4C84FC5CF22A",
                               happenedAt: "2026-07-29T10:30:00Z", title: "第一次认真闻桂花",
                               excerpt: "布布踮起脚，安静地闻了很久。", kind: "moment"),
            WeeklyReportSource(sourceId: voiceID, collection: "voicememos", recordId: "voicerecord1",
                               localId: "8791FB2B-7EA9-43A5-A347-B837FC2BCB4F",
                               happenedAt: "2026-07-31T12:10:00Z", title: "午后的原声",
                               excerpt: "妈妈你看，小鸟回家了。", kind: "voice"),
            WeeklyReportSource(sourceId: growthID, collection: "growthmeasurements", recordId: "growthrecord1",
                               localId: "2A064D10-2478-4802-8C38-32D632253546",
                               happenedAt: "2026-08-01T08:20:00Z", title: "成长测量",
                               excerpt: "身高 92cm，体重 13.5kg", kind: "growth"),
        ]
        return WeeklyReport(
            id: "visualsample", artifactKey: "weekly_report:sample:2026-07-27",
            status: "ready", title: "布布周报", summary: "这一周有几件小事值得收好。",
            weekStart: "2026-07-27T00:00:00Z", weekEnd: "2026-08-03T00:00:00Z",
            generatedAt: "2026-08-03T12:00:00Z", modelVersion: "visual-sample",
            contentHash: "visualsamplehash",
            sections: [
                .init(kind: "small_things", title: "本周三件小事",
                      text: "布布认真闻了桂花，午后留下一句关于小鸟的话，也完成了一次新的成长测量。",
                      sourceIds: [momentID, voiceID, growthID]),
                .init(kind: "growth", title: "一点成长",
                      text: "本周记录的身高是 92cm，体重是 13.5kg。这里只保存事实，不做发育判断。",
                      sourceIds: [growthID]),
                .init(kind: "voice", title: "一段原声",
                      text: "“妈妈你看，小鸟回家了。”",
                      sourceIds: [voiceID]),
                .init(kind: "family_question", title: "留给家人的一个问题",
                      text: "那天闻到桂花时，布布后来还说了什么？",
                      sourceIds: [momentID]),
                .init(kind: "gentle_suggestion", title: "下周轻轻试试",
                      text: "如果刚好听见一句有意思的话，可以顺手留一小段原声。",
                      sourceIds: [voiceID]),
            ],
            sourceRefs: sources)
    }()
}
#endif
