import Foundation
import BackgroundTasks
import SwiftData
import UserNotifications

// MARK: - 后台补拉（R4 G-2）
/// App 进后台后，系统择机唤醒补一轮同步：家人白天发的照片，晚上打开 App 前就已经拉好。
/// BGAppRefresh 由系统按使用习惯调度（通常每天数次），失败/被杀不影响任何主流程。
@MainActor
enum BackgroundRefresher {
    static let refreshID = "com.bubu.timemachine.refresh"

    private static var syncRunner: (@MainActor () async -> Void)?

    /// App 启动早期注册（必须在 didFinishLaunching 前后立即调用）。
    static func register(runner: @escaping @MainActor () async -> Void) {
        syncRunner = runner
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: nil) { task in
            Task { @MainActor in
                await handle(task: task)
            }
        }
    }

    /// 进后台时排下一次唤醒。
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)   // 最早半小时后
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(task: BGTask) async {
        scheduleNext()   // 链式：每次醒来先排下一次
        task.expirationHandler = { }
        await syncRunner?()
        task.setTaskCompleted(success: true)
    }
}

// MARK: - 备份提醒（R4 G-6 轻量版）
/// 自托管家庭的最后保险：每月 1 号提醒做一次全量导出备份（导出功能已有，就差想起来）。
@MainActor
enum BackupReminder {
    private static let id = "bubu.backup.monthly"

    static func scheduleIfAuthorized() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
        let pending = await center.pendingNotificationRequests()
        guard !pending.contains(where: { $0.identifier == id }) else { return }

        var comps = DateComponents()
        comps.day = 1; comps.hour = 10; comps.minute = 3
        let content = UNMutableNotificationContent()
        content.title = "给布布的时光做个备份 📦"
        content.body = "每月一次：到 设置 → 导出，把全部记录导出存到电脑或硬盘。自托管的最后一道保险。"
        content.sound = .default
        try? await center.add(UNNotificationRequest(
            identifier: id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }
}
