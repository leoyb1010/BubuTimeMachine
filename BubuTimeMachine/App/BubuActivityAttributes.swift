import Foundation
#if !targetEnvironment(macCatalyst)
import ActivityKit
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

#if !targetEnvironment(macCatalyst)
// MARK: - Live Activity 属性（主 App 与 Widget extension 共享）
/// 几个「正在发生」的场景共用一套 attributes，用 kind 区分渲染：
/// - 录音中：复用 AudioRecorder.elapsed，展示时长 + 可停止。
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
}
#endif
