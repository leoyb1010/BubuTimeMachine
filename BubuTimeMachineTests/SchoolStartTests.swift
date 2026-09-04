import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 上幼儿园相关口径回归
/// 入园是这个产品内容模型的分水岭：之前家长全天在场、观察即记录；
/// 入园后白天六成清醒时间家长看不见，题库、里程碑和首页文案都要跟着换。
/// 这套测试锁定三件事：天数口径不差一天、题库确实按入园切换、幼儿园预设不与旧预设撞名。
@MainActor
struct SchoolStartTests {

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return Calendar.current.date(from: c)!
    }

    // MARK: 天数口径

    @Test("开学当天是第 1 天，不是第 0 天；且入园日带时分秒也不受影响")
    func firstDayIsDayOne() {
        // 入园日带一个随机时刻：DatePicker 的初值会带当前时分秒，
        // 与生日字段同样的坑（C-P1-5），这里必须两端归一化到当天 0 点。
        let start = date(2026, 9, 9, 14, 37)
        let morningOfFirstDay = date(2026, 9, 9, 7, 30)   // 早于入园日的时刻

        #expect(AgeCalculator.daysSinceSchoolStart(start, at: morningOfFirstDay) == 1)
        // 开学当天不该再显示倒计时
        #expect(AgeCalculator.daysUntilSchoolStart(start, from: morningOfFirstDay) == nil)
        #expect(AgeCalculator.schoolDescription(schoolStartDate: start, at: morningOfFirstDay)
                == "今天是上幼儿园第 1 天")
    }

    @Test("开学前只给倒计时，不给天数")
    func beforeSchoolShowsCountdown() {
        let start = date(2026, 9, 9)
        let fiveDaysBefore = date(2026, 9, 4, 23, 10)

        #expect(AgeCalculator.daysUntilSchoolStart(start, from: fiveDaysBefore) == 5)
        #expect(AgeCalculator.daysSinceSchoolStart(start, at: fiveDaysBefore) == nil)
        #expect(AgeCalculator.schoolDescription(schoolStartDate: start, at: fiveDaysBefore)
                == "还有 5 天上幼儿园")
    }

    @Test("开学之后按第 N 天累计")
    func afterSchoolCountsUp() {
        let start = date(2026, 9, 9)
        #expect(AgeCalculator.daysSinceSchoolStart(start, at: date(2026, 9, 10)) == 2)
        #expect(AgeCalculator.daysSinceSchoolStart(start, at: date(2026, 10, 9)) == 31)
        #expect(AgeCalculator.schoolDescription(schoolStartDate: start, at: date(2026, 10, 9))
                == "上幼儿园第 31 天")
    }

    @Test("没填入园日期时，整套上学口径保持沉默")
    func noSchoolDateStaysQuiet() {
        #expect(AgeCalculator.schoolDescription(schoolStartDate: nil) == nil)
    }

    // MARK: 题库切换

    @Test("已开学一律走幼儿园题库，且问的是布布本人")
    func kindergartenBucketTakesOverAfterEnrollment() {
        // 三岁半：按月龄本来落在 child 桶
        let birthday = date(2023, 2, 4)
        let start = date(2026, 9, 9)
        let afterSchool = date(2026, 9, 20)

        let withSchool = DailyQuestion.todays(birthday: birthday, schoolStartDate: start, on: afterSchool)
        let withoutSchool = DailyQuestion.todays(birthday: birthday, schoolStartDate: nil, on: afterSchool)
        #expect(withSchool != withoutSchool, "填了入园日期就该换一套题，否则等于没切桶")
        // 幼儿园题库是问孩子的，家长照着念——所以必须是第二人称。
        #expect(withSchool.contains("你") || withSchool.contains("幼儿园"))
    }

    @Test("开学前不提前切桶：还没上学就问「今天在幼儿园」是错的")
    func bucketDoesNotSwitchBeforeFirstDay() {
        let birthday = date(2023, 2, 4)
        let start = date(2026, 9, 9)
        let beforeSchool = date(2026, 9, 4)

        let a = DailyQuestion.todays(birthday: birthday, schoolStartDate: start, on: beforeSchool)
        let b = DailyQuestion.todays(birthday: birthday, schoolStartDate: nil, on: beforeSchool)
        #expect(a == b)
    }

    @Test("同一天全家看到同一题；换一天要换题")
    func questionIsStablePerDayAndRotates() {
        let birthday = date(2023, 2, 4)
        let start = date(2026, 9, 9)
        let day1 = DailyQuestion.todays(birthday: birthday, schoolStartDate: start, on: date(2026, 9, 20, 8, 0))
        let day1Evening = DailyQuestion.todays(birthday: birthday, schoolStartDate: start, on: date(2026, 9, 20, 21, 0))
        let day2 = DailyQuestion.todays(birthday: birthday, schoolStartDate: start, on: date(2026, 9, 21, 8, 0))

        #expect(day1 == day1Evening, "同一天必须同一题，否则爸妈看到的不是一道题")
        #expect(day1 != day2)
    }

    // MARK: 里程碑预设

    @Test("幼儿园预设已加入，且不与既有预设撞名")
    func kindergartenMilestonesAreUniqueByTitle() {
        let presets = MilestoneTemplate.presets
        let kindergarten = presets.filter { $0.category == "幼儿园" }
        #expect(kindergarten.count == 12)

        // 撞名会被 MilestoneDedupe / SyncEngine 的同标题去重物理删掉一条，
        // 所以预设库自身必须全局唯一。
        let titles = presets.map(\.title)
        #expect(Set(titles).count == titles.count, "预设库出现同名条目，会被去重逻辑删掉")
        // 「第一天上幼儿园」是这批里唯一不可重来的一条，必须在。
        #expect(titles.contains("第一天上幼儿园"))
    }
}
