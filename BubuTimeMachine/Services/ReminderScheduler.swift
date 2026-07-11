import Foundation
import SwiftData
import UserNotifications

// MARK: - 那年今日 · 提醒调度
/// 每天上午 9:00 提醒一次：往年的今天，布布在做什么。
/// 预排未来 30 天，每天各自取对应日期的回忆 + 当年照片缩略图作附件（通知本身就是回忆）；
/// App 每次活跃时滚动刷新。另负责疫苗到期提醒（提前 3 天 + 当天，打卡后自动排下一针）。
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()
    private init() {}

    private let identifierPrefix = "bubu.onThisDay."
    private let daysAhead = 30

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
            content.body = memory.text.isEmpty
                ? "翻一翻布布的时光轴，今天也想她了吧。下滑可以直接回一句。"
                : "\(memory.text)\n下滑可以直接回一句今天的布布。"
            content.sound = .default
            content.categoryIdentifier = NotificationReplyHandler.categoryId   // 通知可直接文字回复成记录
            // 当年那天的照片直接出现在通知里（横幅长按可见大图）
            if let attachment = photoAttachment(thumbnailFileName: memory.thumbnail, key: "\(identifierPrefix)\(offset)") {
                content.attachments = [attachment]
            }

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: "\(identifierPrefix)\(offset)",
                                            content: content, trigger: trigger)
            center.add(req)
        }
    }

    /// 取指定日期「往年同月同日」的一条记录摘要 + 那天的照片缩略图。
    private func onThisDayMemory(context: ModelContext, for day: Date) -> (text: String, thumbnail: String?) {
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.happenedAt, order: .reverse)])
        guard let entries = try? context.fetch(descriptor) else { return ("", nil) }
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
                let thumb = e.media.first(where: { $0.type == .photo })?.thumbnailFileName
                let text = years > 0 ? "\(years)年前的今天（\(age)）：\(note)" : "那年今日（\(age)）：\(note)"
                return (text, thumb)
            }
        }
        return ("", nil)
    }

    /// 把缩略图复制到 tmp 供 UNNotificationAttachment 使用（系统会移动走该文件）。
    private func photoAttachment(thumbnailFileName: String?, key: String) -> UNNotificationAttachment? {
        guard let thumbnailFileName else { return nil }
        let src = BubuStorage.thumbnailDirectory.appendingPathComponent(thumbnailFileName)
        guard FileManager.default.fileExists(atPath: src.path) else { return nil }
        let ext = src.pathExtension.isEmpty ? "jpg" : src.pathExtension
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("notif_\(key).\(ext)")
        try? FileManager.default.removeItem(at: tmp)
        guard (try? FileManager.default.copyItem(at: src, to: tmp)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: key, url: tmp)
    }

    // MARK: - 疫苗到期提醒（R4 E-4）

    private let vaccinePrefix = "bubu.vaccine."

    /// 重排疫苗提醒：未打卡剂次里最近的 3 个（过期 14 天内～未来 60 天），
    /// 每剂两条：提前 3 天预告 + 到期当天上午。疫苗打卡后再调用即自动排下一针。
    func refreshVaccineReminders(context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        // 清掉旧的疫苗提醒
        let allIds = VaccineDose.schedule.flatMap { ["\(vaccinePrefix)\($0.id).pre", "\(vaccinePrefix)\($0.id).due"] }
        center.removePendingNotificationRequests(withIdentifiers: allIds)

        guard let profile = try? context.fetch(FetchDescriptor<ChildProfile>()).first else { return }
        let recorded = Set(((try? context.fetch(FetchDescriptor<VaccineRecord>())) ?? []).compactMap(\.doseId))
        let cal = Calendar.current
        let now = Date.now

        let upcoming = VaccineDose.schedule
            .filter { !recorded.contains($0.id) }
            .map { (dose: $0, due: $0.dueDate(birthday: profile.birthday)) }
            .filter { pair in
                let days = cal.dateComponents([.day], from: cal.startOfDay(for: now),
                                              to: cal.startOfDay(for: pair.due)).day ?? 0
                return days >= -14 && days <= 60
            }
            .sorted { $0.due < $1.due }
            .prefix(3)

        for (dose, due) in upcoming {
            let name = "\(dose.vaccine)·\(dose.doseLabel)"
            let dueText = BubuDateFormat.yearMonthDay(due)
            // 提前 3 天预告
            if let preDay = cal.date(byAdding: .day, value: -3, to: due), preDay > now {
                var comps = cal.dateComponents([.year, .month, .day], from: preDay)
                comps.hour = 9; comps.minute = 31
                let content = UNMutableNotificationContent()
                content.title = "疫苗预告 💉"
                content.body = "「\(name)」预计 \(dueText) 到期（\(dose.prevents)）。可以先约接种点啦～"
                content.sound = .default
                try? await center.add(UNNotificationRequest(identifier: "\(vaccinePrefix)\(dose.id).pre",
                                                            content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
            // 到期当天
            if due > now {
                var comps = cal.dateComponents([.year, .month, .day], from: due)
                comps.hour = 9; comps.minute = 31
                let content = UNMutableNotificationContent()
                content.title = "今天该打疫苗啦 💉"
                content.body = "「\(name)」今天到期（\(dose.prevents)）。打完回来说一句就自动记上～"
                content.sound = .default
                try? await center.add(UNNotificationRequest(identifier: "\(vaccinePrefix)\(dose.id).due",
                                                            content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
        }
    }
}
