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
    /// 这封信封存时用的加密版本（3 = BTC3 真 E2E）。可选：老数据为 nil，
    /// 首次成功解开时按实际 blob 头回填。
    ///
    /// 为什么必须有：`unseal` 完全按 blob 头部魔数分派版本，而 v2 的密钥只由
    /// `unlockAt` 与 `salt`(=胶囊 id) 派生——两个都是随记录同步到服务器的**明文字段**。
    /// 拿到数据库或备份的人可以自己派生 v2 密钥、封一段自己写的正文、加 BTC2 前缀替换上去，
    /// 换机后同步拉回本地，解封认魔数就成功了：密钥公开时 AES-GCM 的完整性校验形同虚设。
    /// 布布 18 岁打开的会是别人写的信，而界面上没有任何异常。
    /// 记住版本之后，v3 的信就不再接受任何降级的 blob。
    var cryptoVersion: Int?
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
