import SwiftUI
import SwiftData
import Charts

// MARK: - 成长小报告
/// 基于本地记录的轻量数据洞察：记录数、心情分布、月度活跃、标签云。
/// 真实部署可叠加 LLM 生成的文字总结；当前用规则文案模拟。
struct GrowthReportView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Entry> { !$0.isArchived },
           sort: \Entry.happenedAt, order: .reverse) private var entries: [Entry]
    @Query private var milestones: [Milestone]

    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard
                if !moodCounts.isEmpty { moodChartCard }
                if !monthlyCounts.isEmpty { activityChartCard }
                if !topTags.isEmpty { tagsCard }
            }
            .padding()
        }
        .background(background.ignoresSafeArea())
        .navigationTitle("成长小报告")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var background: some View {
        switch env.theme.theme.backgroundStyle {
        case .solid(let hex): Color(hex: hex)
        case .gradient(let a, let b):
            LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("这段时间的布布").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            Text(summaryText).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown).lineSpacing(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(theme.opacity(0.08), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    private var summaryText: String {
        let total = entries.count
        let achieved = milestones.filter(\.isAchieved).count
        let topMood = moodCounts.max { $0.count < $1.count }?.mood.rawValue ?? "平静"
        return "一共记录了 \(total) 个瞬间，点亮 \(achieved) 个里程碑。布布最常出现的心情是「\(topMood)」。每一次记录，都是给未来的她的一封小信。"
    }

    // MARK: 心情分布

    private var moodChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("心情分布").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            Chart(moodCounts, id: \.mood) { item in
                BarMark(
                    x: .value("数量", item.count),
                    y: .value("心情", "\(item.mood.emoji) \(item.mood.rawValue)")
                )
                .foregroundStyle(theme.gradient)
                .cornerRadius(6)
            }
            .frame(height: CGFloat(moodCounts.count) * 38 + 20)
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private struct MoodCount { let mood: Mood; let count: Int }
    private var moodCounts: [MoodCount] {
        let grouped = Dictionary(grouping: entries.compactMap(\.mood)) { $0 }
        return grouped.map { MoodCount(mood: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    // MARK: 月度活跃

    private var activityChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("记录活跃度").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            Chart(monthlyCounts, id: \.label) { item in
                LineMark(x: .value("月份", item.label), y: .value("数量", item.count))
                    .foregroundStyle(theme)
                    .interpolationMethod(.catmullRom)
                AreaMark(x: .value("月份", item.label), y: .value("数量", item.count))
                    .foregroundStyle(theme.opacity(0.15).gradient)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("月份", item.label), y: .value("数量", item.count))
                    .foregroundStyle(theme)
            }
            .frame(height: 180)
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private struct MonthCount { let label: String; let count: Int; let sort: Date }
    private var monthlyCounts: [MonthCount] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry -> DateComponents in
            cal.dateComponents([.year, .month], from: entry.happenedAt)
        }
        return grouped.compactMap { comps, items -> MonthCount? in
            guard let date = cal.date(from: comps), let m = comps.month else { return nil }
            return MonthCount(label: "\(m)月", count: items.count, sort: date)
        }
        .sorted { $0.sort < $1.sort }
        .suffix(6)
        .map { $0 }
    }

    // MARK: 标签云

    private var tagsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最常出现的画面").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            FlowTags(tags: topTags, tint: theme)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var topTags: [String] {
        let all = entries.flatMap { $0.media.flatMap { $0.aiTags } }
        let counts = Dictionary(grouping: all) { $0 }.mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.prefix(10).map(\.key)
    }
}
