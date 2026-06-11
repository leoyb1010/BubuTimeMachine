import SwiftUI
import SwiftData
import Charts

// MARK: - 成长曲线（WHO 百分位 + 布布实测点）
struct GrowthCurveView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var profiles: [ChildProfile]
    @Query(sort: \HealthRecord.recordedAt) private var records: [HealthRecord]

    @State private var metric: WHOGrowthStandard.Metric = .height

    private var profile: ChildProfile? { profiles.first }
    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                metricPicker
                chartCard
                latestReading
                disclaimer
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("成长曲线")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var metricPicker: some View {
        Picker("指标", selection: $metric) {
            ForEach(WHOGrowthStandard.Metric.allCases) { m in
                Text(m.title).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }

    private var bands: [WHOGrowthStandard.Band] {
        WHOGrowthStandard.bands(metric: metric, gender: profile?.gender)
    }

    /// 布布的实测点：(月龄, 数值)。
    private var measurements: [(month: Int, value: Double)] {
        guard let profile else { return [] }
        return records.compactMap { record -> (Int, Double)? in
            guard let value = parseValue(from: record) else { return nil }
            let month = Calendar.current.dateComponents([.month], from: profile.birthday, to: record.recordedAt).month ?? 0
            guard month >= 0, month <= 60 else { return nil }
            return (month, value)
        }
    }

    /// 从记录里抽数值：匹配指标关键字，取 amountText/title/detail 里的第一个数字。
    private func parseValue(from record: HealthRecord) -> Double? {
        let haystack = ([record.title, record.amountText, record.detail].compactMap { $0 } + record.tags).joined(separator: " ")
        guard metric.keywords.contains(where: { haystack.contains($0) }) else { return nil }
        if let value = record.amountValue,
           record.amountUnit == metric.unit {
            return value
        }
        // 抽第一个浮点数
        let pattern = #"(\d+\.?\d*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: haystack, range: NSRange(haystack.startIndex..., in: haystack)),
              let range = Range(match.range(at: 1), in: haystack) else { return nil }
        return Double(haystack[range])
    }

    @ViewBuilder
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(bands, id: \.month) { b in
                    AreaMark(x: .value("月龄", b.month), yStart: .value("P3", b.p3), yEnd: .value("P97", b.p97))
                        .foregroundStyle(theme.opacity(0.08))
                    AreaMark(x: .value("月龄", b.month), yStart: .value("P15", b.p15), yEnd: .value("P85", b.p85))
                        .foregroundStyle(theme.opacity(0.12))
                }
                ForEach(bands, id: \.month) { b in
                    LineMark(x: .value("月龄", b.month), y: .value("P50", b.p50), series: .value("线", "P50"))
                        .foregroundStyle(theme.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                ForEach(measurements, id: \.month) { m in
                    LineMark(x: .value("月龄", m.month), y: .value(metric.title, m.value), series: .value("线", "布布"))
                        .foregroundStyle(theme)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    PointMark(x: .value("月龄", m.month), y: .value(metric.title, m.value))
                        .foregroundStyle(theme)
                        .symbolSize(60)
                }
            }
            .chartYAxisLabel("\(metric.title)（\(metric.unit)）")
            .chartXAxisLabel("月龄")
            .frame(height: 280)
            legend
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: theme.opacity(0.12), label: "P15–P85 多数同龄")
            legendItem(color: theme, label: "布布")
        }
        .font(BubuTheme.Font.caption)
        .foregroundStyle(BubuTheme.Color.secondaryText)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 16, height: 10)
            Text(label)
        }
    }

    @ViewBuilder
    private var latestReading: some View {
        if let last = measurements.max(by: { $0.month < $1.month }),
           let pct = WHOGrowthStandard.percentile(metric: metric, gender: profile?.gender,
                                                   month: last.month, value: last.value) {
            HStack(spacing: 12) {
                BubuMascotBadge(size: 44, expression: .happy)
                VStack(alignment: .leading, spacing: 3) {
                    Text("最近一次：\(formatted(last.value)) \(metric.unit)（\(last.month) 月龄）")
                        .font(BubuTheme.Font.body.weight(.medium))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text(percentileText(pct))
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(theme)
                }
                Spacer()
            }
            .padding()
            .background(theme.opacity(0.08), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        } else {
            Text("还没有\(metric.title)记录。去「体检护理」记一条，比如「身高 75」，曲线就会画出来。")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
    }

    private func percentileText(_ pct: Int) -> String {
        let metricVerb = metric == .weight ? "重" : (metric == .height ? "高" : "大")
        return "P\(pct) · 比同龄约 \(pct)% 的小朋友\(metricVerb)"
    }

    private func formatted(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private var disclaimer: some View {
        Text("曲线基于 WHO 0–5 岁生长标准，仅供家庭参考，不替代医生评估。")
            .font(.system(size: 12))
            .foregroundStyle(BubuTheme.Color.secondaryText)
    }
}
