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
    /// 成长电影服务端合成：照片本就同步在家庭自己的服务器，App 只传【本机照片 URL】。
    func startMovieRender(childName: String, year: Int, template: String,
                          photos: [MovieRenderPhoto], narration: String) async throws -> MovieRenderStatus
    func movieRenderStatus(jobId: String) async throws -> MovieRenderStatus
    /// 下载合成好的成片到本地临时文件，供播放/分享。
    func downloadRenderedMovie(jobId: String) async throws -> URL
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
