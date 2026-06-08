import SwiftData
import Foundation

// MARK: - Comment（家人合奏：三人对同一 Entry 多视角补充）
@Model
final class Comment {
    @Attribute(.unique) var id: UUID
    var remoteId: String?
    var authorRole: String
    var text: String?
    var voiceFileName: String?        // 也可语音补充（姥姥场景）
    var remoteURL: String?            // 语音补充远端 URL
    var voiceDuration: Double = 0
    var voiceWaveform: [Float] = []
    var syncStateRaw: String = SyncState.local.rawValue
    var createdAt: Date
    var entry: Entry?

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }

    init(authorRole: String, text: String? = nil) {
        self.id = UUID()
        self.authorRole = authorRole
        self.text = text
        self.createdAt = .now
    }
}
