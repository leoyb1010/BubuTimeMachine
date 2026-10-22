import SwiftUI
import SwiftData
import Charts

// MARK: - 成长曲线（WHO 百分位 + 布布实测点）
struct GrowthCurveView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var env
    @Query private var profiles: [ChildProfile]
    @Query(sort: \HealthRecord.recordedAt) private var records: [HealthRecord]
    @Query(sort: \GrowthMeasurement.measuredAt) private var structuredMeasurements: [GrowthMeasurement]

    @State private var metric: WHOGrowthStandard.Metric = .height
    @AppStorage("growth.curve.axis") private var axisRaw = AxisMode.age.rawValue
    @State private var showGrowthRecorder = false
    /// 曲线从左向右“画出来”的进度（0…1）。
    @State private var reveal: CGFloat = 0

    init(initialMetric: WHOGrowthStandard.Metric = .height) {
        _metric = State(initialValue: initialMetric)
    }

    enum AxisMode: String, CaseIterable, Identifiable {
        case age, date
        var id: String { rawValue }
        var title: String { self == .age ? "按月龄" : "按日期" }
    }

    /// 一次实测：精确月龄（天数 / 30.4375，与 WHO 口径一致）+ 实际日期。
    struct CurvePoint: Identifiable {
        let id: String
        let date: Date
        let ageMonths: Double
        let value: Double
    }

    private static let daysPerMonth = 30.4375
    private var axis: AxisMode { AxisMode(rawValue: axisRaw) ?? .age }
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
            .bubuContentColumn()
        }
        .background(BubuThemedBackground().ignoresSafeArea())
        .navigationTitle("成长曲线")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGrowthRecorder) {
            HealthRecordSheet(kind: .checkup, growthOnly: true)
        }
        .task(id: "\(metric.rawValue)|\(axisRaw)") { await replayReveal() }
    }

    private func replayReveal() async {
        guard !reduceMotion else { reveal = 1; return }
        reveal = 0
        try? await Task.sleep(for: .milliseconds(60))
        guard !Task.isCancelled else { return }
        withAnimation(BubuMotion.ceremony) { reveal = 1 }
    }

    private var metricPicker: some View {
        VStack(spacing: BubuTheme.Spacing.s) {
            Picker("指标", selection: $metric.animation(BubuMotion.smooth)) {
                ForEach(WHOGrowthStandard.Metric.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            Picker("横轴", selection: $axisRaw.animation(BubuMotion.smooth)) {
                ForEach(AxisMode.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
        }
        .bubuSensoryFeedback(.selection, trigger: metric)
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
        .buttonStyle(BubuPressableStyle())
        .accessibilityHint("打开成长数据表单，可以填写身高、体重和头围")
    }

    // MARK: 数据

    private var resolverMetric: GrowthMeasurementResolver.Metric {
        switch metric {
        case .height: .height
        case .weight: .weight
        case .head: .head
        }
    }

    private func ageMonths(at date: Date, birthday: Date) -> Double {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: birthday), to: cal.startOfDay(for: date)).day ?? 0
        return Double(days) / Self.daysPerMonth
    }

    private func date(atAge months: Double, birthday: Date) -> Date {
        Calendar.current.startOfDay(for: birthday).addingTimeInterval(months * Self.daysPerMonth * 86_400)
    }

    private func value(of measurement: GrowthMeasurement) -> Double? {
        switch metric {
        case .height: measurement.heightCm
        case .weight: measurement.weightKg
        case .head: measurement.headCircumferenceCm
        }
    }

    /// 布布的实测点：每个日历月龄一个点（选点规则与首页共用 GrowthMeasurementResolver），
    /// 但横轴用该次测量的真实日期/精确月龄，而不是整月——这样百分位落点才准。
    /// 旧 HealthRecord 文本解析只补结构化缺失的月份。
    private var points: [CurvePoint] {
        guard let profile else { return [] }
        let cal = Calendar.current
        let birthday = profile.birthday
        let byMonth = GrowthMeasurementResolver.valuesByMonth(
            resolverMetric, birthday: birthday, measurements: structuredMeasurements, calendar: cal
        )
        var result: [Int: CurvePoint] = [:]
        for (month, chosen) in byMonth {
            let match = structuredMeasurements
                .filter { (cal.dateComponents([.month], from: birthday, to: $0.measuredAt).month ?? -1) == month
                    && value(of: $0) == chosen }
                .max { $0.measuredAt < $1.measuredAt }
            guard let match else { continue }
            result[month] = CurvePoint(id: match.id.uuidString, date: match.measuredAt,
                                       ageMonths: ageMonths(at: match.measuredAt, birthday: birthday), value: chosen)
        }
        for record in records {
            guard let v = GrowthMeasurementExtractor.value(metric, from: record) else { continue }
            let month = cal.dateComponents([.month], from: birthday, to: record.recordedAt).month ?? 0
            guard month >= 0, month <= 60, result[month] == nil else { continue }
            result[month] = CurvePoint(id: "legacy-\(month)", date: record.recordedAt,
                                       ageMonths: ageMonths(at: record.recordedAt, birthday: birthday), value: v)
        }
        return result.values.filter { $0.ageMonths >= 0 && $0.ageMonths <= 60.5 }.sorted { $0.ageMonths < $1.ageMonths }
    }

    /// 横轴范围：0 到“当前月龄 / 最后一次测量”之后半年，按 6 个月取整，最多 60。
    private func upperMonth(_ pts: [CurvePoint]) -> Int {
        let now = profile.map { ageMonths(at: .now, birthday: $0.birthday) } ?? 12
        let reach = max(now, pts.last?.ageMonths ?? 0) + 4
        let rounded = Int((reach / 6).rounded(.up)) * 6
        return min(60, max(12, rounded))
    }

    // MARK: 图表

    @ViewBuilder
    private var chartCard: some View {
        let pts = points
        let upper = upperMonth(pts)
        let allBands = WHOGrowthStandard.bands(metric: metric, gender: profile?.gender)
        let shownBands = allBands.filter { $0.month <= upper }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(metric.title)（\(metric.unit)）")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer()
                Text(pts.isEmpty ? "还没有实测" : "\(pts.count) 次实测")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(theme)
                    .contentTransition(.numericText())
            }
            Group {
                switch axis {
                case .age:
                    curveChart(bands: shownBands, points: pts, xBand: { Double($0) }, xPoint: { $0.ageMonths },
                               domain: 0...Double(upper), xLabel: "月龄")
                        .chartXAxis {
                            AxisMarks(values: .stride(by: upper > 36 ? 12 : 6)) { value in
                                AxisGridLine().foregroundStyle(BubuTheme.Color.hairline)
                                AxisValueLabel {
                                    if let m = value.as(Double.self) { Text("\(Int(m))月") }
                                }
                            }
                        }
                case .date:
                    if let birthday = profile?.birthday {
                        curveChart(bands: shownBands, points: pts,
                                   xBand: { date(atAge: Double($0), birthday: birthday) }, xPoint: { $0.date },
                                   domain: date(atAge: 0, birthday: birthday)...date(atAge: Double(upper), birthday: birthday),
                                   xLabel: "日期")
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .month, count: upper > 36 ? 12 : 6)) { _ in
                                    AxisGridLine().foregroundStyle(BubuTheme.Color.hairline)
                                    AxisValueLabel(format: .dateTime.year(.twoDigits).month(.defaultDigits))
                                }
                            }
                    }
                }
            }
            // 宽屏放高：横屏 1300pt 宽 × 280pt 高会把曲线压成一条，趋势读不出来
            .frame(height: BubuAdaptive.value(sizeClass, compact: 290, regular: 420))
            legend
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func curveChart<X: Plottable & Comparable>(
        bands: [WHOGrowthStandard.Band], points: [CurvePoint],
        xBand: @escaping (Int) -> X, xPoint: @escaping (CurvePoint) -> X, domain: ClosedRange<X>, xLabel: String
    ) -> some View {
        Chart {
            ForEach(bands, id: \.month) { b in
                AreaMark(x: .value(xLabel, xBand(b.month)), yStart: .value("P3", b.p3), yEnd: .value("P97", b.p97),
                         series: .value("带", "P3–P97"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(BubuTheme.Color.pinkSurface.opacity(0.75))
                AreaMark(x: .value(xLabel, xBand(b.month)), yStart: .value("P15", b.p15), yEnd: .value("P85", b.p85),
                         series: .value("带", "P15–P85"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(theme.opacity(0.16))
            }
            ForEach(bands, id: \.month) { b in
                LineMark(x: .value(xLabel, xBand(b.month)), y: .value("P50", b.p50), series: .value("线", "P50"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(theme.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            }
            ForEach(points) { p in
                LineMark(x: .value(xLabel, xPoint(p)), y: .value(metric.title, p.value), series: .value("线", "布布"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(BubuTheme.Color.deepRose)
                    .lineStyle(StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                PointMark(x: .value(xLabel, xPoint(p)), y: .value(metric.title, p.value))
                    .foregroundStyle(BubuTheme.Color.deepRose)
                    .symbol {
                        Circle()
                            .fill(BubuTheme.Color.card)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(BubuTheme.Color.deepRose, lineWidth: 3))
                    }
                    .accessibilityLabel("\(formatted(p.value)) \(metric.unit)")
                    .accessibilityValue(AgeCalculator.ageDescription(birthday: profile?.birthday ?? p.date, at: p.date))
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().frame(width: max(0, geo.size.width * reveal))
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: BubuTheme.Color.pinkSurface, label: "P3–P97")
            legendItem(color: theme.opacity(0.22), label: "P15–P85")
            legendItem(color: BubuTheme.Color.deepRose, label: "布布")
            Spacer(minLength: 0)
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
        if let last = points.last,
           let pct = WHOGrowthStandard.percentile(metric: metric, gender: profile?.gender,
                                                   ageMonths: last.ageMonths, value: last.value) {
            HStack(spacing: 12) {
                BubuMascotBadge(size: 44, expression: .happy)
                VStack(alignment: .leading, spacing: 3) {
                    Text("最近一次：\(formatted(last.value)) \(metric.unit)")
                        .font(BubuTheme.Font.body.weight(.medium))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("\(BubuDateFormat.shortDate(last.date)) · \(AgeCalculator.ageDescription(birthday: profile?.birthday ?? last.date, at: last.date))")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                    Text(percentileText(pct))
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(theme)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding()
            .background(theme.opacity(0.08), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        } else {
            Text("还没有\(metric.title)记录。点上面的「更新数据」记一条，曲线就会画出来。")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
    }

    private func percentileText(_ pct: Double) -> String {
        let verb = metric == .weight ? "重" : (metric == .height ? "高" : "大")
        if pct < 3 { return "在 P3 以下 · 下次体检时可以和医生聊聊" }
        if pct > 97 { return "在 P97 以上 · 下次体检时可以和医生聊聊" }
        let p = Int(pct.rounded())
        let who = WHOGrowthStandard.isBoy(profile?.gender) ? "男孩" : "女孩"
        return "约 P\(p) · 比同龄约 \(p)% 的\(who)\(verb)"
    }

    private func formatted(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private var disclaimer: some View {
        Text(WHOGrowthStandard.isApproximate(gender: profile?.gender)
             ? "曲线为 WHO 0–5 岁生长标准的近似值，仅供家庭参考，不替代医生评估。"
             : "曲线按 WHO 2006 儿童生长标准（女孩，LMS 法）逐月计算；0–2 岁为卧位身长、2 岁起为立位身高。仅供家庭参考，不替代医生评估。")
            .font(BubuTheme.Font.caption)
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
