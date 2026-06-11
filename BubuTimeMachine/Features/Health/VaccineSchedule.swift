import Foundation

// MARK: - 国家免疫规划疫苗表（一类苗）
/// 内置中国国家免疫规划程序（一类苗，免费）按月龄排期。无网络依赖。
/// 用于按布布月龄自动排期 + 完成打卡 + 提前提醒。仅供家庭参考，以当地接种点通知为准。
struct VaccineDose: Identifiable, Sendable, Hashable {
    let id: String          // 稳定 id：疫苗简称+剂次
    let vaccine: String     // 疫苗全称
    let shortName: String   // 简称
    let doseLabel: String   // 第几剂
    let monthDue: Int       // 推荐接种月龄（出生为 0）
    let prevents: String    // 预防疾病

    static let schedule: [VaccineDose] = [
        .init(id: "HepB-1", vaccine: "乙肝疫苗", shortName: "乙肝", doseLabel: "第1剂", monthDue: 0, prevents: "乙型肝炎"),
        .init(id: "BCG-1", vaccine: "卡介苗", shortName: "卡介苗", doseLabel: "第1剂", monthDue: 0, prevents: "结核病"),
        .init(id: "HepB-2", vaccine: "乙肝疫苗", shortName: "乙肝", doseLabel: "第2剂", monthDue: 1, prevents: "乙型肝炎"),
        .init(id: "IPV-1", vaccine: "脊灰灭活疫苗", shortName: "脊灰", doseLabel: "第1剂", monthDue: 2, prevents: "脊髓灰质炎"),
        .init(id: "DTaP-1", vaccine: "百白破疫苗", shortName: "百白破", doseLabel: "第1剂", monthDue: 3, prevents: "百日咳/白喉/破伤风"),
        .init(id: "IPV-2", vaccine: "脊灰灭活疫苗/二价", shortName: "脊灰", doseLabel: "第2剂", monthDue: 3, prevents: "脊髓灰质炎"),
        .init(id: "DTaP-2", vaccine: "百白破疫苗", shortName: "百白破", doseLabel: "第2剂", monthDue: 4, prevents: "百日咳/白喉/破伤风"),
        .init(id: "OPV-3", vaccine: "脊灰减毒活疫苗", shortName: "脊灰", doseLabel: "第3剂", monthDue: 4, prevents: "脊髓灰质炎"),
        .init(id: "DTaP-3", vaccine: "百白破疫苗", shortName: "百白破", doseLabel: "第3剂", monthDue: 5, prevents: "百日咳/白喉/破伤风"),
        .init(id: "HepB-3", vaccine: "乙肝疫苗", shortName: "乙肝", doseLabel: "第3剂", monthDue: 6, prevents: "乙型肝炎"),
        .init(id: "MenA-1", vaccine: "A群流脑多糖疫苗", shortName: "流脑A", doseLabel: "第1剂", monthDue: 6, prevents: "流行性脑脊髓膜炎"),
        .init(id: "MenA-2", vaccine: "A群流脑多糖疫苗", shortName: "流脑A", doseLabel: "第2剂", monthDue: 9, prevents: "流行性脑脊髓膜炎"),
        .init(id: "MMR-1", vaccine: "麻腮风疫苗", shortName: "麻腮风", doseLabel: "第1剂", monthDue: 8, prevents: "麻疹/腮腺炎/风疹"),
        .init(id: "JE-1", vaccine: "乙脑减毒活疫苗", shortName: "乙脑", doseLabel: "第1剂", monthDue: 8, prevents: "流行性乙型脑炎"),
        .init(id: "MMR-2", vaccine: "麻腮风疫苗", shortName: "麻腮风", doseLabel: "第2剂", monthDue: 18, prevents: "麻疹/腮腺炎/风疹"),
        .init(id: "DTaP-4", vaccine: "百白破疫苗", shortName: "百白破", doseLabel: "第4剂", monthDue: 18, prevents: "百日咳/白喉/破伤风"),
        .init(id: "HepA-1", vaccine: "甲肝减毒活疫苗", shortName: "甲肝", doseLabel: "第1剂", monthDue: 18, prevents: "甲型肝炎"),
        .init(id: "JE-2", vaccine: "乙脑减毒活疫苗", shortName: "乙脑", doseLabel: "第2剂", monthDue: 24, prevents: "流行性乙型脑炎"),
        .init(id: "MenAC-1", vaccine: "A群C群流脑多糖疫苗", shortName: "流脑AC", doseLabel: "第3剂", monthDue: 36, prevents: "流行性脑脊髓膜炎"),
        .init(id: "DTaP-5", vaccine: "白破疫苗", shortName: "白破", doseLabel: "加强", monthDue: 72, prevents: "白喉/破伤风"),
        .init(id: "OPV-4", vaccine: "脊灰减毒活疫苗", shortName: "脊灰", doseLabel: "第4剂", monthDue: 48, prevents: "脊髓灰质炎"),
        .init(id: "MenAC-2", vaccine: "A群C群流脑多糖疫苗", shortName: "流脑AC", doseLabel: "第4剂", monthDue: 72, prevents: "流行性脑脊髓膜炎"),
    ]

    /// 推荐接种的大致日期（基于生日 + monthDue）。
    func dueDate(birthday: Date) -> Date {
        Calendar.current.date(byAdding: .month, value: monthDue, to: birthday) ?? birthday
    }
}
