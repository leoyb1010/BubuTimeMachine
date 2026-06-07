import SwiftData
import Foundation

// MARK: - VoiceMemo（成长之声：按年龄归档她的声音 + 家人对她说的话）
@Model
final class VoiceMemo {
    @Attribute(.unique) var id: UUID
    var remoteId: String?
    var kindRaw: String               // childVoice（她的声音）/ familyVoice（对她说）
    var localFileName: String?
    var remoteURL: String?
    var transcript: String?           // Whisper 转写
    var ageYears: Int?                 // 录制时她的年龄，自动归档
    var recordedAt: Date
    var durationSeconds: Double?
    var syncStateRaw: String = SyncState.local.rawValue
    var createdAt: Date

    enum Kind: String, Codable, Sendable { case childVoice, familyVoice }
    var kind: Kind { Kind(rawValue: kindRaw) ?? .childVoice }
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }

    init(kind: Kind, recordedAt: Date = .now) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.recordedAt = recordedAt
        self.createdAt = .now
    }
}
