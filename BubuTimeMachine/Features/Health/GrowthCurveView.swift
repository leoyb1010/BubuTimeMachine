import SwiftUI
import SwiftData
import Charts

// MARK: - 成长曲线（WHO 百分位 + 布布实测点）
struct GrowthCurveView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppEnvironment.self) private var env
    @Query private var profiles: [ChildProfile]
    @Query(sort: \HealthRecord.recordedAt) private var records: [HealthRecord]
    @Query(sort: \GrowthMeasurement.measuredAt) private var structuredMeasurements: [GrowthMeasurement]

    @State private var metric: WHOGrowthStandard.Metric = .height
    @State private var showGrowthRecorder = false

    init(initialMetric: WHOGrowthStandard.Metric = .height) {
        _metric = State(initialValue: initialMetric)
    }

    private var profile: ChildProfile? { profiles.first }
    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                metricPicker
                updateDataButton
                chartCard
                latestReading
                disclaimer
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("成长曲线")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGrowthRecorder) {
            HealthRecordSheet(kind: .checkup)
        }
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

    private var updateDataButton: some View {
        Button {
            showGrowthRecorder = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(BubuTheme.Font.scaled(18, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("更新数据")
                        .font(BubuTheme.Font.body.weight(.bold))
                    Text("记录新的身高、体重或头围")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(BubuTheme.Font.caption.weight(.bold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .foregroundStyle(BubuTheme.Color.warmBrown)
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(theme.opacity(0.10), in: RoundedRectangle(
                cornerRadius: BubuTheme.Radius.card, style: .continuous
            ))
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开体检记录，可以填写身高、体重和头围")
    }

    /// 布布的实测点：(月龄, 数值)，每个月龄唯一——图表点 id 不再重复。
    /// 结构化 GrowthMeasurement 优先（同月取最新一条）；旧 HealthRecord 文本解析只补结构化缺失的月份。
    private var measurements: [(month: Int, value: Double)] {
        guard let profile else { return [] }
        let cal = Calendar.current

        let resolvedMetric: GrowthMeasurementResolver.Metric
        switch metric {
        case .height: resolvedMetric = .height
        case .weight: resolvedMetric = .weight
        case .head: resolvedMetric = .head
        }
        var merged = GrowthMeasurementResolver.valuesByMonth(
            resolvedMetric,
            birthday: profile.birthday,
            measurements: structuredMeasurements,
            calendar: cal
        )

        let structuredMonths = Set(merged.keys)
        for record in records {
            guard let value = parseValue(from: record) else { continue }
            let month = cal.dateComponents([.month], from: profile.birthday, to: record.recordedAt).month ?? 0
            guard month >= 0, month <= 60,
                  !structuredMonths.contains(month),
                  merged[month] == nil else { continue }
            merged[month] = value
        }

        return merged.keys.sorted().map { ($0, merged[$0]!) }
    }

    /// 从旧健康记录里抽结构化数值，和首页/启动迁移共用同一套解析规则。
    private func parseValue(from record: HealthRecord) -> Double? {
        GrowthMeasurementExtractor.value(metric, from: record)
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
            // 宽屏放高：横屏 1300pt 宽 × 280pt 高会把曲线压成一条，趋势读不出来
        .frame(height: BubuAdaptive.value(sizeClass, compact: 280, regular: 420))
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
            .font(BubuTheme.Font.scaled(12))
            .foregroundStyle(BubuTheme.Color.secondaryText)
    }
}
