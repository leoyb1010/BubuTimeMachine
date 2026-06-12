import Foundation

// MARK: - Mock AI 服务
/// 接口先行：返回温暖、可信的假结果，让 AI 工坊完整可玩。
/// 正式部署时，把本类替换为调用自托管 FastAPI 的 BubuAIService，协议不变、UI 不改。
final class MockAIService: AIService {

    func ping() async throws -> Bool { true }

    func classifyContent(note: String?, tags: [String], locationName: String?) async throws -> AIClassification {
        try? await Task.sleep(for: .milliseconds(400))
        return AIClassification(
            suggestedTitle: "在家的午后",
            eventCluster: "日常",
            placeName: locationName ?? "家",
            visualTags: tags.isEmpty ? ["宝宝", "微笑", "室内"] : tags
        )
    }

    /// 关键词假解析：离线/预览时让自然语言入口完整可玩。
    func parseNaturalCapture(_ request: NaturalCaptureRequest) async throws -> NaturalCaptureResult {
        try? await Task.sleep(for: .milliseconds(500))
        let text = request.text
        var items: [NaturalCaptureItem] = []
        if text.contains("疫苗") {
            items.append(NaturalCaptureItem(
                domain: .vaccine, action: .create, title: "疫苗接种", note: nil, date: .now,
                fields: ["vaccine_name": .string("示例疫苗")], tags: ["疫苗"],
                confidence: 0.9, needsConfirmation: true, sourceText: text))
        }
        if text.contains("喝水") {
            items.append(NaturalCaptureItem(
                domain: .water, action: .create, title: "喝水", note: nil, date: .now,
                fields: ["amount_ml": .number(120)], tags: [],
                confidence: 0.9, needsConfirmation: false, sourceText: text))
        }
        if text.contains("身高") || text.contains("体重") {
            items.append(NaturalCaptureItem(
                domain: .growth, action: .create, title: "身高体重", note: nil, date: .now,
                fields: ["height_cm": .number(82), "weight_kg": .number(10.6)], tags: [],
                confidence: 0.88, needsConfirmation: false, sourceText: text))
        }
        if items.isEmpty {
            items.append(NaturalCaptureItem(
                domain: .timeline, action: .create, title: String(text.prefix(12)), note: text,
                date: .now, fields: [:], tags: [],
                confidence: 0.7, needsConfirmation: false, sourceText: text))
        }
        return NaturalCaptureResult(confidence: 0.85, items: items, warnings: [])
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
        let body = trimmed.isEmpty ? "小手摸到软软的光，耳边有熟悉的声音，我慢慢眨眨眼。" : trimmed
        return """
        我是\(childName)，这一刻有好多小感觉：\(body)
        我的小手动了动，眼睛也忙着看。身边的声音软软的，我好像把这一点点暖暖的东西，都悄悄装进心里了。
        """
    }

    func generateGrowthMovie(year: Int) async throws -> GrowthMovieJob {
        try? await Task.sleep(for: .milliseconds(500))
        return GrowthMovieJob(jobId: "mock-job-\(year)", year: year, status: "generating")
    }

    func movieNarration(year: Int, childName: String, highlights: [String]) async throws -> String {
        "这是\(childName)的一小段成长电影。" + highlights.prefix(3).joined(separator: "，")
    }
}
