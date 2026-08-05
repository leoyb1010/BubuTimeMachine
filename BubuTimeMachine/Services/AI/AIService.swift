import Foundation

// MARK: - AI 服务协议（BubuAIService 实现，全部走自托管 FastAPI）
/// 隐私至上：AI 能力全部自托管，UI 永不依赖具体后端。
protocol AIService: Sendable {
    func ping() async throws -> Bool
    /// 富归类：传文字 + 标签 + 地点（时间/地点/事件）。
    func classifyContent(note: String?, tags: [String], locationName: String?) async throws -> AIClassification
    func detectFirstTime(media: [Media]) async throws -> FirstTimeSuggestion?
    func transcribe(audioURL: URL) async throws -> String
    func rewriteFirstPerson(note: String, childName: String) async throws -> String
    func generateGrowthMovie(year: Int) async throws -> GrowthMovieJob
    func movieNarration(year: Int, childName: String, highlights: [String]) async throws -> String
    /// 一句话自然语言 → 多条结构化记录（疫苗/成长/餐食/喝水/睡眠/不舒服/时光…）。
    func parseNaturalCapture(_ request: NaturalCaptureRequest) async throws -> NaturalCaptureResult
    /// 布布问答：App 端检索出相关记录传入，服务端组织答案并回引用到的记录 id。
    func ask(question: String, childName: String, records: [QAContextRecord]) async throws -> QAAnswer
    /// 在家庭自托管索引里同时搜索照片画面与已有文字；不上传照片，返回可追溯到本地记录的来源。
    func semanticSearch(query: String, limit: Int) async throws -> SemanticSearchResponse
    /// 服务端派生周报：每段都带来源，收进档案只改变派生产物状态。
    func latestWeeklyReport() async throws -> WeeklyReport?
    func weeklyReportHistory() async throws -> [WeeklyReport]
    func generateWeeklyReport() async throws -> WeeklyReport
    func archiveWeeklyReport(id: String) async throws -> WeeklyReport
    /// 只推送新周报 id 的 SSE，不承载正文。
    func weeklyReportEvents() -> AsyncStream<String>
    /// 声音年轮：先生成可核对的原声清单，家庭确认后再渲染；失败可按同一 id 重试。
    func latestSoundRing() async throws -> SoundRing?
    func soundRingHistory() async throws -> [SoundRing]
    func createSoundRingDraft() async throws -> SoundRing
    func removeSoundRingClip(id: String, sourceId: String) async throws -> SoundRing
    func renderSoundRing(id: String) async throws -> SoundRing
    func soundRingStatus(id: String) async throws -> SoundRing
    func archiveSoundRing(id: String) async throws -> SoundRing
    func downloadSoundRing(id: String) async throws -> URL
    /// 成长电影服务端合成：照片本就同步在家庭自己的服务器，App 只传【本机照片 URL】。
    func startMovieRender(childName: String, year: Int, template: String,
                          photos: [MovieRenderPhoto], narration: String) async throws -> MovieRenderStatus
    func movieRenderStatus(jobId: String) async throws -> MovieRenderStatus
    /// 下载合成好的成片到本地临时文件，供播放/分享。
    func downloadRenderedMovie(jobId: String) async throws -> URL
}

// MARK: - 派生作品来源
/// 周报、声音年轮和后续成长电影共用的可回查事实引用；作品层不复制或改写事实。
struct ArtifactSourceReference: Codable, Sendable, Equatable, Identifiable {
    let sourceId: String
    let collection: String
    let recordId: String
    let localId: String
    let happenedAt: String
    let title: String
    let excerpt: String
    let kind: String

    var id: String { sourceId }

    enum CodingKeys: String, CodingKey {
        case collection, title, excerpt, kind
        case sourceId = "source_id"
        case recordId = "record_id"
        case localId = "local_id"
        case happenedAt = "happened_at"
    }
}

/// 保留旧名称，现有周报视图无需一次性重命名；真实类型已经是公共作品来源。
typealias WeeklyReportSource = ArtifactSourceReference

// MARK: - 布布周报

struct WeeklyReportSection: Codable, Sendable, Equatable, Identifiable {
    let kind: String
    let title: String
    let text: String
    let sourceIds: [String]

    var id: String { kind }
}

