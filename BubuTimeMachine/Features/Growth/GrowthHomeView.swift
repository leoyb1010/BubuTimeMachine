import SwiftUI
import SwiftData

// MARK: - 成长总览
/// 一个成长引擎，多处消费：里程碑、实测数据、健康照护、疫苗和“第一次”共享入口，
/// 不复制数据、不新建模型，只把已经存在的事实组织成家人一眼能懂的成长域。
struct GrowthHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Milestone.createdAt, order: .reverse) private var milestones: [Milestone]
    @Query(sort: \GrowthMeasurement.measuredAt, order: .reverse) private var measurements: [GrowthMeasurement]
    @Query(sort: \HealthRecord.recordedAt, order: .reverse) private var healthRecords: [HealthRecord]
    @Query(sort: \VaccineRecord.injectedAt, order: .reverse) private var vaccines: [VaccineRecord]
    @Query(sort: \FirstTime.happenedAt, order: .reverse) private var firstTimes: [FirstTime]

    private var theme: Color { env.theme.theme.primary }
    private var achievedMilestones: [Milestone] { milestones.filter(\.isAchieved) }
    private var latestHeight: Double? {
        GrowthMeasurementResolver.latestValue(.height, from: measurements)
    }
    private var latestWeight: Double? {
        GrowthMeasurementResolver.latestValue(.weight, from: measurements)
    }
    private var latestMeasurementDate: Date? {
        measurements
            .filter { $0.heightCm != nil || $0.weightKg != nil || $0.headCircumferenceCm != nil }
            .map(\.measuredAt)
            .max()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                overview
                    .entranceEffect(index: 0)
                primaryLinks
                    .entranceEffect(index: 1)
                firstTimesSection
                    .entranceEffect(index: 2)
                recentGrowth
                    .entranceEffect(index: 3)
            }
            .padding()
            .bubuContentColumn()
        }
        .background(BubuThemedBackground().ignoresSafeArea())
        .navigationTitle("成长")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var overview: some View {
        HStack(spacing: 16) {
            BubuMascotBadge(size: 62, expression: .happy)
            VStack(alignment: .leading, spacing: 5) {
                Text("布布正在慢慢长大")
                    .font(BubuTheme.Font.scaled(19, weight: .heavy, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(overviewText)
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [theme.opacity(0.14), BubuTheme.Color.pink.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "sparkles")
                .foregroundStyle(theme.opacity(0.65))
                .padding(16)
                .symbolEffect(.pulse, value: achievedMilestones.count)
                .accessibilityHidden(true)
        }
    }

    private var overviewText: String {
        var parts: [String] = []
        if !achievedMilestones.isEmpty { parts.append("点亮了 \(achievedMilestones.count) 个里程碑") }
        if latestHeight != nil || latestWeight != nil {
            let values = [
                latestHeight.map { "身高 \(formatted($0)) cm" },
                latestWeight.map { "体重 \(formatted($0)) kg" }
            ].compactMap { $0 }
            if !values.isEmpty { parts.append(values.joined(separator: "，")) }
        }
        if !vaccines.isEmpty { parts.append("留下 \(vaccines.count) 条疫苗记录") }
        return parts.isEmpty ? "从一次测量、一个第一次或一颗新星开始记录。" : parts.joined(separator: "；") + "。"
    }

    private var primaryLinks: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 12),
                count: BubuAdaptive.columns(sizeClass, compact: 2, regular: 4)
            ),
            spacing: 12
        ) {
            NavigationLink { GrowthCurveView() } label: {
                growthLink(icon: "chart.xyaxis.line", title: "成长数据", subtitle: measurementSubtitle)
            }
            NavigationLink { MilestonesHomeView() } label: {
                growthLink(icon: "star.fill", title: "里程碑", subtitle: "已点亮 \(achievedMilestones.count) 个")
            }
            NavigationLink { HealthHomeView() } label: {
                growthLink(icon: "heart.text.square.fill", title: "健康照护", subtitle: "共 \(healthRecords.count) 条记录")
            }
            NavigationLink { VaccineView() } label: {
                growthLink(icon: "syringe.fill", title: "疫苗接种", subtitle: "已记录 \(vaccines.count) 剂")
            }
        }
        .buttonStyle(BubuPressableStyle())
    }

    private func growthLink(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(BubuTheme.Font.scaled(23, weight: .semibold))
                .foregroundStyle(theme)
                .frame(width: 42, height: 42)
                .background(theme.opacity(0.11), in: Circle())
            Text(title)
                .font(BubuTheme.Font.body.weight(.bold))
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text(subtitle)
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .padding(15)
        .background(
            BubuTheme.Color.card,
            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
        )
        .bubuCardShadow()
    }

    private var measurementSubtitle: String {
        guard let latestMeasurementDate else { return "还没有实测数据" }
        let date = BubuDateFormat.shortDate(latestMeasurementDate)
        return "最近更新于 \(date)"
    }

    @ViewBuilder
    private var firstTimesSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("第一次", systemImage: "flag.checkered")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer()
                Text("\(firstTimes.count) 条")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(theme)
            }
            if firstTimes.isEmpty {
                Text("记录里被确认的“第一次”会自动汇到这里。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            } else {
                ForEach(firstTimes.prefix(3)) { item in
                    HStack(spacing: 11) {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(theme)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.what)
                                .font(BubuTheme.Font.body.weight(.semibold))
                                .foregroundStyle(BubuTheme.Color.warmBrown)
                                .lineLimit(2)
                            Text(BubuDateFormat.shortDate(item.happenedAt))
                                .font(BubuTheme.Font.caption)
                                .foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(
            BubuTheme.Color.card,
            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
        )
    }

    @ViewBuilder
    private var recentGrowth: some View {
        if let latest = achievedMilestones.first {
            NavigationLink { MilestonesHomeView() } label: {
                HStack(spacing: 13) {
                    Text(latest.emoji)
                        .font(BubuTheme.Font.scaled(31))
                        .frame(width: 50, height: 50)
                        .background(theme.opacity(0.10), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("最近点亮")
                            .font(BubuTheme.Font.caption.weight(.semibold))
                            .foregroundStyle(theme)
                        Text(latest.title)
                            .font(BubuTheme.Font.body.weight(.bold))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(BubuTheme.Font.caption.weight(.bold))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .padding(16)
                .background(
                    theme.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
                )
            }
            .buttonStyle(BubuPressableStyle())
        }
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
