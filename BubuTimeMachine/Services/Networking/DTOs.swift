import Foundation

// MARK: - 网络传输对象（DTO）
// UI 永不直接依赖这些类型；它们只在 Service 层与服务器之间流转。

struct AuthToken: Codable, Sendable {
    let token: String
    let role: String
    let expiresAt: Date?
}

/// Entry 的服务器表示。与 SwiftData `Entry` 解耦，便于后端字段独立演进。
struct EntryDTO: Codable, Sendable {
    var id: String?                 // remoteId
    var localId: String             // 客户端 UUID，幂等去重用
    var title: String?
    var note: String?
    var firstPersonNote: String?
    var happenedAt: Date
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    var authorRole: String
    var mood: String?
    var isArchived: Bool
    var editedAt: Date?
    var createdAt: Date
}

/// 一次媒体上传请求。
struct MediaUploadRequest: Sendable {
    let mediaId: UUID
    let entryLocalId: UUID
    let fileURL: URL
    let type: MediaType
    let fileName: String
}

/// 上传过程事件流。
enum UploadEvent: Sendable {
    case progress(Double)                       // 0...1，驱动 Media.uploadProgress
    case completed(remoteId: String, url: String)
}

/// Realtime 远端变更事件（PocketBase subscribe）。
enum RealtimeEvent: Sendable {
    case entryChanged(EntryDTO)
    case entryDeleted(remoteId: String)
    case connected
    case disconnected
}

// MARK: - AI 结果类型

/// AI 对一条 Entry 的归类结果：时间/地点/事件聚类。
struct AIClassification: Sendable {
    let suggestedTitle: String?
    let eventCluster: String?       // 用于时光轴按"事件"重排
    let placeName: String?
    let visualTags: [String]
}

/// "这是第一次吗"识别建议。
struct FirstTimeSuggestion: Sendable {
    let what: String                // "第一次吃西瓜"
    let confidence: Double          // 0...1
}

/// 年度成长电影生成任务句柄。
struct GrowthMovieJob: Sendable {
    let jobId: String
    let year: Int
    let status: String              // pending / generating / ready / failed
}