struct WeeklyReport: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let artifactKey: String
    let status: String
    let title: String
    let summary: String
    let weekStart: String
    let weekEnd: String
    let generatedAt: String
    let modelVersion: String
    let contentHash: String
    let sections: [WeeklyReportSection]
    let sourceRefs: [ArtifactSourceReference]

    enum CodingKeys: String, CodingKey {
        case id, status, title, summary, sections
        case artifactKey = "artifact_key"
        case weekStart = "week_start"
        case weekEnd = "week_end"
        case generatedAt = "generated_at"
        case modelVersion = "model_version"
        case contentHash = "content_hash"
        case sourceRefs = "source_refs"
    }
}

// MARK: - 声音年轮
struct SoundRingClip: Codable, Sendable, Equatable, Identifiable {
    let sourceId: String
    let photoSourceId: String
    let ageYears: Int
    let kind: String
    let title: String
    let recordedAt: String
    let transcript: String
    let durationSeconds: Double
    let startSeconds: Double
    let endSeconds: Double

    var id: String { sourceId }

    enum CodingKeys: String, CodingKey {
        case title, kind, transcript
        case sourceId = "source_id"
        case photoSourceId = "photo_source_id"
        case ageYears = "age_years"
        case recordedAt = "recorded_at"
        case durationSeconds = "duration_seconds"
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
    }
}

struct SoundRing: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let artifactKey: String
    let status: String
    let title: String
    let summary: String
    let generatedAt: String
    let modelVersion: String
    let originalDurationSeconds: Double
    let renderedDurationSeconds: Double
    let attempts: Int
    let error: String
    let narrator: String
    let voiceCloning: Bool
    let hasAudio: Bool
    let clips: [SoundRingClip]
    let sourceRefs: [ArtifactSourceReference]
    let contentHash: String

    enum CodingKeys: String, CodingKey {
        case id, status, title, summary, attempts, error, narrator, clips
        case artifactKey = "artifact_key"
        case generatedAt = "generated_at"
        case modelVersion = "model_version"
        case originalDurationSeconds = "original_duration_seconds"
        case renderedDurationSeconds = "rendered_duration_seconds"
        case voiceCloning = "voice_cloning"
        case hasAudio = "has_audio"
        case sourceRefs = "source_refs"
        case contentHash = "content_hash"
    }
}

// MARK: - 语义搜图
struct SemanticSearchHit: Codable, Sendable, Equatable {
    let assetId: String
    let entryLocalId: String
    let mediaRecordId: String
    let capturedAt: String
    let score: Double
    let reason: String

    enum CodingKeys: String, CodingKey {
        case assetId = "asset_id"
        case entryLocalId = "entry_local_id"
        case mediaRecordId = "media_record_id"
        case capturedAt = "captured_at"
        case score, reason
    }
}

struct SemanticSearchResponse: Codable, Sendable, Equatable {
    let query: String
    let modelVersion: String
    let hits: [SemanticSearchHit]

    enum CodingKeys: String, CodingKey {
        case query, hits
        case modelVersion = "model_version"
    }
}

/// 服务端可能一条记录含多张照片；UI 每条记录只保留置信度最高且确实存在于本机的命中。
enum TimelineSemanticSearchResolver {
    static func bestHits(_ hits: [SemanticSearchHit], availableEntryIDs: Set<UUID>) -> [UUID: SemanticSearchHit] {
        var result: [UUID: SemanticSearchHit] = [:]
        for hit in hits {
            guard let id = UUID(uuidString: hit.entryLocalId), availableEntryIDs.contains(id) else { continue }
            if let old = result[id], old.score >= hit.score { continue }
            result[id] = hit
        }
        return result
    }
}

// MARK: - 成长电影服务端合成
struct MovieRenderPhoto: Sendable {
    let url: String       // 家庭自托管 PocketBase 上的照片 URL
    let caption: String
}

struct MovieRenderStatus: Sendable {
    let jobId: String
    let status: String    // queued / rendering / ready / failed
    let progress: Double  // 0...1
    let ready: Bool
    let error: String
}

// MARK: - 问答上下文（检索在 App 端做）
struct QAContextRecord: Sendable {
    let id: String
    let dateText: String
    let ageText: String
    let text: String
}

struct QAAnswer: Sendable {
    let answer: String
    let usedIDs: [String]
}
