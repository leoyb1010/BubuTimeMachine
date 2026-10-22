import Foundation

// MARK: - WHO 儿童生长标准（0–5 岁）
/// 女孩：内置 WHO Child Growth Standards（2006）官方 LMS 参数，逐月 0…60 月龄，
/// 任意百分位按 Box-Cox 公式 X = M·(1 + L·S·Z)^(1/L)（L = 0 时 X = M·e^(S·Z)）计算，
/// 不再用关键月龄抽样 + 线性插值的近似值。
///   - 体重：Weight-for-age, girls 0–5 years（wfa_girls_0-to-5-years_lms）
///   - 身长/身高：0–23 月为卧位身长，24–60 月为立位身高（lhfa_girls_0-to-5-years_lms；
///     24 月龄取身高行，因此曲线在 24 月处有约 0.7 cm 的官方台阶）
///   - 头围：Head circumference-for-age, girls 0–5 years（hcfa_girls_0-to-5-years_lms）
/// 男孩：仍用原关键月龄近似表（标注为近似，App 的主角布布是女孩）。
///
/// 说明：这是家庭参考，不替代医生评估。
enum WHOGrowthStandard {

    enum Metric: String, CaseIterable, Identifiable, Sendable {
        case height   // 身长/身高 cm
        case weight   // 体重 kg
        case head     // 头围 cm

        var id: String { rawValue }
        var title: String {
            switch self {
            case .height: return "身高"
            case .weight: return "体重"
            case .head: return "头围"
            }
        }
        var unit: String {
            switch self {
            case .height: return "cm"
            case .weight: return "kg"
            case .head: return "cm"
            }
        }
        /// 匹配 HealthRecord 录入时的关键字（从 title/amountText 里提数值）。
        var keywords: [String] {
            switch self {
            case .height: return ["身高", "身长", "高"]
            case .weight: return ["体重", "重"]
            case .head: return ["头围"]
            }
        }
    }

    /// 一个月龄点上的五条百分位值。
    struct Band: Sendable {
        let month: Int
        let p3: Double
        let p15: Double
        let p50: Double
        let p85: Double
        let p97: Double
    }

    struct LMS: Sendable, Equatable {
        let l: Double
        let m: Double
        let s: Double

        /// Z 分对应的测量值。
        func value(z: Double) -> Double {
            if abs(l) < 1e-9 { return m * exp(s * z) }
            return m * pow(1 + l * s * z, 1 / l)
        }

        /// 测量值对应的 Z 分。
        func zScore(_ x: Double) -> Double {
            guard x > 0 else { return -.infinity }
            if abs(l) < 1e-9 { return log(x / m) / s }
            return (pow(x / m, l) - 1) / (l * s)
        }
    }

    /// WHO 百分位线对应的标准正态分位数。
    enum Z {
        static let p3 = -1.880794
        static let p15 = -1.036433
        static let p50 = 0.0
        static let p85 = 1.036433
        static let p97 = 1.880794
    }

    static func isBoy(_ gender: String?) -> Bool {
        gender == "男" || gender == "男孩" || gender?.lowercased() == "male"
    }

    /// 男孩走的是近似表。
    static func isApproximate(gender: String?) -> Bool { isBoy(gender) }

    /// 0…60 月龄（可带小数）处的 LMS，相邻整月线性插值。男孩返回 nil。
    static func lms(metric: Metric, gender: String?, ageMonths: Double) -> LMS? {
        guard !isBoy(gender), ageMonths >= 0, ageMonths <= 60 else { return nil }
        let table: [LMS]
        switch metric {
        case .height: table = girlLengthHeight
        case .weight: table = girlWeight
        case .head: table = girlHead
        }
        let lower = Int(ageMonths.rounded(.down))
        if lower >= 60 { return table[60] }
        let t = ageMonths - Double(lower)
        let a = table[lower], b = table[lower + 1]
        guard t > 0 else { return a }
        return LMS(l: a.l + (b.l - a.l) * t, m: a.m + (b.m - a.m) * t, s: a.s + (b.s - a.s) * t)
    }

