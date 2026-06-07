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
    var durationSeconds: Double?      // 视频/音频时长
    var width: Int?
    var height: Int?
    var uploadProgress: Double = 0    // 0...1，UI 进度条
    var syncStateRaw: String = SyncState.local.rawValue
    var aiTags: [String] = []         // AI 视觉打标
    var createdAt: Date

    var entry: Entry?

    var type: MediaType { MediaType(rawValue: typeRaw) ?? .photo }
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
