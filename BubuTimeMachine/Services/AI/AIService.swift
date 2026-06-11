import Foundation

// MARK: - AI 服务协议（BubuAIService 实现，全部走自托管 FastAPI）
/// 隐私至上：AI 能力全部自托管，UI 永不依赖具体后端。
protocol AIService: Sendable {
    func ping() async throws -> Bool
    func classify(entryId: UUID) async throws -> AIClassification   // 时间/地点/事件
    func detectFirstTime(media: [Media]) async throws -> FirstTimeSuggestion?
    func transcribe(audioURL: URL) async throws -> String
    func rewriteFirstPerson(note: String, childName: String) async throws -> String
    func generateGrowthMovie(year: Int) async throws -> GrowthMovieJob
    func movieNarration(year: Int, childName: String, highlights: [String]) async throws -> String
}