    /// 取某性别某指标的百分位带（女孩逐月 0…60；男孩为关键月龄）。
    static func bands(metric: Metric, gender: String?) -> [Band] {
        if isBoy(gender) {
            switch metric {
            case .height: return heightBoy
            case .weight: return weightBoy
            case .head: return headBoy
            }
        }
        return (0...60).compactMap { month in
            guard let lms = lms(metric: metric, gender: gender, ageMonths: Double(month)) else { return nil }
            return Band(month: month,
                        p3: lms.value(z: Z.p3), p15: lms.value(z: Z.p15), p50: lms.value(z: Z.p50),
                        p85: lms.value(z: Z.p85), p97: lms.value(z: Z.p97))
        }
    }

    /// 精确月龄处的 Z 分（只对女孩 LMS 有效）。
    static func zScore(metric: Metric, gender: String?, ageMonths: Double, value: Double) -> Double? {
        lms(metric: metric, gender: gender, ageMonths: ageMonths)?.zScore(value)
    }

    /// 精确月龄处的百分位（0–100，带小数）。女孩用 LMS + 正态分布；男孩用近似表插值。
    static func percentile(metric: Metric, gender: String?, ageMonths: Double, value: Double) -> Double? {
        if let z = zScore(metric: metric, gender: gender, ageMonths: ageMonths, value: value) {
            return 50 * (1 + erf(z / 2.0.squareRoot()))
        }
        guard ageMonths >= 0, ageMonths <= 60,
              let band = interpolatedBand(bands(metric: metric, gender: gender), month: Int(ageMonths.rounded()))
        else { return nil }
        let points: [(Double, Double)] = [(band.p3, 3), (band.p15, 15), (band.p50, 50), (band.p85, 85), (band.p97, 97)]
        if value <= band.p3 { return 3 }
        if value >= band.p97 { return 97 }
        for i in 0..<(points.count - 1) {
            let (v0, p0) = points[i], (v1, p1) = points[i + 1]
            if value >= v0 && value <= v1 {
                let t = (v1 - v0) == 0 ? 0 : (value - v0) / (v1 - v0)
                return p0 + (p1 - p0) * t
            }
        }
        return 50
    }

    /// 兼容旧调用：整月龄、整数百分位（夹在 3…97）。
    static func percentile(metric: Metric, gender: String?, month: Int, value: Double) -> Int? {
        percentile(metric: metric, gender: gender, ageMonths: Double(month), value: value)
            .map { Int(min(max($0, 3), 97).rounded()) }
    }

    /// 月龄落在两个关键点之间时，按月龄比例插值出五条百分位值。
    static func interpolatedBand(_ table: [Band], month: Int) -> Band? {
        guard !table.isEmpty else { return nil }
        if let exact = table.first(where: { $0.month == month }) { return exact }
        guard let lower = table.last(where: { $0.month < month }) else { return table.first }
        guard let upper = table.first(where: { $0.month > month }) else { return table.last }
        let t = Double(month - lower.month) / Double(upper.month - lower.month)
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return Band(month: month,
                    p3: lerp(lower.p3, upper.p3), p15: lerp(lower.p15, upper.p15),
                    p50: lerp(lower.p50, upper.p50), p85: lerp(lower.p85, upper.p85),
                    p97: lerp(lower.p97, upper.p97))
    }

    // MARK: 女孩 LMS（WHO 2006，月龄 0…60，下标即月龄）

