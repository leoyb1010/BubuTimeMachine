import SwiftUI
import SwiftData

// MARK: - PDF 年册导出页
/// 选一个年龄段（如「1 岁这一年」），生成 A4 竖版 PDF 年册并分享。
struct YearbookView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt) private var entries: [Entry]
    @Query(sort: \Milestone.happenedAt, order: .reverse) private var milestones: [Milestone]
    @Query private var profiles: [ChildProfile]

    @State private var selectedYear = 0
    @State private var generating = false
    @State private var pdfURL: URL?
    @State private var showShare = false
    @State private var errorText: String?

    private var profile: ChildProfile? { profiles.first }
    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                hero
                yearPicker
                summary
                generateButton
                if let errorText {
                    Text(errorText).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.danger)
                }
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("PDF 年册")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            if let pdfURL { ShareSheet(items: [pdfURL]) }
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed.fill").font(.system(size: 52)).foregroundStyle(theme)
            Text("把布布的一年，做成一本书")
                .font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
                .multilineTextAlignment(.center)
            Text("封面 + 每条记录的照片与文字 + 里程碑 + 家人寄语，A4 竖版 PDF。打印出来，就是 30 年后还能摸到的实体礼物。")
                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    /// 可选年龄段：从 0 岁到当前年龄。
    private var availableYears: [Int] {
        guard let profile else { return [0] }
        let age = AgeCalculator.ageYears(birthday: profile.birthday)
        return Array(0...max(age, 0))
    }

    private var yearPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择年龄段").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(availableYears, id: \.self) { year in
                        Button { selectedYear = year } label: {
                            Text(yearLabel(year))
                                .font(BubuTheme.Font.body.weight(.medium))
                                .foregroundStyle(selectedYear == year ? .white : BubuTheme.Color.warmBrown)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(selectedYear == year ? theme : BubuTheme.Color.softFill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func yearLabel(_ year: Int) -> String {
        year == 0 ? "0–1 岁" : "\(year) 岁这一年"
    }

    private var entriesInRange: [Entry] {
        guard let profile else { return [] }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .year, value: selectedYear, to: profile.birthday),
              let end = cal.date(byAdding: .year, value: selectedYear + 1, to: profile.birthday) else { return [] }
        return entries.filter { $0.happenedAt >= start && $0.happenedAt < end }
    }

    private var summary: some View {
        let list = entriesInRange
        return HStack(spacing: 12) {
            BubuMascotBadge(size: 44, expression: .reading)
            Text("这一年有 \(list.count) 条记录、\(list.reduce(0) { $0 + $1.media.count }) 张照片")
                .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
            Spacer()
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var generateButton: some View {
        Button {
            Task { await generate() }
        } label: {
            HStack {
                if generating { ProgressView().tint(.white) }
                else { Image(systemName: "doc.badge.arrow.up") }
                Text(generating ? "正在排版…" : "生成年册 PDF")
            }
            .font(BubuTheme.Font.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(theme, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(generating || profile == nil || entriesInRange.isEmpty)
    }

    private func generate() async {
        guard let profile else { return }
        generating = true
        errorText = nil
        defer { generating = false }

        let cal = Calendar.current
        // 主线程收集快照。
        let pages: [YearbookExporter.Page] = entriesInRange.map { e in
            YearbookExporter.Page(
                date: e.happenedAt,
                note: e.firstPersonNote ?? e.note,
                ageText: AgeCalculator.compactAge(birthday: profile.birthday, at: e.happenedAt),
                authorRole: e.authorRole,
                imageFileNames: e.media.filter { $0.type == .photo }.compactMap { $0.localFileName },
                mood: e.mood?.emoji)
        }
        let rangeStart = cal.date(byAdding: .year, value: selectedYear, to: profile.birthday) ?? profile.birthday
        let rangeEnd = cal.date(byAdding: .year, value: selectedYear + 1, to: profile.birthday) ?? .now
        let yearMilestones = milestones
            .filter { $0.isAchieved && ($0.happenedAt.map { $0 >= rangeStart && $0 < rangeEnd } ?? false) }
            .map(\.title)
        // 家人寄语：取该年记录的文字评论（排除反应）。
        let messages = entriesInRange.flatMap { e in
            e.comments.filter { !Reaction.isReaction($0) }.compactMap { c -> String? in
                guard let t = c.text, !t.isEmpty else { return nil }
                return "\(c.authorRole)：\(t)"
            }
        }
        let coverFile = profile.heroBackgroundFileName ?? entriesInRange.first?.media.first(where: { $0.type == .photo })?.localFileName

        let input = YearbookExporter.Input(
            childName: profile.name,
            rangeTitle: yearLabel(selectedYear),
            coverImageFileName: coverFile,
            entries: pages,
            milestones: yearMilestones,
            messages: Array(messages.prefix(14)))

        let exporter = YearbookExporter(mediaStore: env.mediaStore, theme: env.theme.theme)
        if let url = exporter.makePDF(input) {
            pdfURL = url
            showShare = true
            BubuHaptics.success()
        } else {
            errorText = "年册生成失败了，稍后再试试。"
        }
    }
}
