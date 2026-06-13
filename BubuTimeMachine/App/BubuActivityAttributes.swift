import Foundation
import ActivityKit

// MARK: - Live Activity 属性（主 App 与 Widget extension 共享）
/// 两个「正在发生」的场景共用一套 attributes，用 kind 区分渲染：
/// - 录音中：复用 AudioRecorder.elapsed，展示时长 + 可停止。
/// - 时间胶囊倒计时：复用 TimeCapsule.unlockAt，锁屏/灵动岛系统自走倒计时。
struct BubuActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// 录音已进行的起点（用 Text(timerInterval:) 让系统自走，避免频繁 update 耗电）。
        var startedAt: Date
        /// 录音场景的当前时长文案（end 时定格用）；倒计时场景可忽略。
        var elapsedText: String
    }

    enum Kind: String, Codable, Hashable {
        case voiceRecording   // 录音中
        case capsuleCountdown // 时间胶囊倒计时
    }

    var kind: Kind
    /// 标题：录音→"正在记录布布的声音"；胶囊→胶囊标题。
    var title: String
    /// 倒计时场景的解锁时间；录音场景为 nil。
    var unlockAt: Date?
    /// 布布名字（展示用）。
    var childName: String
}
