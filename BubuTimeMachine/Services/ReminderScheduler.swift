import Foundation
import SwiftData
import UserNotifications

// MARK: - 那年今日 · 提醒调度
/// 每天上午 9:00 提醒一次：往年的今天，布布在做什么。
/// 旧实现是「单条 repeats=true 通知」——文案在 App 打开那天算好后每天重复，
/// 第二天起内容必然过期/错误。现改为预排未来 7 天，每天各自取对应日期的回忆；
/// App 每次活跃时滚动刷新这 7 天。
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()
    private init() {}

    private let identifierPrefix = "bubu.onThisDay."
    private let daysAhead = 7

    private var allIdentifiers: [String] {
        (0..<daysAhead).map { "\(identifierPrefix)\($0)" }
    }

    /// 开关变化时调用。
    func update(enabled: Bool, context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        if enabled {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return }
            scheduleWeekAhead(center: center, context: context)
        } else {
            center.removePendingNotificationRequests(withIdentifiers: allIdentifiers + ["bubu.onThisDay.daily"])
        }
    }

    /// App 启动时按开关状态刷新（滚动重排未来 7 天）。
    func refreshIfEnabled(enabled: Bool, context: ModelContext) {
        guard enabled else { return }
        scheduleWeekAhead(center: .current(), context: context)
    }

    private func scheduleWeekAhead(center: UNUserNotificationCenter, context: ModelContext) {
        // 连旧版的单条重复通知一起清掉
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers + ["bubu.onThisDay.daily"])

        let cal = Calendar.current
        for offset in 0..<daysAhead {
            guard let day = cal.date(byAdding: .day, value: offset, to: .now) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = 9
            comps.minute = 0
            // 今天 9 点已过则跳过今天
            if let fireDate = cal.date(from: comps), fireDate <= .now { continue }

            let content = UNMutableNotificationContent()
            content.title = "那年今日 · 布布时光机"
            let memory = onThisDayMemory(context: context, for: day)
            content.body = memory.isEmpty
                ? "翻一翻布布的时光轴，今天也想她了吧。下滑可以直接回一句。"
                : "\(memory)\n下滑可以直接回一句今天的布布。"
            content.sound = .default
            content.categoryIdentifier = NotificationReplyHandler.categoryId   // 通知可直接文字回复成记录

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: "\(identifierPrefix)\(offset)",
                                            content: content, trigger: trigger)
            center.add(req)
        }
    }

    /// 取指定日期「往年同月同日」的一条记录摘要。
    private func onThisDayMemory(context: ModelContext, for day: Date) -> String {
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.happenedAt, order: .reverse)])
        guard let entries = try? context.fetch(descriptor) else { return "" }
        let cal = Calendar.current
        let target = cal.dateComponents([.month, .day], from: day)
        let profile = try? context.fetch(FetchDescriptor<ChildProfile>()).first

        for e in entries {
            let c = cal.dateComponents([.month, .day], from: e.happenedAt)
            let pastYear = !cal.isDate(e.happenedAt, inSameDayAs: day)
            if c.month == target.month && c.day == target.day && pastYear {
                let years = cal.dateComponents([.year], from: e.happenedAt, to: day).year ?? 0
                let age = profile.map { AgeCalculator.ageDescription(birthday: $0.birthday, at: e.happenedAt) } ?? ""
                let note = e.note ?? "那天的布布"
                return years > 0 ? "\(years)年前的今天（\(age)）：\(note)" : "那年今日（\(age)）：\(note)"
            }
        }
        return ""
    }
}
