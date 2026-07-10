import Foundation
import SwiftData
import UserNotifications

// MARK: - 通知直接回复（零操作记录：锁屏上答一句就成时光）
/// 「那年今日 / 今日一问」提醒带一个文字输入动作，用户在通知上直接打字回答 → 后台落一条记录。
/// App 未运行时系统会把它拉起到后台处理，记录仍会保存，下次前台自动同步。
@MainActor
final class NotificationReplyHandler: NSObject {
    static let shared = NotificationReplyHandler()

    static let categoryId = "bubu.reply"
    static let replyActionId = "bubu.reply.text"

    /// App 启动时调用：注册回复类目 + 设为通知中心代理。
    func register() {
        let center = UNUserNotificationCenter.current()
        let action = UNTextInputNotificationAction(
            identifier: Self.replyActionId,
            title: "回一句",
            options: [],
            textInputButtonTitle: "记下",
            textInputPlaceholder: "此刻的布布…")
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [action],
            intentIdentifiers: [],
            options: [])
        center.setNotificationCategories([category])
        center.delegate = self
    }
}

extension NotificationReplyHandler: UNUserNotificationCenterDelegate {
    /// 前台时也允许横幅展示（否则 App 开着收不到那年今日提醒）。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let textResponse = response as? UNTextInputNotificationResponse else { return }
        let text = textResponse.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await MainActor.run {
            guard let context = SharedModelContainer.sharedIfAvailable?.mainContext else { return }
            let role = SharedDefaults.currentRole
            try? EntryWriter.quickTextEntry(note: text, role: role, in: context)
            // 复用手表那条通知，让 App 前台时立刻同步 + 刷新
            NotificationCenter.default.post(name: WatchConnectivityManager.didRecordNotification, object: nil)
        }
    }
}
