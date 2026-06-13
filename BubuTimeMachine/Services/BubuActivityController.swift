import Foundation
import ActivityKit
import OSLog

// MARK: - Live Activity 启停控制（主 App 侧）
/// 封装 ActivityKit 的 request/update/end，全部做可用性与授权降级：
/// 用户未开启 Live Activity、系统不支持时，所有方法安静 no-op，主流程零影响。
@MainActor
enum BubuActivityController {
    private static let log = Logger(subsystem: "com.bubu.timemachine", category: "LiveActivity")

    // 当前录音 Activity 句柄（同一时刻只允许一个）。
    private static var voiceActivity: Activity<BubuActivityAttributes>?

    private static var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: 录音中

    /// 开始录音时调用：起一个录音 Live Activity。
    static func startVoiceRecording(childName: String) {
        guard isEnabled, voiceActivity == nil else { return }
        let attributes = BubuActivityAttributes(
            kind: .voiceRecording,
            title: "正在记录\(childName)的声音",
            unlockAt: nil,
            childName: childName
        )
        let state = BubuActivityAttributes.ContentState(startedAt: .now, elapsedText: "0:00")
        do {
            voiceActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            log.error("起录音 Live Activity 失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 停止录音时调用：定格时长并结束 Activity。
    static func endVoiceRecording(elapsedText: String) {
        guard voiceActivity != nil else { return }
        let final = BubuActivityAttributes.ContentState(startedAt: .now, elapsedText: elapsedText)
        voiceActivity = nil
        Task { await endAll(final: final) }
    }

    /// 结束全部进行中的录音 Activity。用 Activity.activities 遍历（值由 ActivityKit 提供，
    /// 不跨隔离域捕获我们自己的存储），规避 Swift 6 对非 Sendable Activity 的 sending 告警。
    private static func endAll(final: BubuActivityAttributes.ContentState) async {
        for activity in Activity<BubuActivityAttributes>.activities
            where activity.attributes.kind == .voiceRecording {
            await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    // MARK: 时间胶囊倒计时

    /// 为临近解锁的时间胶囊起一个倒计时 Live Activity。
    static func startCapsuleCountdown(title: String, unlockAt: Date, childName: String) {
        guard isEnabled, unlockAt > .now else { return }
        let attributes = BubuActivityAttributes(
            kind: .capsuleCountdown,
            title: title,
            unlockAt: unlockAt,
            childName: childName
        )
        let state = BubuActivityAttributes.ContentState(startedAt: .now, elapsedText: "")
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: unlockAt)
            )
        } catch {
            log.error("起胶囊倒计时 Live Activity 失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
