import SwiftUI

struct HealthKindDesign: Sendable {
    var heroTitle: String
    var heroSubtitle: String
    var icon: String
    var mascot: BubuExpression
    var quickAmounts: [Double]
    var unit: String?
    var chips: [String]
}

extension HealthRecordKind {
    var design: HealthKindDesign {
        switch self {
        case .meal:
            return HealthKindDesign(heroTitle: "今天吃了什么",
                                    heroSubtitle: "记录正餐、主食、蛋白质和吃完反应。",
                                    icon: "fork.knife.circle.fill",
                                    mascot: .eating,
                                    quickAmounts: [],
                                    unit: nil,
                                    chips: ["米粥", "面条", "鸡蛋", "肉泥", "蔬菜", "水果"])
        case .snack:
            return HealthKindDesign(heroTitle: "小零食时间",
                                    heroSubtitle: "用小卡片记录水果、酸奶、磨牙棒和尝新反应。",
                                    icon: "takeoutbag.and.cup.and.straw.fill",
                                    mascot: .playing,
                                    quickAmounts: [],
                                    unit: nil,
                                    chips: ["水果", "酸奶", "奶酪", "小饼干", "磨牙棒", "尝新"])
        case .supplement:
            return HealthKindDesign(heroTitle: "营养补充",
                                    heroSubtitle: "维 D、钙、益生菌等，适合做连续记录。",
                                    icon: "pills.circle.fill",
                                    mascot: .thinking,
                                    quickAmounts: [],
                                    unit: nil,
                                    chips: ["维D", "钙", "铁", "益生菌", "DHA"])
        case .water:
            return HealthKindDesign(heroTitle: "喝水小水壶",
                                    heroSubtitle: "快速点一下，记录今天喝了多少水。",
                                    icon: "drop.circle.fill",
                                    mascot: .drinking,
                                    quickAmounts: [30, 60, 90, 120, 150, 200],
                                    unit: "ml",
                                    chips: ["温水", "吸管杯", "水壶", "主动喝", "提醒后喝"])
        case .sleep:
            return HealthKindDesign(heroTitle: "睡眠小月亮",
                                    heroSubtitle: "记录入睡、醒来、午睡和夜醒。",
                                    icon: "moon.zzz.fill",
                                    mascot: .sleeping,
                                    quickAmounts: [],
                                    unit: nil,
                                    chips: ["午睡", "夜睡", "夜醒", "自主入睡", "哄睡"])
        case .symptom:
            return HealthKindDesign(heroTitle: "不舒服观察",
                                    heroSubtitle: "记录症状、体温、严重程度和是否需要继续观察。",
                                    icon: "cross.case.circle.fill",
                                    mascot: .drinking,
                                    quickAmounts: [],
                                    unit: nil,
                                    chips: ["流鼻涕", "咳嗽", "发热", "腹泻", "皮疹", "肚子疼"])
        case .checkup:
            return HealthKindDesign(heroTitle: "体检护理",
                                    heroSubtitle: "记录身高、体重、疫苗、牙齿和医生建议。",
                                    icon: "stethoscope.circle.fill",
                                    mascot: .love,
                                    quickAmounts: [],
                                    unit: nil,
                                    chips: ["身高", "体重", "疫苗", "牙齿", "体检", "医生建议"])
        }
    }
}
