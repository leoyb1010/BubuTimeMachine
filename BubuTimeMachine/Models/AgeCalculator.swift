import Foundation

// MARK: - 年龄计算
/// 布布档案的生日驱动全 App 的年龄展示。所有"她当时多大"都由此计算。
enum AgeCalculator {

    /// 在某个时刻，布布的精确年龄描述："1岁11个月"、"出生第3天"、"还没出生呢"。
    static func ageDescription(birthday: Date, at date: Date) -> String {
        let cal = Calendar.current
        // 两端先归一化到当天 0 点：与 daysSinceBirth/daysUntilNextBirthday 口径一致，
        // 消除生日带随机时分秒导致的"1岁11个月却又生日快乐""出生当天显示即将出生"。
        let birth = cal.startOfDay(for: birthday)
        let now = cal.startOfDay(for: date)
        if now < birth {
            let days = cal.dateComponents([.day], from: now, to: birth).day ?? 0
            return days <= 0 ? "即将出生" : "还有\(days)天出生"
        }
        let comps = cal.dateComponents([.year, .month, .day], from: birth, to: now)
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
        let birth = cal.startOfDay(for: birthday)
        let now = cal.startOfDay(for: date)
        return max(0, cal.dateComponents([.year], from: birth, to: now).year ?? 0)
    }

    /// 紧凑年龄："1y11m"、"23d"，用于卡片角标。
    static func compactAge(birthday: Date, at date: Date) -> String {
        let cal = Calendar.current
        let birth = cal.startOfDay(for: birthday)
        let now = cal.startOfDay(for: date)
        guard now >= birth else { return "孕期" }
        let comps = cal.dateComponents([.year, .month, .day], from: birth, to: now)
        let y = comps.year ?? 0, m = comps.month ?? 0, d = comps.day ?? 0
        if y == 0 && m == 0 { return "\(d)天" }
        if y == 0 { return "\(m)月" }
        return m == 0 ? "\(y)岁" : "\(y)岁\(m)月"
    }

    // MARK: - 上学

    /// 上学第几天（开学当天算第 1 天）。还没到开学日返回 nil。
    /// 与 daysSinceBirth 同口径：两端都归一化到当天 0 点，避免入园日带时分秒时忽早忽晚。
    static func daysSinceSchoolStart(_ start: Date, at date: Date = .now) -> Int? {
        let cal = Calendar.current
        let from = cal.startOfDay(for: start)
        let to = cal.startOfDay(for: date)
        guard to >= from else { return nil }
        return (cal.dateComponents([.day], from: from, to: to).day ?? 0) + 1
    }

    /// 距离开学还有几天。开学当天及之后返回 nil。
    static func daysUntilSchoolStart(_ start: Date, from date: Date = .now) -> Int? {
        let cal = Calendar.current
        let from = cal.startOfDay(for: date)
        let to = cal.startOfDay(for: start)
        guard to > from else { return nil }
        return cal.dateComponents([.day], from: from, to: to).day
    }

    /// 一句话上学状态："还有 5 天上幼儿园" / "今天是上幼儿园第 1 天" / "上幼儿园第 23 天"。
    /// 没填入园日期返回 nil。
    static func schoolDescription(schoolStartDate: Date?, at date: Date = .now) -> String? {
        guard let start = schoolStartDate else { return nil }
        if let left = daysUntilSchoolStart(start, from: date) {
            return "还有 \(left) 天上幼儿园"
        }
        guard let day = daysSinceSchoolStart(start, at: date) else { return nil }
        return day == 1 ? "今天是上幼儿园第 1 天" : "上幼儿园第 \(day) 天"
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
