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

    func ask(question: String, childName: String, records: [QAContextRecord]) async throws -> QAAnswer {
        let recs: [[String: Any]] = records.map {
            ["id": $0.id, "date": $0.dateText, "age": $0.ageText, "text": $0.text]
        }
        let body: [String: Any] = ["question": question, "child_name": childName, "records": recs]
        let obj = try await post("ask", body)
        return QAAnswer(answer: obj["answer"] as? String ?? "",
                        usedIDs: obj["used_ids"] as? [String] ?? [])
    }

    func startMovieRender(childName: String, year: Int, template: String,
                          photos: [MovieRenderPhoto], narration: String) async throws -> MovieRenderStatus {
        let body: [String: Any] = [
            "child_name": childName, "year": year, "template": template, "narration": narration,
            "photos": photos.map { ["url": $0.url, "caption": $0.caption] },
        ]
        let obj = try await post("movie/render", body)
        return Self.renderStatus(from: obj)
    }

    func movieRenderStatus(jobId: String) async throws -> MovieRenderStatus {
        let obj = try await get("movie/status/\(jobId)")
        return Self.renderStatus(from: obj)
    }

    func downloadRenderedMovie(jobId: String) async throws -> URL {
        let url = baseURL.appendingPathComponent("movie/file/\(jobId)")
        var req = URLRequest(url: url)
        applyAuth(&req)
        req.timeoutInterval = 300
        // 流式落盘：长片整段读进内存会触发内存告警（R4 待核-mp4）
        let (tempURL, resp) = try await session.download(for: req)
        try Self.check(resp, Data())
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("bubu_movie_\(jobId).mp4")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    private static func renderStatus(from obj: [String: Any]) -> MovieRenderStatus {
        MovieRenderStatus(
            jobId: obj["job_id"] as? String ?? "",
            status: obj["status"] as? String ?? "failed",
            progress: obj["progress"] as? Double ?? 0,
            ready: obj["ready"] as? Bool ?? false,
            error: obj["error"] as? String ?? "")
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
        // 长语音服务端转写可能远超默认 60s（P3-32）：与 downloadRenderedMovie 同档放宽。
        req.timeoutInterval = 300
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)
        // 分块把音频写进临时 multipart 请求体文件，再 upload(fromFile:) 流式上传，
        // 避免整段大录音一次性读进内存拼 body 的内存峰值（沿用 PocketBaseClient 的成熟做法）。
        let bodyURL = try Self.multipartBodyFile(boundary: boundary, audioURL: audioURL)
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        let (data, resp) = try await session.upload(for: req, fromFile: bodyURL)
        try Self.check(resp, data)
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return obj["transcript"] as? String ?? ""
    }

    /// 把「单文件 multipart 请求体」分块写到临时文件，返回其 URL（字段名 file、octet-stream 与旧版一致）。
    private static func multipartBodyFile(boundary: String, audioURL: URL) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bubu-transcribe-\(UUID().uuidString).body")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: tempURL)
        defer { try? output.close() }
        func write(_ string: String) throws {
            try output.write(contentsOf: Data(string.utf8))
        }

        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n")
        try write("Content-Type: application/octet-stream\r\n\r\n")

        let input = try FileHandle(forReadingFrom: audioURL)
        defer { try? input.close() }
        while true {
            let chunk = try input.read(upToCount: 1_048_576)
            guard let chunk, !chunk.isEmpty else { break }
            try output.write(contentsOf: chunk)
        }

        try write("\r\n--\(boundary)--\r\n")
        return tempURL
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

    private func get(_ path: String) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        applyAuth(&req)
        req.timeoutInterval = 30
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp, data)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

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
