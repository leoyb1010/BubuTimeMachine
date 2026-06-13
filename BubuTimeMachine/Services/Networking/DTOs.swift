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
    var familyId: String?
    var authorUserId: String?
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

struct MediaDTO: Codable, Sendable {
    var id: String?
    var localId: String
    var entryLocalId: String
    var mediaType: String
    var remoteURL: String?
    var durationSeconds: Double?
    var width: Int?
    var height: Int?
    var aiTags: [String]
    var createdAt: Date
}

struct MilestoneDTO: Codable, Sendable {
    var id: String?
    var localId: String
    var title: String
    var category: String
    var emoji: String
    var detail: String?
    var happenedAt: Date?
    var ageDescription: String?
    var isCustom: Bool
    var createdAt: Date
}

struct FirstTimeDTO: Codable, Sendable {
    var id: String?
    var localId: String
    var what: String
    var happenedAt: Date
    var detectedByAI: Bool
    var confirmedByParent: Bool
    var entryLocalId: String?
    var createdAt: Date
}

struct FamilyMemberDTO: Codable, Sendable {
    var id: String?
    var localId: String
    var name: String
    var relation: String
    var avatarEmoji: String
    var themeColorHex: String
    var isPrimary: Bool
    var createdAt: Date
}

struct ChildProfileDTO: Codable, Sendable {
    var id: String?
    var localId: String
    var name: String
    var birthday: Date
    var gender: String?
    var bloodType: String?
    var birthPlace: String?
    var avatarRemoteURL: String?   // 由服务端 avatar file 字段派生，身份卡跨设备显示头像
    var createdAt: Date
}

struct HealthRecordDTO: Codable, Sendable {
    var id: String?
    var localId: String
    var kind: String
    var title: String
    var detail: String?
    var recordedAt: Date
    var amountText: String?
    var reaction: String?
    var amountValue: Double?
    var amountUnit: String?
    var startAt: Date?
    var endAt: Date?
    var severity: String?
    var temperatureCelsius: Double?
    var tags: [String]
    var createdAt: Date
}

struct VaccineRecordDTO: Codable, Sendable {
    var id: String?
    var localId: String
    var doseId: String?
    var vaccineName: String
    var doseLabel: String?
    var injectedAt: Date
    var hospital: String?
    var injectionSite: String?
    var reaction: String?
    var note: String?
    var source: String
    var createdAt: Date
}

struct GrowthMeasurementDTO: Codable, Sendable {
    var id: String?
    var localId: String
    var measuredAt: Date
    var heightCm: Double?
    var weightKg: Double?
    var headCircumferenceCm: Double?
    var note: String?
    var source: String
    var createdAt: Date
}

struct CommentDTO: Codable, Sendable {
    var id: String?
    var localId: String
    var entryLocalId: String
    var authorRole: String
    var text: String?
    var remoteURL: String?
    var voiceDuration: Double
    var voiceWaveform: [Float]
    var createdAt: Date
}

struct VoiceNoteDTO: Codable, Sendable {
    var id: String?
    var localId: String
    var entryLocalId: String
    var authorRole: String
    var remoteURL: String?
    var durationSeconds: Double
    var transcript: String?
    var waveform: [Float]
    var createdAt: Date
}

struct VoiceMemoDTO: Codable, Sendable {
    var id: String?
    var localId: String
    var kind: String
    var remoteURL: String?
    var transcript: String?
    var ageYears: Int?
    var recordedAt: Date
    var durationSeconds: Double?
    var createdAt: Date
}

struct TimeCapsuleDTO: Codable, Sendable {
    var id: String?
    var localId: String
    var title: String
    var fromRole: String
    var unlockAt: Date
    var isLocked: Bool
    var encryptedBlobRemoteURL: String?
    var coverEmoji: String?
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
