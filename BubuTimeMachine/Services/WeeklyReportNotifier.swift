import Foundation
import UserNotifications

/// SSE 收到新周报后发一条不含家庭正文的本地通知。
@MainActor
enum WeeklyReportNotifier {
    private static let latestKey = "bubu.weeklyReport.notifiedId"

    static func notifyIfNew(_ report: WeeklyReport) async {
        guard report.status == "ready",
              UserDefaults.standard.string(forKey: latestKey) != report.id else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard !Task.isCancelled else { return }
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "布布周报写好了"
        content.body = "这一周的小事已经整理好，每一段都附有原记录出处。"
        content.sound = .default
        guard !Task.isCancelled else { return }
        do {
            try await center.add(UNNotificationRequest(
                identifier: "bubu.weeklyReport.\(report.id)", content: content, trigger: nil))
            UserDefaults.standard.set(report.id, forKey: latestKey)
        } catch {
            // 不落 marker；系统暂时失败时，下次 SSE/重连还能安全重试同一通知 id。
        }
    }
}
