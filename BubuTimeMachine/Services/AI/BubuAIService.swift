import Foundation

// MARK: - BubuAIService（AIService 真实实现）
/// 调用自托管 FastAPI（背后接 DeepSeek）。隐私：只发文字，不上传照片。
/// 任意一步失败都抛错，UI 层各视图自行降级（保留 Mock 体验或提示稍后再试）。
final class BubuAIService: AIService, @unchecked Sendable {

    private let baseURL: URL
    private let apiKey: String
    private let session = URLSession(configuration: .default)

    init(baseURL: URL, apiKey: String = "") {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    func ping() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        var req = URLRequest(url: url)
        applyAuth(&req)
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp, data)
        // 服务端开启鉴权时，health 会回 auth 字段；key 不对则视为未连通。
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let auth = obj["auth"] as? Bool, !auth, !apiKey.isEmpty {
            return false
        }
        return true
    }

    private func applyAuth(_ req: inout URLRequest) {
        if !apiKey.isEmpty {
            req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
    }

    func rewriteFirstPerson(note: String, childName: String) async throws -> String {
        let body: [String: Any] = ["note": note, "child_name": childName]
        let obj = try await post("rewrite-first-person", body)
        return (obj["first_person"] as? String) ?? ""
    }

    /// 富归类：传文字 + 标签 + 地点。
    func classifyContent(note: String?, tags: [String], locationName: String?) async throws -> AIClassification {
        let body: [String: Any] = [
            "note": note ?? "", "tags": tags, "location_name": locationName ?? "",
        ]
        let obj = try await post("classify", body)
        return AIClassification(
            suggestedTitle: obj["suggested_title"] as? String,
            eventCluster: obj["event_cluster"] as? String,
            placeName: obj["place_name"] as? String ?? locationName,
            visualTags: obj["visual_tags"] as? [String] ?? tags
        )
    }

    func detectFirstTime(media: [Media]) async throws -> FirstTimeSuggestion? {
        let tags = Array(Set(media.flatMap { $0.aiTags }))
        guard !tags.isEmpty else { return nil }
        let obj = try await post("detect-first-time", ["tags": tags])
        guard let isFirst = obj["is_first"] as? Bool, isFirst,
              let what = obj["what"] as? String else { return nil }
        return FirstTimeSuggestion(what: what, confidence: obj["confidence"] as? Double ?? 0.5)
    }

    func transcribe(audioURL: URL) async throws -> String {
        let url = baseURL.appendingPathComponent("transcribe")
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)
        let fileData = try Data(contentsOf: audioURL)
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        let (data, resp) = try await session.upload(for: req, from: body)
        try Self.check(resp, data)
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return obj["transcript"] as? String ?? ""
    }

    func generateGrowthMovie(year: Int) async throws -> GrowthMovieJob {
        // 旁白生成（成片 ffmpeg 拼接在服务端，前端流程占位）。
        let obj = try await post("movie-narration", ["year": year, "child_name": "布布"])
        let narration = obj["narration"] as? String ?? ""
        return GrowthMovieJob(jobId: "ai-\(year)", year: year,
                              status: narration.isEmpty ? "failed" : "ready")
    }

    /// 旁白文本（供成长电影视图直接取用）。
    func movieNarration(year: Int, childName: String, highlights: [String]) async throws -> String {
        let obj = try await post("movie-narration", [
            "year": year, "child_name": childName, "highlights": highlights,
        ])
        return obj["narration"] as? String ?? ""
    }

    /// 一句话自然语言 → 结构化记录（服务端 /parse-natural-capture）。
    func parseNaturalCapture(_ request: NaturalCaptureRequest) async throws -> NaturalCaptureResult {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bodyData = try encoder.encode(request)

        let url = baseURL.appendingPathComponent("parse-natural-capture")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)
        req.timeoutInterval = 90
        req.httpBody = bodyData

        let (data, resp) = try await session.data(for: req)
        try Self.check(resp, data)
        return try NaturalCaptureCoding.decoder().decode(NaturalCaptureResult.self, from: data)
    }

    // MARK: - 私有

    private func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)
        req.timeoutInterval = 90
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp, data)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw APIError.server(http.statusCode, String(msg))
        }
    }
}
