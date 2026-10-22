import Foundation
#if !targetEnvironment(macCatalyst)
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

    // MARK: 哄睡计时（R4 E-3）

    /// 开始哄睡：锁屏/灵动岛实时计时（Text(timerInterval:) 系统自走，零耗电 update）。
    static func startSleepTimer(childName: String, startedAt: Date) {
        guard isEnabled else { return }
        let attributes = BubuActivityAttributes(
            kind: .sleepTimer,
            title: "\(childName)睡着啦",
            unlockAt: nil,
            childName: childName
        )
        let state = BubuActivityAttributes.ContentState(startedAt: startedAt, elapsedText: "")
        do {
            _ = try Activity.request(attributes: attributes,
                                     content: .init(state: state, staleDate: nil))
        } catch {
            log.error("起哄睡 Live Activity 失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 结束哄睡计时。
    static func endSleepTimer(elapsedText: String) {
        Task {
            let final = BubuActivityAttributes.ContentState(startedAt: .now, elapsedText: elapsedText)
            for activity in Activity<BubuActivityAttributes>.activities
                where activity.attributes.kind == .sleepTimer {
                await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate)
            }
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

    // MARK: 课程上传 / 解析

    /// 正在跟踪的课程（创建成功后才有 id）。同一时刻只跟踪一节课。
    private static var courseUploadID: String?
    private static var courseUploadStartedAt: Date?
    private static var lastCourseUploadState: BubuActivityAttributes.ContentState?
    /// 解析可能要几十分钟；超过这个时间仍没结果就收起，避免锁屏一直挂着。
    static let courseUploadTimeout: TimeInterval = 45 * 60

    /// 点「上传」时调用。已有上传 Activity 时先结束旧的。
    static func startCourseUpload(title: String, childName: String) {
        endCourseUploadActivities(final: nil)
        courseUploadID = nil
        courseUploadStartedAt = .now
        lastCourseUploadState = nil
        guard isEnabled else { return }
        let attributes = BubuActivityAttributes(kind: .courseUpload, title: title, unlockAt: nil, childName: childName)
        let state = BubuActivityAttributes.ContentState(startedAt: .now, elapsedText: "",
                                                        uploadPhase: .compressing, progress: 0)
        do {
            _ = try Activity.request(attributes: attributes,
                                     content: .init(state: state, staleDate: .now.addingTimeInterval(courseUploadTimeout)))
            lastCourseUploadState = state
        } catch {
            log.error("起课程上传 Live Activity 失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 课程已在服务端创建：之后由首页轮询按课程状态推进。
    static func attachCourseUpload(courseID: String) {
        courseUploadID = courseID
    }

    /// 压缩/上传过程中的进度。压缩进度按 5% 一档节流，避免频繁刷新锁屏。
    static func updateCourseUpload(phase: CourseUploadActivityPhase, progress: Double? = nil,
                                   step: Int? = nil, steps: Int? = nil) {
        let state = BubuActivityAttributes.ContentState(startedAt: courseUploadStartedAt ?? .now, elapsedText: "",
                                                        uploadPhase: phase, progress: progress, step: step, steps: steps)
        if let last = lastCourseUploadState, last.uploadPhase == phase, last.step == step,
           abs((last.progress ?? 0) - (progress ?? 0)) < 0.05 { return }
        lastCourseUploadState = state
        if phase.isTerminal {
            finishCourseUpload(state)
            return
        }
        Task {
            for activity in Activity<BubuActivityAttributes>.activities where activity.attributes.kind == .courseUpload {
                await activity.update(.init(state: state, staleDate: .now.addingTimeInterval(courseUploadTimeout)))
            }
        }
    }

    /// 上传本身失败（课程已删除）：显示温和的失败态后收起。
    static func failCourseUpload() {
        courseUploadID = nil
        updateCourseUpload(phase: .failed)
    }

    /// 首页每次拿到课程列表时调用：跟踪的课程到了草稿/失败就结束；超时也结束。
    static func syncCourseUpload(with courses: [(id: String, state: String)]) {
        guard let id = courseUploadID else { return }
        if let started = courseUploadStartedAt, Date.now.timeIntervalSince(started) > courseUploadTimeout {
            courseUploadID = nil
            endCourseUploadActivities(final: nil)
            return
        }
        guard let course = courses.first(where: { $0.id == id }),
              let phase = CourseUploadActivityPhase.from(courseState: course.state),
              phase != .uploading else { return }
        if phase.isTerminal { courseUploadID = nil }
        updateCourseUpload(phase: phase)
    }

    private static func finishCourseUpload(_ state: BubuActivityAttributes.ContentState) {
        courseUploadID = nil
        endCourseUploadActivities(final: state)
    }

    private static func endCourseUploadActivities(final: BubuActivityAttributes.ContentState?) {
        // 先同步记下要结束的是哪几个，避免异步执行时把紧接着新起的上传 Activity 一起结束。
        let ids = Set(Activity<BubuActivityAttributes>.activities
            .filter { $0.attributes.kind == .courseUpload }.map(\.id))
        guard !ids.isEmpty else { return }
        Task {
            for activity in Activity<BubuActivityAttributes>.activities where ids.contains(activity.id) {
                if let final {
                    // 结果在锁屏停留几分钟，家长解锁就能看到「草稿可审核」；失败只停留一小会儿。
                    let linger: TimeInterval = final.uploadPhase == .ready ? 10 * 60 : 2 * 60
                    await activity.end(.init(state: final, staleDate: nil),
                                       dismissalPolicy: .after(.now.addingTimeInterval(linger)))
                } else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }
}
#else
/// Catalyst 没有锁屏 Live Activity；Mac 档案馆保留同一调用面并安静降级。
@MainActor
enum BubuActivityController {
    static func startVoiceRecording(childName: String) {}
    static func endVoiceRecording(elapsedText: String) {}
    static func startSleepTimer(childName: String, startedAt: Date) {}
    static func endSleepTimer(elapsedText: String) {}
    static func startCapsuleCountdown(title: String, unlockAt: Date, childName: String) {}
    static func startCourseUpload(title: String, childName: String) {}
    static func attachCourseUpload(courseID: String) {}
    static func updateCourseUpload(phase: CourseUploadActivityPhase, progress: Double? = nil,
                                   step: Int? = nil, steps: Int? = nil) {}
    static func failCourseUpload() {}
    static func syncCourseUpload(with courses: [(id: String, state: String)]) {}
}
#endif
