import Foundation

// MARK: - Mock AI 服务
/// M0/M1 阶段使用：返回温暖、合理的假结果，让 AI 相关 UI 可先行开发。
final class MockAIService: AIService {

    func classify(entryId: UUID) async throws -> AIClassification {
        try? await Task.sleep(for: .milliseconds(300))
        return AIClassification(
            suggestedTitle: "在家的午后",
            eventCluster: "日常",
            placeName: "家",
            visualTags: ["宝宝", "微笑", "室内"]
        )
    }

    func detectFirstTime(media: [Media]) async throws -> FirstTimeSuggestion? {
        try? await Task.sleep(for: .milliseconds(300))
        // Mock 偶发返回一个"第一次"建议，用于联调弹窗
        return nil
    }

    func transcribe(audioURL: URL) async throws -> String {
        try? await Task.sleep(for: .milliseconds(400))
        return "（这里会是布布或家人说的话的文字版）"
    }

    func rewriteFirstPerson(note: String, childName: String) async throws -> String {
        try? await Task.sleep(for: .milliseconds(400))
        return "今天，\(childName)很开心。\(note)"
    }

    func generateGrowthMovie(year: Int) async throws -> GrowthMovieJob {
        try? await Task.sleep(for: .milliseconds(300))
        return GrowthMovieJob(jobId: "mock-job-\(year)", year: year, status: "pending")
    }
}