    private static let girlWeight: [LMS] = [
        .init(l: 0.3809, m: 3.2322, s: 0.14171), .init(l: 0.1714, m: 4.1873, s: 0.13724),
        .init(l: 0.0962, m: 5.1282, s: 0.13000), .init(l: 0.0402, m: 5.8458, s: 0.12619),
        .init(l: -0.0050, m: 6.4237, s: 0.12402), .init(l: -0.0430, m: 6.8985, s: 0.12274),
        .init(l: -0.0756, m: 7.2970, s: 0.12204), .init(l: -0.1039, m: 7.6422, s: 0.12178),
        .init(l: -0.1288, m: 7.9487, s: 0.12181), .init(l: -0.1507, m: 8.2254, s: 0.12199),
        .init(l: -0.1700, m: 8.4800, s: 0.12223), .init(l: -0.1872, m: 8.7192, s: 0.12247),
        .init(l: -0.2024, m: 8.9481, s: 0.12268), .init(l: -0.2158, m: 9.1699, s: 0.12283),
        .init(l: -0.2278, m: 9.3870, s: 0.12294), .init(l: -0.2384, m: 9.6008, s: 0.12299),
        .init(l: -0.2478, m: 9.8124, s: 0.12303), .init(l: -0.2562, m: 10.0226, s: 0.12306),
        .init(l: -0.2637, m: 10.2315, s: 0.12309), .init(l: -0.2703, m: 10.4393, s: 0.12315),
        .init(l: -0.2762, m: 10.6464, s: 0.12323), .init(l: -0.2815, m: 10.8534, s: 0.12335),
        .init(l: -0.2862, m: 11.0608, s: 0.12350), .init(l: -0.2903, m: 11.2688, s: 0.12369),
        .init(l: -0.2941, m: 11.4775, s: 0.12390), .init(l: -0.2975, m: 11.6864, s: 0.12414),
        .init(l: -0.3005, m: 11.8947, s: 0.12441), .init(l: -0.3032, m: 12.1015, s: 0.12472),
        .init(l: -0.3057, m: 12.3059, s: 0.12506), .init(l: -0.3080, m: 12.5073, s: 0.12545),
        .init(l: -0.3101, m: 12.7055, s: 0.12587), .init(l: -0.3120, m: 12.9006, s: 0.12633),
        .init(l: -0.3138, m: 13.0930, s: 0.12683), .init(l: -0.3155, m: 13.2837, s: 0.12737),
        .init(l: -0.3171, m: 13.4731, s: 0.12794), .init(l: -0.3186, m: 13.6618, s: 0.12855),
        .init(l: -0.3201, m: 13.8503, s: 0.12919), .init(l: -0.3216, m: 14.0385, s: 0.12988),
        .init(l: -0.3230, m: 14.2265, s: 0.13059), .init(l: -0.3243, m: 14.4140, s: 0.13135),
        .init(l: -0.3257, m: 14.6010, s: 0.13213), .init(l: -0.3270, m: 14.7873, s: 0.13293),
        .init(l: -0.3283, m: 14.9727, s: 0.13376), .init(l: -0.3296, m: 15.1573, s: 0.13460),
        .init(l: -0.3309, m: 15.3410, s: 0.13545), .init(l: -0.3322, m: 15.5240, s: 0.13630),
        .init(l: -0.3335, m: 15.7064, s: 0.13716), .init(l: -0.3348, m: 15.8882, s: 0.13800),
        .init(l: -0.3361, m: 16.0697, s: 0.13884), .init(l: -0.3374, m: 16.2511, s: 0.13968),
        .init(l: -0.3387, m: 16.4322, s: 0.14051), .init(l: -0.3400, m: 16.6133, s: 0.14132),
        .init(l: -0.3414, m: 16.7942, s: 0.14213), .init(l: -0.3427, m: 16.9748, s: 0.14293),
        .init(l: -0.3440, m: 17.1551, s: 0.14371), .init(l: -0.3453, m: 17.3347, s: 0.14448),
        .init(l: -0.3466, m: 17.5136, s: 0.14525), .init(l: -0.3479, m: 17.6916, s: 0.14600),
        .init(l: -0.3492, m: 17.8686, s: 0.14675), .init(l: -0.3505, m: 18.0445, s: 0.14748),
        .init(l: -0.3518, m: 18.2193, s: 0.14821),
    ]

