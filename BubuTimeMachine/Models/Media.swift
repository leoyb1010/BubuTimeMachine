import SwiftData
import Foundation

// MARK: - Media（照片/视频/音频统一抽象，支持分片上传进度）
@Model
final class Media {
    @Attribute(.unique) var id: UUID
    var remoteId: String?
    var typeRaw: String               // photo / video / audio
    var localFileName: String?        // 沙盒相对路径
    var remoteURL: String?            // PocketBase file url
    var thumbnailFileName: String?
    /// 服务端缩略图 URL（media.thumbnail file 字段）。V2 新增：
    /// 视频的预览图靠它——接收端不用下完整个视频就能出预览。
    var remoteThumbURL: String?
    /// 文件内容 SHA256（十六进制）。V2 新增：导入时计算，拦截同一文件被重复收录。
    var contentHash: String?
    /// PhotoKit 资源版本：display / original / live-paired。可选字段，老数据默认展示。
    var resourceRoleRaw: String?
    /// 同一系统相册资产的稳定分组 ID（当前图、原图、Live Photo 动态资源共用）。
    var assetGroupID: String?
    var durationSeconds: Double?      // 视频/音频时长
    var width: Int?
    var height: Int?
    var uploadProgress: Double = 0    // 0...1，UI 进度条
    var syncStateRaw: String = SyncState.local.rawValue
    var aiTags: [String] = []         // AI 视觉打标
    var createdAt: Date

    var entry: Entry?

    var type: MediaType { MediaType(rawValue: typeRaw) ?? .photo }
    /// 老记录没有角色，仍按普通素材展示；系统后台额外保存的原图/Live 动态资源
    /// 只用于传家宝保真与导出，不在时光流里重复出现。
    var isDisplayResource: Bool {
        guard let role = resourceRoleRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !role.isEmpty else { return true }
        return role == "display"
    }
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }

    init(type: MediaType, localFileName: String?) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.localFileName = localFileName
        self.createdAt = .now
    }
}
