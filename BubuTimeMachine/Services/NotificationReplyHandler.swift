import Foundation
import OSLog
import SwiftData
import UserNotifications

// MARK: - 通知直接回复（零操作记录：锁屏上答一句就成时光）
/// 「那年今日 / 今日一问」提醒带一个文字输入动作，用户在通知上直接打字回答 → 后台落一条记录。
/// App 未运行时系统会把它拉起到后台处理，记录仍会保存，下次前台自动同步。
@MainActor
final class NotificationReplyHandler: NSObject {
    static let shared = NotificationReplyHandler()

    nonisolated static let categoryId = "bubu.reply"
    nonisolated static let replyActionId = "bubu.reply.text"

    private let log = Logger(subsystem: "com.bubu.timemachine", category: "NotificationReply")
    private let inboxDirectory: @MainActor () -> URL
    private let availableContainer: @MainActor () -> ModelContainer?
    private let didRecord: @MainActor () -> Void

    /// Dependencies let tests exercise callback ordering using only temporary synthetic data.
    /// Resolving the real inbox is deliberately lazy, so a test/recovery memory container cannot
    /// read or consume the production queue during launch.
    init(
        inboxDirectory: @escaping @MainActor () -> URL = {
            BubuStorage.containerURL.appendingPathComponent("NotificationReplyInbox", isDirectory: true)
        },
        availableContainer: @escaping @MainActor () -> ModelContainer? = { SharedModelContainer.sharedIfAvailable },
        didRecord: @escaping @MainActor () -> Void = {
            NotificationCenter.default.post(name: WatchConnectivityManager.didRecordNotification, object: nil)
        }
    ) {
        self.inboxDirectory = inboxDirectory
        self.availableContainer = availableContainer
        self.didRecord = didRecord
        super.init()
    }

    /// Stage first, before asking SwiftData to open. The UUID survives retries and process death.
    func receiveReply(text: String, role: FamilyRole, id: UUID = UUID(), happenedAt: Date = .now) throws {
        let reply = NotificationReplyInbox.Reply(id: id, note: text, role: role, happenedAt: happenedAt)
        try NotificationReplyInbox(directory: inboxDirectory()).stage(reply)
        retryPendingReplies()
    }

    /// Called on healthy launch/foreground as well as after a newly staged response.
    func retryPendingReplies() {
        guard let container = availableContainer(), NotificationReplyInbox.isPersistent(container) else { return }
        let inbox = NotificationReplyInbox(directory: inboxDirectory())
        do {
            for reply in try inbox.pendingReplies() {
                do {
                    try inbox.importReply(reply, into: container)
                    // Reuse the existing sync/refresh signal only after durable readback succeeds.
                    didRecord()
                } catch {
                    log.error("通知回复仍在收件箱，稍后重试：\(error.localizedDescription, privacy: .private)")
                }
            }
        } catch {
            log.error("暂时无法读取通知回复收件箱：\(error.localizedDescription, privacy: .private)")
        }
    }

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
        guard response.actionIdentifier == Self.replyActionId,
              let textResponse = response as? UNTextInputNotificationResponse else { return }
        let text = textResponse.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await MainActor.run {
            do {
                try receiveReply(text: text, role: SharedDefaults.currentRole)
            } catch {
                // Do not claim success if even the protected inbox cannot be written (e.g. disk full).
                log.fault("通知回复未能暂存：\(error.localizedDescription, privacy: .private)")
            }
        }
    }
}