    /// L 恒为 1。0–23 月卧位身长，24–60 月立位身高。
    private static let girlLengthHeight: [LMS] = [
        (49.1477, 0.03790), (53.6872, 0.03640), (57.0673, 0.03568), (59.8029, 0.03520),
        (62.0899, 0.03486), (64.0301, 0.03463), (65.7311, 0.03448), (67.2873, 0.03441),
        (68.7498, 0.03440), (70.1435, 0.03444), (71.4818, 0.03452), (72.7710, 0.03464),
        (74.0150, 0.03479), (75.2176, 0.03496), (76.3817, 0.03514), (77.5099, 0.03534),
        (78.6055, 0.03555), (79.6710, 0.03576), (80.7079, 0.03598), (81.7182, 0.03620),
        (82.7036, 0.03643), (83.6654, 0.03666), (84.6040, 0.03688), (85.5202, 0.03711),
        (85.7153, 0.03764), (86.5904, 0.03786), (87.4462, 0.03808), (88.2830, 0.03830),
        (89.1004, 0.03851), (89.8991, 0.03872), (90.6797, 0.03893), (91.4430, 0.03913),
        (92.1906, 0.03933), (92.9239, 0.03952), (93.6444, 0.03971), (94.3533, 0.03989),
        (95.0515, 0.04006), (95.7399, 0.04024), (96.4187, 0.04041), (97.0885, 0.04057),
        (97.7493, 0.04073), (98.4015, 0.04089), (99.0448, 0.04105), (99.6795, 0.04120),
        (100.3058, 0.04135), (100.9238, 0.04150), (101.5337, 0.04164), (102.1360, 0.04179),
        (102.7312, 0.04193), (103.3197, 0.04206), (103.9021, 0.04220), (104.4786, 0.04233),
        (105.0494, 0.04246), (105.6148, 0.04259), (106.1748, 0.04272), (106.7295, 0.04285),
        (107.2788, 0.04298), (107.8227, 0.04310), (108.3613, 0.04322), (108.8948, 0.04334),
        (109.4233, 0.04347),
    ].map { LMS(l: 1, m: $0.0, s: $0.1) }

    /// L 恒为 1。
    private static let girlHead: [LMS] = [
        (33.8787, 0.03496), (36.5463, 0.03210), (38.2521, 0.03168), (39.5328, 0.03140),
        (40.5817, 0.03119), (41.4590, 0.03102), (42.1995, 0.03087), (42.8290, 0.03075),
        (43.3671, 0.03063), (43.8300, 0.03053), (44.2319, 0.03044), (44.5844, 0.03035),
        (44.8965, 0.03027), (45.1752, 0.03019), (45.4265, 0.03012), (45.6551, 0.03006),
        (45.8650, 0.02999), (46.0598, 0.02993), (46.2424, 0.02987), (46.4152, 0.02982),
        (46.5801, 0.02977), (46.7384, 0.02972), (46.8913, 0.02967), (47.0391, 0.02962),
        (47.1822, 0.02957), (47.3204, 0.02953), (47.4536, 0.02949), (47.5817, 0.02945),
        (47.7045, 0.02941), (47.8219, 0.02937), (47.9340, 0.02933), (48.0410, 0.02929),
        (48.1432, 0.02926), (48.2408, 0.02922), (48.3343, 0.02919), (48.4239, 0.02915),
        (48.5099, 0.02912), (48.5926, 0.02909), (48.6722, 0.02906), (48.7489, 0.02903),
        (48.8228, 0.02900), (48.8941, 0.02897), (48.9629, 0.02894), (49.0294, 0.02891),
        (49.0937, 0.02888), (49.1559, 0.02886), (49.2161, 0.02883), (49.2744, 0.02880),
        (49.3309, 0.02878), (49.3857, 0.02875), (49.4389, 0.02873), (49.4905, 0.02870),
        (49.5405, 0.02868), (49.5892, 0.02865), (49.6365, 0.02863), (49.6826, 0.02861),
        (49.7275, 0.02859), (49.7712, 0.02856), (49.8139, 0.02854), (49.8556, 0.02852),
        (49.8964, 0.02850),
    ].map { LMS(l: 1, m: $0.0, s: $0.1) }

    // MARK: 男孩近似表（关键月龄：0,2,4,6,9,12,18,24,36,48,60）

