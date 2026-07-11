import Foundation

// MARK: - 年龄计算
/// 布布档案的生日驱动全 App 的年龄展示。所有"她当时多大"都由此计算。
enum AgeCalculator {

    /// 在某个时刻，布布的精确年龄描述："1岁11个月"、"出生第3天"、"还没出生呢"。
    static func ageDescription(birthday: Date, at date: Date) -> String {
        let cal = Calendar.current
        if date < birthday {
            let days = cal.dateComponents([.day], from: date, to: birthday).day ?? 0
            return days <= 0 ? "即将出生" : "还有\(days)天出生"
        }
        let comps = cal.dateComponents([.year, .month, .day], from: birthday, to: date)
        let y = comps.year ?? 0, m = comps.month ?? 0, d = comps.day ?? 0
        if y == 0 && m == 0 {
            return d == 0 ? "出生当天" : "出生第\(d)天"
        }
        if y == 0 {
            return d == 0 ? "\(m)个月" : "\(m)个月\(d)天"
        }
        if m == 0 {
            return d == 0 ? "\(y)岁" : "\(y)岁\(d)天"
        }
        return "\(y)岁\(m)个月"
    }

    /// 来到世界第几天（从出生当天算第 1 天）。
    static func daysSinceBirth(birthday: Date, at date: Date = .now) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: birthday)
        let end = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, days) + 1
    }

    /// 当前是第几岁（用于成长之声、年度电影归档）。0 表示未满 1 岁。
    static func ageYears(birthday: Date, at date: Date = .now) -> Int {
        let cal = Calendar.current
        return max(0, cal.dateComponents([.year], from: birthday, to: date).year ?? 0)
    }

    /// 紧凑年龄："1y11m"、"23d"，用于卡片角标。
    static func compactAge(birthday: Date, at date: Date) -> String {
        let cal = Calendar.current
        guard date >= birthday else { return "孕期" }
        let comps = cal.dateComponents([.year, .month, .day], from: birthday, to: date)
        let y = comps.year ?? 0, m = comps.month ?? 0, d = comps.day ?? 0
        if y == 0 && m == 0 { return "\(d)天" }
        if y == 0 { return "\(m)月" }
        return m == 0 ? "\(y)岁" : "\(y)岁\(m)月"
    }

    /// 距离下个生日还有几天。
    static func daysUntilNextBirthday(birthday: Date, from date: Date = .now) -> Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.month, .day], from: birthday)
        // 生日【当天】就是 0 天：nextDate(after:) 会跳到明年，导致当天显示"还有365天"、
        // 小组件"生日快乐🎂"分支永不可达（R4 P2-39）
        let today = cal.dateComponents([.month, .day], from: date)
        if today.month == comps.month && today.day == comps.day { return 0 }
        guard let next = cal.nextDate(after: date, matching: comps,
                                      matchingPolicy: .nextTime) else { return 0 }
        return cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                  to: cal.startOfDay(for: next)).day ?? 0
    }
}
