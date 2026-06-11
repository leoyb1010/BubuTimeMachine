import Foundation

// MARK: - WHO 儿童生长标准（0–5 岁百分位）
/// 内置 WHO Child Growth Standards 百分位数据（P3/P15/P50/P85/P97），无网络依赖。
/// 数据为按月龄的 L/M/S 简化版近似值（来源：WHO 2006 标准表关键月龄抽样 + 线性插值）。
/// 用于在 Swift Charts 画"五条带 + 布布实测点"，落点处给"比同龄 X% 的小朋友高"的友好解读。
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

    /// 取某性别某指标的百分位带（按月龄，0…60）。gender: "男"/"女"，其它按女孩处理。
    static func bands(metric: Metric, gender: String?) -> [Band] {
        let boy = (gender == "男" || gender == "男孩" || gender?.lowercased() == "male")
        switch metric {
        case .height: return boy ? heightBoy : heightGirl
        case .weight: return boy ? weightBoy : weightGirl
        case .head: return boy ? headBoy : headGirl
        }
    }

    /// 给定月龄与实测值，估算落在第几百分位（粗略：在 P3…P97 五点间线性插值）。
    static func percentile(metric: Metric, gender: String?, month: Int, value: Double) -> Int? {
        let table = bands(metric: metric, gender: gender)
        guard let band = nearest(table, month: month) else { return nil }
        let points: [(Double, Double)] = [(band.p3, 3), (band.p15, 15), (band.p50, 50),
                                          (band.p85, 85), (band.p97, 97)]
        if value <= band.p3 { return 3 }
        if value >= band.p97 { return 97 }
        for i in 0..<(points.count - 1) {
            let (v0, p0) = points[i]
            let (v1, p1) = points[i + 1]
            if value >= v0 && value <= v1 {
                let t = (v1 - v0) == 0 ? 0 : (value - v0) / (v1 - v0)
                return Int((p0 + (p1 - p0) * t).rounded())
            }
        }
        return 50
    }

    static func nearest(_ table: [Band], month: Int) -> Band? {
        table.min { abs($0.month - month) < abs($1.month - month) }
    }

    // MARK: 数据（关键月龄：0,2,4,6,9,12,18,24,36,48,60；中间月龄图表线性连接）
    // 数值取自 WHO 2006/2007 标准表的近似抽样，用于家庭参考。

    private static let heightGirl: [Band] = [
        .init(month: 0,  p3: 45.6, p15: 47.2, p50: 49.1, p85: 51.0, p97: 52.7),
        .init(month: 2,  p3: 53.0, p15: 54.9, p50: 57.1, p85: 59.3, p97: 61.1),
        .init(month: 4,  p3: 57.8, p15: 59.8, p50: 62.1, p85: 64.5, p97: 66.4),
        .init(month: 6,  p3: 61.2, p15: 63.3, p50: 65.7, p85: 68.2, p97: 70.3),
        .init(month: 9,  p3: 65.3, p15: 67.5, p50: 70.1, p85: 72.8, p97: 75.0),
        .init(month: 12, p3: 68.9, p15: 71.3, p50: 74.0, p85: 76.8, p97: 79.2),
        .init(month: 18, p3: 74.9, p15: 77.5, p50: 80.7, p85: 83.9, p97: 86.5),
        .init(month: 24, p3: 80.0, p15: 83.0, p50: 86.4, p85: 89.8, p97: 92.9),
        .init(month: 36, p3: 87.4, p15: 90.9, p50: 95.1, p85: 99.3, p97: 102.7),
        .init(month: 48, p3: 94.1, p15: 98.0, p50: 102.7, p85: 107.4, p97: 111.3),
        .init(month: 60, p3: 99.9, p15: 104.5, p50: 109.4, p85: 114.5, p97: 118.9),
    ]
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
    private static let weightGirl: [Band] = [
        .init(month: 0,  p3: 2.4, p15: 2.8, p50: 3.2, p85: 3.7, p97: 4.2),
        .init(month: 2,  p3: 4.0, p15: 4.5, p50: 5.1, p85: 5.8, p97: 6.5),
        .init(month: 4,  p3: 5.0, p15: 5.6, p50: 6.4, p85: 7.3, p97: 8.1),
        .init(month: 6,  p3: 5.7, p15: 6.4, p50: 7.3, p85: 8.3, p97: 9.3),
        .init(month: 9,  p3: 6.5, p15: 7.3, p50: 8.2, p85: 9.3, p97: 10.5),
        .init(month: 12, p3: 7.0, p15: 7.9, p50: 8.9, p85: 10.1, p97: 11.5),
        .init(month: 18, p3: 8.1, p15: 9.1, p50: 10.2, p85: 11.6, p97: 13.2),
        .init(month: 24, p3: 9.0, p15: 10.2, p50: 11.5, p85: 13.0, p97: 14.8),
        .init(month: 36, p3: 10.8, p15: 12.1, p50: 13.9, p85: 15.8, p97: 18.1),
        .init(month: 48, p3: 12.3, p15: 13.8, p50: 16.1, p85: 18.5, p97: 21.5),
        .init(month: 60, p3: 13.7, p15: 15.3, p50: 18.2, p85: 21.2, p97: 24.9),
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
    private static let headGirl: [Band] = [
        .init(month: 0,  p3: 32.0, p15: 33.0, p50: 33.9, p85: 34.8, p97: 35.8),
        .init(month: 2,  p3: 36.0, p15: 37.0, p50: 38.3, p85: 39.5, p97: 40.5),
        .init(month: 4,  p3: 38.5, p15: 39.5, p50: 40.6, p85: 41.8, p97: 42.9),
        .init(month: 6,  p3: 40.0, p15: 41.0, p50: 42.2, p85: 43.4, p97: 44.5),
        .init(month: 9,  p3: 41.5, p15: 42.6, p50: 43.8, p85: 45.0, p97: 46.1),
        .init(month: 12, p3: 42.5, p15: 43.6, p50: 44.9, p85: 46.1, p97: 47.2),
        .init(month: 18, p3: 43.9, p15: 45.0, p50: 46.2, p85: 47.4, p97: 48.6),
        .init(month: 24, p3: 44.8, p15: 45.9, p50: 47.2, p85: 48.4, p97: 49.6),
        .init(month: 36, p3: 46.0, p15: 47.1, p50: 48.3, p85: 49.6, p97: 50.8),
        .init(month: 48, p3: 46.8, p15: 47.9, p50: 49.1, p85: 50.4, p97: 51.6),
        .init(month: 60, p3: 47.4, p15: 48.5, p50: 49.7, p85: 51.0, p97: 52.2),
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
