import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - AgeCalculator 地基函数回归测试
/// AgeCalculator 是全 App「她当时多大」的唯一真源，被 iPhone 主 App、iPhone 小组件、
/// 手表 App、手表复杂功能共享。C-P1-5 修复：四个方法两端统一 startOfDay 归一化，口径一致。
/// 本套件锁定：生日当天不再"忽早忽晚"、出生当天不显示"即将出生"、四方法互不打架、闰年 2/29 行为明确。
@MainActor
struct AgeCalculatorTests {

    /// 用设备时区（AgeCalculator 内部一律 Calendar.current）构造带时分秒的日期。
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        return Calendar.current.date(from: c)!
    }

    // MARK: 1. 生日当天早晨——核心 bug：生日带时分秒、at 更早时刻，不得差一天

    @Test("周岁生日当天早晨：生日带14:23，at为当天09:00，显示整岁且倒计时=0，四方法口径一致")
    func birthdayMorningNoOffByOne() {
        let birthday = date(2023, 3, 5, 14, 23, 0)   // 出生时刻带随机时分秒
        let at = date(2025, 3, 5, 9, 0, 0)           // 两周岁生日当天早上（早于出生时刻）

        // ageDescription 必须是"2岁"，绝不能是"1岁11个月"（旧 bug：at 早于生日时刻被算少一天）
        #expect(AgeCalculator.ageDescription(birthday: birthday, at: at) == "2岁")
        // 生日当天倒计时必须为 0（让手表"生日快乐🎂"分支可达）
        #expect(AgeCalculator.daysUntilNextBirthday(birthday: birthday, from: at) == 0)
        // 口径一致性：整岁与倒计时=0 同时成立，不再出现"1岁11个月 + 生日快乐"同框
        #expect(AgeCalculator.ageYears(birthday: birthday, at: at) == 2)
        #expect(AgeCalculator.compactAge(birthday: birthday, at: at) == "2岁")
    }

    // MARK: 2. 出生当天——at 早于/晚于出生时刻都应"出生当天/第1天"，绝不"即将出生"

    @Test("出生当天，at早于出生时刻：显示出生当天而非即将出生")
    func birthDayEarlierThanBirthTime() {
        let birthday = date(2025, 7, 1, 14, 0, 0)
        let at = date(2025, 7, 1, 9, 0, 0)           // 比出生时刻早（旧 bug 触发"即将出生"）
        #expect(AgeCalculator.ageDescription(birthday: birthday, at: at) == "出生当天")
        #expect(AgeCalculator.compactAge(birthday: birthday, at: at) == "0天")
        // 来到世界第 1 天（1-based）
        #expect(AgeCalculator.daysSinceBirth(birthday: birthday, at: at) == 1)
    }

    @Test("出生当天，at晚于出生时刻：显示出生当天")
    func birthDayLaterThanBirthTime() {
        let birthday = date(2025, 7, 1, 14, 0, 0)
        let at = date(2025, 7, 1, 20, 0, 0)
        #expect(AgeCalculator.ageDescription(birthday: birthday, at: at) == "出生当天")
        #expect(AgeCalculator.daysSinceBirth(birthday: birthday, at: at) == 1)
    }

    // MARK: 3. 整岁 / 非整龄

    @Test("正好N岁：只显示岁数")
    func exactYears() {
        let birthday = date(2020, 6, 15, 8, 30, 0)
        let at = date(2025, 6, 15, 0, 0, 0)
        #expect(AgeCalculator.ageDescription(birthday: birthday, at: at) == "5岁")
        #expect(AgeCalculator.ageYears(birthday: birthday, at: at) == 5)
    }

    @Test("非整龄：1岁11个月的常见展示")
    func partialAge() {
        let birthday = date(2023, 4, 5, 0, 0, 0)
        let at = date(2025, 3, 5, 0, 0, 0)           // 1岁11个月（还差一个月满2岁）
        #expect(AgeCalculator.ageDescription(birthday: birthday, at: at) == "1岁11个月")
        #expect(AgeCalculator.ageYears(birthday: birthday, at: at) == 1)
        #expect(AgeCalculator.compactAge(birthday: birthday, at: at) == "1岁11月")
    }

    @Test("满月前：出生第N天与月龄")
    func infantDays() {
        let birthday = date(2025, 7, 1, 10, 0, 0)
        let d3 = date(2025, 7, 3, 6, 0, 0)
        #expect(AgeCalculator.ageDescription(birthday: birthday, at: d3) == "出生第2天")
        #expect(AgeCalculator.daysSinceBirth(birthday: birthday, at: d3) == 3) // 1-based：第3天
    }

    // MARK: 4. 闰年 2/29——平年倒计时明确落在真实 2/29

    @Test("闰年2/29生日：平年内倒计时落在下一个『观察日』3/1（当前实现行为，非2/29）")
    func leapDayBirthdayCountdownFromNonLeapYear() {
        // 现状说明：daysUntilNextBirthday 用 nextDate(matching: 2/29, .nextTime)。
        // 平年不存在 2/29，.nextTime 会把它解析到紧邻的下一刻——即『3/1』，
        // 而不是"跳到下一个闰年的真实 2/29"。因此 2/29 宝宝在平年按 3/1 过生日。
        // 该方法本次修复未改动，此断言锁定既有行为，防后续回归。
        let birthday = date(2024, 2, 29, 0, 0, 0)
        let from = date(2025, 3, 1, 0, 0, 0)         // 平年、已过2月

        let days = AgeCalculator.daysUntilNextBirthday(birthday: birthday, from: from)
        #expect(days > 0)
        // from + days 落在下一个 3/1（2026-03-01）
        let cal = Calendar.current
        let target = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: from))!
        let comps = cal.dateComponents([.month, .day], from: target)
        #expect(comps.month == 3 && comps.day == 1)
    }

    @Test("闰年2/29生日：当天（2028-02-29）倒计时=0")
    func leapDayBirthdayOnTheDay() {
        let birthday = date(2024, 2, 29, 0, 0, 0)
        let onDay = date(2028, 2, 29, 9, 0, 0)
        #expect(AgeCalculator.daysUntilNextBirthday(birthday: birthday, from: onDay) == 0)
        #expect(AgeCalculator.ageDescription(birthday: birthday, at: onDay) == "4岁")
    }

    // MARK: 5. 归一化健壮性——生日随机时分秒不改变任何结果（跨"时区口径"证明）

    @Test("生日带任意时分秒与归一化到0点，四方法结果完全一致")
    func timeComponentsDoNotAffectResults() {
        // AgeCalculator 四方法一律用 Calendar.current 做 startOfDay，无跨方法时区漂移。
        // 这里证明：同一日历日下，生日的时分秒被彻底抹除——带时分秒 == 归一化到0点。
        let withTime = date(2023, 3, 5, 23, 59, 59)
        let normalized = date(2023, 3, 5, 0, 0, 0)
        let at = date(2025, 8, 20, 11, 11, 11)

        #expect(AgeCalculator.ageDescription(birthday: withTime, at: at)
                == AgeCalculator.ageDescription(birthday: normalized, at: at))
        #expect(AgeCalculator.daysSinceBirth(birthday: withTime, at: at)
                == AgeCalculator.daysSinceBirth(birthday: normalized, at: at))
        #expect(AgeCalculator.ageYears(birthday: withTime, at: at)
                == AgeCalculator.ageYears(birthday: normalized, at: at))
        #expect(AgeCalculator.compactAge(birthday: withTime, at: at)
                == AgeCalculator.compactAge(birthday: normalized, at: at))
        #expect(AgeCalculator.daysUntilNextBirthday(birthday: withTime, from: at)
                == AgeCalculator.daysUntilNextBirthday(birthday: normalized, from: at))
    }

    @Test("孕期：at早于出生日（跨日）显示还有N天出生")
    func prenatal() {
        let birthday = date(2025, 7, 10, 0, 0, 0)
        let at = date(2025, 7, 1, 0, 0, 0)
        #expect(AgeCalculator.ageDescription(birthday: birthday, at: at) == "还有9天出生")
        #expect(AgeCalculator.compactAge(birthday: birthday, at: at) == "孕期")
    }
}
