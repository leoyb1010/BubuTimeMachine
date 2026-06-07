import Foundation
import SwiftData
import UserNotifications

// MARK: - 那年今日 · 提醒调度
/// 每天固定时间提醒一次：往年的今天，布布在做什么。
/// 内容在 App 在前台时从 SwiftData 实时取；为保证后台也能触发，
/// 注册一个每日重复的本地通知，文案在 App 活跃时刷新。
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()
    private init() {}

    private let identifier = "bubu.onThisDay.daily"

    /// 开关变化时调用。
    func update(enabled: Bool, context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        if enabled {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return }
            scheduleDaily(center: center, context: context)
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
        }
    }

    /// App 启动时按开关状态刷新（文案用最新数据）。
    func refreshIfEnabled(enabled: Bool, context: ModelContext) {
        guard enabled else { return }
        scheduleDaily(center: .current(), context: context)
    }

    private func scheduleDaily(center: UNUserNotificationCenter, context: ModelContext) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let memories = onThisDayMemories(context: context)
        let content = UNMutableNotificationContent()
        content.title = "那年今日 · 布布时光机"
        content.body = memories.isEmpty
            ? "翻一翻布布的时光轴，今天也想她了吧。"
            : memories
        content.sound = .default

        // 每天上午 9:00
        var date = DateComponents()
        date.hour = 9
        date.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(req)
    }

    /// 取"往年同月同日"的一条记录摘要。
    private func onThisDayMemories(context: ModelContext) -> String {
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.happenedAt, order: .reverse)])
        guard let entries = try? context.fetch(descriptor) else { return "" }
        let cal = Calendar.current
        let today = cal.dateComponents([.month, .day], from: .now)
        let profile = try? context.fetch(FetchDescriptor<ChildProfile>()).first

        for e in entries {
            let c = cal.dateComponents([.month, .day], from: e.happenedAt)
            let pastYear = !cal.isDate(e.happenedAt, inSameDayAs: .now)
            if c.month == today.month && c.day == today.day && pastYear {
                let years = cal.dateComponents([.year], from: e.happenedAt, to: .now).year ?? 0
                let age = profile.map { AgeCalculator.ageDescription(birthday: $0.birthday, at: e.happenedAt) } ?? ""
                let note = e.note ?? "那天的布布"
                return "\(years)年前的今天（\(age)）：\(note)"
            }
        }
        return ""
    }
}
