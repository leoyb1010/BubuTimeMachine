import SwiftUI
import SwiftData
import Charts

// MARK: - 成长报告
/// 不做伪发育评估，只呈现这个家庭档案真实收到了什么、缺什么。
struct GrowthReportView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt, order: .reverse) private var entries: [Entry]
    @Query private var milestones: [Milestone]
    @Query(sort: \HealthRecord.recordedAt, order: .reverse) private var healthRecords: [HealthRecord]

    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                archiveSummary
                metricGrid
                recordingRhythm
                careTraceCard
                milestoneCard
                placeAndSceneCard
                familyParticipationCard
                nextSuggestionCard
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("成长报告")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var archiveSummary: some View {
        HStack(alignment: .top, spacing: 14) {
            BubuMascotBadge(size: 62, expression: .reading)
            VStack(alignment: .leading, spacing: 8) {
                Text("这份档案收到了什么")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(summaryText)
                    .font(BubuTheme.Font.body)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineSpacing(5)
            }
        }
        .padding()
        .background(theme.opacity(0.08), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var summaryText: String {
        if entries.isEmpty && healthRecords.isEmpty && achievedMilestones.isEmpty {
            return "现在还只是一本空相册。先存几张照片、几句话或一段声音，未来的布布就会慢慢收到一本真实的成长书。"
        }
        return "这里不替布布下发育结论，只整理家人真实留下的材料：\(textCount) 句文字、\(photoCount) 张照片、\(voiceCount) 段声音、\(healthRecords.count) 条照护记录。"
    }

    private var metricGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            metric("照片/视频", "\(visualMediaCount)", "photo.stack", BubuTheme.Color.warning)
            metric("家人的话", "\(textCount)", "text.bubble", theme)
            metric("声音", "\(voiceCount)", "waveform", BubuTheme.Color.info)
            metric("已点亮第一次", "\(achievedMilestones.count)", "star", BubuTheme.Color.success)
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(BubuTheme.Font.scaled(20, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(BubuTheme.Font.scaled(24, weight: .bold)).foregroundStyle(BubuTheme.Color.warmBrown)
                Text(title).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            }
            Spacer()
        }
        .padding(14)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
        .bubuCardShadow()
    }

    private var recordingRhythm: some View {
        reportCard(title: "最近记录节奏", subtitle: rhythmText, expression: .music) {
            if !monthlyCounts.isEmpty {
                Chart(monthlyCounts, id: \.label) { item in
                    BarMark(x: .value("月份", item.label), y: .value("数量", item.count))
                        .foregroundStyle(theme.gradient)
                        .cornerRadius(6)
                }
                .frame(height: 150)
            }
        }
    }

    private var careTraceCard: some View {
        reportCard(title: "生活照护", subtitle: "只整理餐食、睡眠、不舒服等照护痕迹，不做医学判断。", expression: .eating) {
            if healthKindCounts.isEmpty {
                quietText("还没有健康照护记录。可以从一顿饭、一次午睡或一次不舒服开始记。")
            } else {
                ForEach(healthKindCounts, id: \.kind) { item in
                    row("\(item.kind.emoji) \(item.kind.title)", "\(item.count) 次")
                }
            }
        }
    }

    private var milestoneCard: some View {
        reportCard(title: "已点亮的第一次", subtitle: achievedMilestones.isEmpty ? "还没有点亮里程碑。" : "这些是被家人确认过的成长瞬间。", expression: .cheer) {
            ForEach(achievedMilestones.prefix(5)) { m in
                row("\(m.emoji) \(m.title)", m.category)
            }
        }
    }

    private var placeAndSceneCard: some View {
        reportCard(title: "地点和画面", subtitle: locations.isEmpty ? "没有记录地点，隐私保护中。" : "只展示你选择保存过的地点。", expression: .thinking) {
            if !locations.isEmpty { FlowTags(tags: Array(locations.prefix(8)), tint: theme) }
            if !topTags.isEmpty {
                Text("照片关键词")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .padding(.top, 4)
                FlowTags(tags: topTags, tint: theme)
            }
        }
    }

    private var familyParticipationCard: some View {
        reportCard(title: "谁在陪布布写这本书", subtitle: "不是排名，只是看见每个人留下的陪伴。", expression: .love) {
            ForEach(authorCounts, id: \.role) { item in row(item.role, "\(item.count) 条") }
        }
    }

    private var nextSuggestionCard: some View {
        HStack(alignment: .top, spacing: 12) {
            BubuMascotBadge(size: 48, expression: .bye)
            VStack(alignment: .leading, spacing: 6) {
                Text("下次可以补一点")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(suggestionText)
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .lineSpacing(4)
            }
        }
        .padding()
        .background(theme.opacity(0.07), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    private func reportCard<Content: View>(title: String, subtitle: String, expression: BubuExpression, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                BubuMascotBadge(size: 38, expression: expression)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                    Text(subtitle).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func row(_ left: String, _ right: String) -> some View {
        HStack {
            Text(left).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.warmBrown).lineLimit(1)
            Spacer()
            Text(right).font(BubuTheme.Font.caption.weight(.semibold)).foregroundStyle(BubuTheme.Color.secondaryText)
        }
    }

    private func quietText(_ text: String) -> some View {
        Text(text).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText).lineSpacing(4)
    }

    private var achievedMilestones: [Milestone] { milestones.filter(\.isAchieved).sorted { ($0.happenedAt ?? .distantPast) > ($1.happenedAt ?? .distantPast) } }
    private var photoCount: Int { entries.reduce(0) { $0 + $1.media.filter { $0.type == .photo }.count } }
    private var visualMediaCount: Int { entries.reduce(0) { $0 + $1.media.filter { $0.type == .photo || $0.type == .video }.count } }
    private var voiceCount: Int { entries.reduce(0) { $0 + $1.voiceNotes.count } }
    private var textCount: Int { entries.filter { $0.note?.isEmpty == false }.count }
    private var locations: [String] { Array(Set(entries.compactMap(\.locationName))).sorted() }
    private var topTags: [String] { Dictionary(grouping: entries.flatMap { $0.media.flatMap { $0.aiTags } }) { $0 }.mapValues(\.count).sorted { $0.value > $1.value }.prefix(8).map(\.key) }

    private struct MonthCount { let label: String; let count: Int; let sort: Date }
    private var monthlyCounts: [MonthCount] {
        let cal = Calendar.current
        return Dictionary(grouping: entries) { cal.dateComponents([.year, .month], from: $0.happenedAt) }
            .compactMap { comps, items in
                guard let date = cal.date(from: comps), let m = comps.month else { return nil }
                return MonthCount(label: "\(m)月", count: items.count, sort: date)
            }
            .sorted { $0.sort < $1.sort }.suffix(6).map { $0 }
    }

    private struct HealthKindCount { let kind: HealthRecordKind; let count: Int }
    private var healthKindCounts: [HealthKindCount] { Dictionary(grouping: healthRecords.map(\.kind)) { $0 }.map { HealthKindCount(kind: $0.key, count: $0.value.count) }.sorted { $0.count > $1.count } }

    private struct AuthorCount { let role: String; let count: Int }
    private var authorCounts: [AuthorCount] { Dictionary(grouping: entries.map(\.authorRole)) { $0 }.map { AuthorCount(role: $0.key, count: $0.value.count) }.sorted { $0.count > $1.count } }

    private var rhythmText: String {
        let recent = entries.filter { $0.happenedAt >= (Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now) }.count
        return recent == 0 ? "最近 30 天还没有新记录。" : "最近 30 天记录了 \(recent) 个瞬间。"
    }

    private var suggestionText: String {
        if voiceCount == 0 { return "可以录一段今天的声音。未来的布布会想听见家人当时的语气。" }
        if healthRecords.isEmpty { return "可以补几条餐食、睡眠或不舒服记录，照护线索会更完整。" }
        if locations.isEmpty { return "如果愿意，可以在记录时打开“记录地点”，以后能按公园、家、旅行来回看。" }
        if achievedMilestones.isEmpty { return "可以去里程碑里点亮一个第一次，比如第一次挥手或第一次叫妈妈。" }
        return "继续保持：照片、声音、文字、照护和第一次都在变丰富。"
    }
}
