import SwiftData
import Foundation

// MARK: - TimeCapsule（时间胶囊：写给未来的她，到期前加密锁定）
@Model
final class TimeCapsule {
    @Attribute(.unique) var id: UUID
    var remoteId: String?
    var title: String
    var fromRole: String              // 谁写的
    var unlockAt: Date                // 解锁时间，如 18 岁生日
    var isLocked: Bool = true
    var encryptedBlobFileName: String? // 本地加密文件（信件文本+音视频）
    var coverEmoji: String?
    var syncStateRaw: String = SyncState.local.rawValue
    var createdAt: Date

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }

    init(title: String, fromRole: String, unlockAt: Date) {
        self.id = UUID()
        self.title = title
        self.fromRole = fromRole
        self.unlockAt = unlockAt
        self.createdAt = .now
    }
}
