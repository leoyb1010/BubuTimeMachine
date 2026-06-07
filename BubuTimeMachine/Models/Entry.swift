import SwiftData
import Foundation

// MARK: - Entry（记录：一切的容器，一次"记录此刻"= 一个 Entry）
/// 核心聚合根。1 个 Entry → N Media / N Comment / 0..1 Milestone / 0..1 FirstTime。
@Model
final class Entry {
    @Attribute(.unique) var id: UUID
    var remoteId: String?
    var title: String?
    var note: String?                 // 父母视角原文
    var firstPersonNote: String?      // AI 改写的布布第一人称版本
    var happenedAt: Date              // 事件真实发生时间（非创建时间）
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    var authorRole: String            // "爸爸"/"妈妈"/"姥姥"
    var moodRaw: String?              // 心情标签（开心/平静/调皮/委屈…）
    var syncStateRaw: String = SyncState.local.rawValue
    var isArchived: Bool = false      // 软删除：永不物理丢失
    var editedAt: Date?               // 最后编辑时间（已上传内容可改可补充）
    var createdAt: Date

    // 关系
    @Relationship(deleteRule: .cascade, inverse: \Media.entry)
    var media: [Media] = []
    @Relationship(deleteRule: .cascade, inverse: \Comment.entry)
    var comments: [Comment] = []      // 家人合奏：多视角补充
    @Relationship(deleteRule: .cascade, inverse: \VoiceNote.entry)
    var voiceNotes: [VoiceNote] = []  // 语音记录（不止文字）
    @Relationship(inverse: \Milestone.entry)
    var milestone: Milestone?
    @Relationship(inverse: \FirstTime.entry)
    var firstTime: FirstTime?

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }

    var mood: Mood? {
        get { moodRaw.flatMap(Mood.init(rawValue:)) }
        set { moodRaw = newValue?.rawValue }
    }

    init(happenedAt: Date = .now, authorRole: String, note: String? = nil) {
        self.id = UUID()
        self.happenedAt = happenedAt
        self.authorRole = authorRole
        self.note = note
        self.createdAt = .now
    }
}
