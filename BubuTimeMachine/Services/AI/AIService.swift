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
