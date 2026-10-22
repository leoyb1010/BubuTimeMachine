import Foundation
#if !targetEnvironment(macCatalyst)
import ActivityKit
import AppIntents
import SwiftData
#endif

// MARK: - 课程上传进度（Live Activity 与课程状态的映射，平台无关，便于测试）
/// 压缩中 x% → 上传中 n/m → 解析中 → 草稿可审核 / 失败。
nonisolated enum CourseUploadActivityPhase: String, Codable, Hashable, Sendable {
    case compressing, uploading, parsing, ready, failed

    /// 服务端课程状态 → 进度阶段。识别不了的状态返回 nil（不更新）。
    static func from(courseState state: String) -> CourseUploadActivityPhase? {
        switch state {
        case "uploading": .uploading
        case "processing", "waiting": .parsing
        case "draft", "published": .ready
        case "failed", "no_lesson": .failed
        default: nil
        }
    }

    var isTerminal: Bool { self == .ready || self == .failed }

    var symbol: String {
        switch self {
        case .compressing: "rectangle.compress.vertical"
        case .uploading: "icloud.and.arrow.up.fill"
        case .parsing: "sparkles"
        case .ready: "checkmark.seal.fill"
        case .failed: "heart.slash.fill"
        }
    }

    /// 锁屏/灵动岛的主文案。progress 0...1；step/steps 为上传第几个文件。
    func text(progress: Double? = nil, step: Int? = nil, steps: Int? = nil) -> String {
        switch self {
        case .compressing:
            let percent = Int(((progress ?? 0) * 100).rounded())
            return "压缩中 \(min(max(percent, 0), 100))%"
        case .uploading:
            if let step, let steps, steps > 1 { return "上传中 \(step)/\(steps)" }
            return "上传中"
        case .parsing: return "解析中"
        case .ready: return "草稿可审核"
        case .failed: return "没有完成"
        }
    }

    /// 锁屏上的一句说明。解析阶段 App 多半已经在后台，不能保证锁屏自己推进，所以如实说「完成后回 App 看」。
    func hint(childName: String) -> String {
        switch self {
        case .compressing, .uploading: "传完前别关掉 App，切走也会接着传"
        case .parsing: "家里的服务器在听老师的原声，完成后回 App 看看"
        case .ready: "点这里去核对，就能开放给\(childName)"
        case .failed: "这次没传完，点这里回到 App 接着传"
        }
    }

    /// 过期（App 太久没回来更新）时的说明。
    static let staleHint = "有一阵没更新了，打开 App 看看结果"

    /// 灵动岛紧凑态右侧的短文案。
    func shortText(progress: Double? = nil, step: Int? = nil, steps: Int? = nil) -> String {
        switch self {
        case .compressing: "\(Int(((progress ?? 0) * 100).rounded()))%"
        case .uploading: (step.flatMap { s in steps.map { "\(s)/\($0)" } }) ?? "上传"
        case .parsing: "解析"
        case .ready: "可审核"
        case .failed: "未完成"
        }
    }

    /// 进度条整体值：压缩占 0–30%，上传 30–80%，解析停在 90%，结束 100%。
    func overallProgress(progress: Double? = nil, step: Int? = nil, steps: Int? = nil) -> Double {
        switch self {
        case .compressing: return 0.3 * min(max(progress ?? 0, 0), 1)
        case .uploading:
            guard let step, let steps, steps > 0 else { return 0.3 }
            return 0.3 + 0.5 * Double(max(step - 1, 0)) / Double(steps)
        case .parsing: return 0.9
        case .ready, .failed: return 1
        }
    }
}

// MARK: - 启动/回前台时如何处理留在锁屏上的课程活动（纯逻辑，便于测试）
nonisolated enum CourseUploadReconciler {
    enum Action: Equatable { case keep, dismiss, markFailed, askServer(String) }

    /// phase：活动当前显示的阶段；trackedID：已创建的课程 id；本进程没有在上传（调用方保证）。
    static func action(phase: CourseUploadActivityPhase?, trackedID: String?, timedOut: Bool, hasClient: Bool) -> Action {
        if timedOut { return .dismiss }
        switch phase {
        case .ready?, .failed?:
            return .keep   // 已是结果态，按自己的停留时间收起
        case .compressing?, .uploading?, nil:
            // 进程已经不在传：要么被杀/挂起，要么上次没收尾。有课程就问服务端（也许其实传完了）。
            if let trackedID, hasClient { return .askServer(trackedID) }
            return .markFailed
        case .parsing?:
            guard let trackedID else { return .dismiss }
            return hasClient ? .askServer(trackedID) : .keep
        }
    }
}

