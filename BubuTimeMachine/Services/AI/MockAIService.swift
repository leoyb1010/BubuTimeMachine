import Foundation

// MARK: - Mock AI 服务
/// 接口先行：返回温暖、可信的假结果，让 AI 工坊完整可玩。
/// 正式部署时，把本类替换为调用自托管 FastAPI 的 BubuAIService，协议不变、UI 不改。
final class MockAIService: AIService {

    func classify(entryId: UUID) async throws -> AIClassification {
        try? await Task.sleep(for: .milliseconds(400))
        return AIClassification(
            suggestedTitle: "在家的午后",
            eventCluster: "日常",
            placeName: "家",
            visualTags: ["宝宝", "微笑", "室内"]
        )
    }

    func detectFirstTime(media: [Media]) async throws -> FirstTimeSuggestion? {
        try? await Task.sleep(for: .milliseconds(400))
        // 依据标签给出"第一次"猜测，用于联调弹窗
        let tags = media.flatMap { $0.aiTags }
        if tags.contains("水果") { return FirstTimeSuggestion(what: "第一次吃水果", confidence: 0.62) }
        if tags.contains("蛋糕") { return FirstTimeSuggestion(what: "第一次吃蛋糕", confidence: 0.7) }
        return nil
    }

    func transcribe(audioURL: URL) async throws -> String {
        try? await Task.sleep(for: .milliseconds(600))
        return "（示例转写）布布在咿咿呀呀地说话，最后清楚地喊了一声「妈妈」。"
    }

    func rewriteFirstPerson(note: String, childName: String) async throws -> String {
        try? await Task.sleep(for: .seconds(1))
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.isEmpty ? "今天也是被爱包围的一天。" : trimmed
        return """
        今天我是\(childName)。
        \(body)
        我还不太会用语言说出来，但我什么都记得——\
        阳光的味道、被抱起来时的安心，还有你们看我时的眼神。
        等我长大，谢谢你们把这些都替我收好了。
        """
    }

    func generateGrowthMovie(year: Int) async throws -> GrowthMovieJob {
        try? await Task.sleep(for: .milliseconds(500))
        return GrowthMovieJob(jobId: "mock-job-\(year)", year: year, status: "generating")
    }
}
