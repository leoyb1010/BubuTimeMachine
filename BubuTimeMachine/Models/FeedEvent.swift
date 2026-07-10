import Foundation
import SwiftData

// MARK: - 家庭动态
@Model
final class FeedEvent {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var actorRole: String
    var targetLocalId: String?
    var summary: String
    var happenedAt: Date
    var syncStateRaw: String = SyncState.local.rawValue
    var createdAt: Date

    var kind: FeedEventKind {
        get { FeedEventKind(rawValue: kindRaw) ?? .entryCreated }
        set { kindRaw = newValue.rawValue }
    }

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }

    init(kind: FeedEventKind, actorRole: String, summary: String, targetLocalId: String? = nil, happenedAt: Date = .now) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.actorRole = actorRole
        self.summary = summary
        self.targetLocalId = targetLocalId
        self.happenedAt = happenedAt
        self.createdAt = .now
    }
}

enum FeedEventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case entryCreated
    case entryArchived
    case commentAdded
    case voiceAdded
    case milestoneLit
    case healthRecorded
    case firstTimeConfirmed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .entryCreated: return "瞬间"
        case .entryArchived: return "删除"
        case .commentAdded: return "评论"
        case .voiceAdded: return "语音"
        case .milestoneLit: return "里程碑"
        case .healthRecorded: return "健康"
        case .firstTimeConfirmed: return "第一次"
        }
    }

    var icon: String {
        switch self {
        case .entryCreated: return "heart.circle.fill"
        case .entryArchived: return "trash.circle.fill"
        case .commentAdded: return "text.bubble.fill"
        case .voiceAdded: return "waveform.circle.fill"
        case .milestoneLit: return "star.circle.fill"
        case .healthRecorded: return "heart.text.square.fill"
        case .firstTimeConfirmed: return "sparkles"
        }
    }

    var emoji: String {
        switch self {
        case .entryCreated: return "✨"
        case .entryArchived: return "🗑️"
        case .commentAdded: return "💬"
        case .voiceAdded: return "🎤"
        case .milestoneLit: return "🌟"
        case .healthRecorded: return "🍼"
        case .firstTimeConfirmed: return "🎉"
        }
    }
}