    private static let heightBoy: [Band] = [
        .init(month: 0,  p3: 46.1, p15: 47.9, p50: 49.9, p85: 51.8, p97: 53.7),
        .init(month: 2,  p3: 54.4, p15: 56.4, p50: 58.4, p85: 60.4, p97: 62.4),
        .init(month: 4,  p3: 59.7, p15: 61.8, p50: 63.9, p85: 66.0, p97: 68.0),
        .init(month: 6,  p3: 63.3, p15: 65.5, p50: 67.6, p85: 69.8, p97: 71.9),
        .init(month: 9,  p3: 67.5, p15: 69.7, p50: 72.0, p85: 74.2, p97: 76.5),
        .init(month: 12, p3: 71.0, p15: 73.4, p50: 75.7, p85: 78.1, p97: 80.5),
        .init(month: 18, p3: 76.9, p15: 79.6, p50: 82.3, p85: 85.0, p97: 87.7),
        .init(month: 24, p3: 81.7, p15: 84.8, p50: 87.8, p85: 90.9, p97: 93.9),
        .init(month: 36, p3: 88.7, p15: 92.4, p50: 96.1, p85: 99.8, p97: 103.5),
        .init(month: 48, p3: 94.9, p15: 99.1, p50: 103.3, p85: 107.5, p97: 111.7),
        .init(month: 60, p3: 100.7, p15: 105.3, p50: 110.0, p85: 114.6, p97: 119.2),
    ]
    private static let weightBoy: [Band] = [
        .init(month: 0,  p3: 2.5, p15: 2.9, p50: 3.3, p85: 3.9, p97: 4.4),
        .init(month: 2,  p3: 4.3, p15: 4.9, p50: 5.6, p85: 6.3, p97: 7.1),
        .init(month: 4,  p3: 5.6, p15: 6.2, p50: 7.0, p85: 7.9, p97: 8.7),
        .init(month: 6,  p3: 6.4, p15: 7.1, p50: 7.9, p85: 8.9, p97: 9.8),
        .init(month: 9,  p3: 7.1, p15: 7.9, p50: 8.9, p85: 10.0, p97: 11.0),
        .init(month: 12, p3: 7.7, p15: 8.6, p50: 9.6, p85: 10.8, p97: 12.0),
        .init(month: 18, p3: 8.8, p15: 9.8, p50: 10.9, p85: 12.3, p97: 13.7),
        .init(month: 24, p3: 9.7, p15: 10.8, p50: 12.2, p85: 13.6, p97: 15.3),
        .init(month: 36, p3: 11.3, p15: 12.7, p50: 14.3, p85: 16.2, p97: 18.3),
        .init(month: 48, p3: 12.7, p15: 14.2, p50: 16.3, p85: 18.6, p97: 21.2),
        .init(month: 60, p3: 14.1, p15: 15.7, p50: 18.3, p85: 21.0, p97: 24.2),
    ]
    private static let headBoy: [Band] = [
        .init(month: 0,  p3: 32.4, p15: 33.4, p50: 34.5, p85: 35.5, p97: 36.6),
        .init(month: 2,  p3: 37.0, p15: 38.0, p50: 39.1, p85: 40.3, p97: 41.5),
        .init(month: 4,  p3: 39.7, p15: 40.6, p50: 41.6, p85: 42.7, p97: 43.8),
        .init(month: 6,  p3: 41.5, p15: 42.4, p50: 43.3, p85: 44.2, p97: 45.2),
        .init(month: 9,  p3: 43.0, p15: 43.9, p50: 45.0, p85: 46.0, p97: 47.0),
        .init(month: 12, p3: 44.0, p15: 44.9, p50: 46.1, p85: 47.1, p97: 48.1),
        .init(month: 18, p3: 45.3, p15: 46.3, p50: 47.4, p85: 48.5, p97: 49.5),
        .init(month: 24, p3: 46.1, p15: 47.1, p50: 48.3, p85: 49.4, p97: 50.4),
        .init(month: 36, p3: 47.3, p15: 48.3, p50: 49.5, p85: 50.6, p97: 51.6),
        .init(month: 48, p3: 48.0, p15: 49.0, p50: 50.2, p85: 51.3, p97: 52.3),
        .init(month: 60, p3: 48.6, p15: 49.6, p50: 50.8, p85: 51.9, p97: 52.9),
    ]
}