#if !targetEnvironment(macCatalyst)
// MARK: - Live Activity 属性（主 App 与 Widget extension 共享）
/// 几个「正在发生」的场景共用一套 attributes，用 kind 区分渲染：
/// - 录音中：复用 AudioRecorder.elapsed，展示时长（录音一进后台就自动收尾，锁屏上看不到它，所以不放停止键）。
/// - 时间胶囊倒计时：复用 TimeCapsule.unlockAt，锁屏/灵动岛系统自走倒计时。
/// - 课程上传：压缩/上传/解析进度，到草稿可审核或失败为止。
nonisolated struct BubuActivityAttributes: ActivityAttributes {
    nonisolated public struct ContentState: Codable, Hashable {
        /// 录音已进行的起点（用 Text(timerInterval:) 让系统自走，避免频繁 update 耗电）。
        var startedAt: Date
        /// 录音场景的当前时长文案（end 时定格用）；倒计时场景可忽略。
        var elapsedText: String
        /// 课程上传阶段；其他场景为 nil。旧版本的状态解码时缺省为 nil。
        var uploadPhase: CourseUploadActivityPhase? = nil
        /// 当前阶段的进度 0...1（压缩用）。
        var progress: Double? = nil
        /// 上传第几个文件 / 共几个。
        var step: Int? = nil
        var steps: Int? = nil
    }

    nonisolated enum Kind: String, Codable, Hashable {
        case voiceRecording   // 录音中
        case capsuleCountdown // 时间胶囊倒计时
        case sleepTimer       // 哄睡计时（R4 E-3）
        case courseUpload     // 每日学习课程上传 / 解析
    }

    var kind: Kind
    /// 标题：录音→"正在记录布布的声音"；胶囊→胶囊标题；课程→课程名。
    var title: String
    /// 倒计时场景的解锁时间；录音场景为 nil。
    var unlockAt: Date?
    /// 布布名字（展示用）。
    var childName: String
    /// 点锁屏/灵动岛时打开的深链（课程上传带上课日期）；缺省按 kind 选。旧版本的 attributes 解码时为 nil。
    var deepLink: URL? = nil

    /// 点实时活动打开哪里：课程 → 那天的每日学习；哄睡 → 成长；录音/胶囊 → 首页。
    var widgetURL: URL {
        if let deepLink { return deepLink }
        switch kind {
        case .courseUpload: return URL(string: "bubu://learning")!
        case .sleepTimer: return URL(string: "bubu://growth")!
        case .voiceRecording, .capsuleCountdown: return URL(string: "bubu://identity")!
        }
    }

    static func learningURL(schoolDate: String) -> URL {
        var components = URLComponents()
        components.scheme = "bubu"
        components.host = "learning"
        components.queryItems = [URLQueryItem(name: "date", value: schoolDate)]
        return components.url ?? URL(string: "bubu://learning")!
    }
}

// MARK: - 锁屏「醒啦」按钮
/// 抱着睡着的孩子时，在锁屏/灵动岛点一下就结束哄睡计时并记下睡了多久，不用解锁找页面。
/// 主 App 与 Widget extension 都编进了这个 intent，系统会在主 App 进程里执行 perform。
/// 写库语义与健康页 / 手表的 endSleep 一致：不到一分钟算误触，只清状态不落卡。
struct EndSleepActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "布布醒啦"
    static let description = IntentDescription("结束哄睡计时，记下这次睡了多久。")
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let end = Date.now
        let started = SharedDefaults.sleepStartedAt
        SharedDefaults.sleepStartedAt = nil
        var summary = ""
        if let started, end.timeIntervalSince(started) >= 60,
           let context = SharedModelContainer.sharedIfAvailable?.mainContext {
            let text = SleepActivityText.duration(from: started, to: end)
            let record = HealthRecord(kind: .sleep, title: "睡觉", recordedAt: end)
            record.startAt = started
            record.endAt = end
            record.amountValue = end.timeIntervalSince(started) / 3600
            record.amountUnit = "小时"
            record.amountText = text
            record.syncState = .local
            context.insert(record)
            context.insert(FeedEvent(kind: .healthRecorded, actorRole: SharedDefaults.currentRole.rawValue,
                                     summary: "记录了睡眠：\(text)", targetLocalId: record.id.uuidString, happenedAt: end))
            try context.save()
            SharedDefaults.refreshWidgetsAfterWrite(context: context)
            summary = text
        }
        let final = BubuActivityAttributes.ContentState(startedAt: end, elapsedText: summary)
        for activity in Activity<BubuActivityAttributes>.activities where activity.attributes.kind == .sleepTimer {
            await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate)
        }
        return .result()
    }
}

/// 与 HealthRecordDraft.durationText 同一套说法（Widget extension 里没有健康页代码，这里单独放一份）。
nonisolated enum SleepActivityText {
    static func duration(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        let hours = minutes / 60, rest = minutes % 60
        if hours > 0 && rest > 0 { return "\(hours)小时\(rest)分钟" }
        if hours > 0 { return "\(hours)小时" }
        return "\(rest)分钟"
    }
}
#endif
