import SwiftData
import Foundation

// MARK: - VoiceNote（语音记录：附在 Entry 上的录音）
/// 不止文字——一段话、一声笑、姥姥的叮咛都能录下来。
/// 与 VoiceMemo（成长之声，按岁横切归档）区分：VoiceNote 属于某条具体记录。
@Model
final class VoiceNote {
    @Attribute(.unique) var id: UUID
    var remoteId: String?
    var localFileName: String?        // 沙盒相对路径（.m4a）
    var remoteURL: String?
    var durationSeconds: Double = 0
    var transcript: String?           // 预留：将来 Whisper 转写
    var authorRole: String            // 谁录的
    var waveformSamples: [Float] = []  // 波形可视化采样（0...1）
    var syncStateRaw: String = SyncState.local.rawValue
    var createdAt: Date

    var entry: Entry?

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }

    init(localFileName: String?, durationSeconds: Double, authorRole: String,
         waveformSamples: [Float] = []) {
        self.id = UUID()
        self.localFileName = localFileName
        self.durationSeconds = durationSeconds
        self.authorRole = authorRole
        self.waveformSamples = waveformSamples
        self.createdAt = .now
    }
}
