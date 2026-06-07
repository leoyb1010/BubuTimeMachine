import Foundation

// MARK: - PocketBaseClient（APIClient 真实实现）
/// 对接自托管 PocketBase：REST 鉴权 + CRUD + multipart 上传（带进度）+ Realtime(SSE)。
/// 幂等：以 localId 为去重键，createEntry 先查后建/更新。
/// 离线优先：所有失败都抛错，由 SyncEngine 决定保留本地、稍后重试。
final class PocketBaseClient: NSObject, APIClient, @unchecked Sendable {

    private let baseURL: URL
    private let identity: String       // 家庭共享账户邮箱
    private let password: String

    /// token 存内存 + Keychain（这里简化为内存；ServerConfig 可扩展持久化）。
    private let tokenBox = TokenBox()

    init(baseURL: URL, identity: String, password: String) {
        self.baseURL = baseURL
        self.identity = identity
        self.password = password
    }

    // MARK: 鉴权

    func authenticate(role: String) async throws -> AuthToken {
        let url = baseURL.appendingPathComponent("api/collections/users/auth-with-password")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "identity": identity, "password": password,
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["token"] as? String else {
            throw APIError.server(500, "鉴权响应异常")
        }
        await tokenBox.set(token)
        return AuthToken(token: token, role: role, expiresAt: nil)
    }

    private func ensureToken() async throws -> String {
        if let t = await tokenBox.get() { return t }
        _ = try await authenticate(role: "")
        guard let t = await tokenBox.get() else { throw APIError.unauthorized }
        return t
    }

    // MARK: Entry CRUD（幂等）

    func createEntry(_ dto: EntryDTO) async throws -> EntryDTO {
        let token = try await ensureToken()
        let body = Self.entryBody(dto)

        // 先按 localId 查是否已存在
        if let existing = try await findRecord(collection: "entries",
                                               localId: dto.localId, token: token) {
            let updated = try await patch(collection: "entries", id: existing,
                                          json: body, token: token)
            return Self.entryDTO(from: updated, fallback: dto)
        }
        let created = try await post(collection: "entries", json: body, token: token)
        return Self.entryDTO(from: created, fallback: dto)
    }

    func fetchEntries(since: Date?) async throws -> [EntryDTO] {
        let token = try await ensureToken()
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("api/collections/entries/records"),
            resolvingAgainstBaseURL: false)!
        var query = [URLQueryItem(name: "perPage", value: "500"),
                     URLQueryItem(name: "sort", value: "-happenedAt")]
        if let since {
            let iso = ISO8601DateFormatter().string(from: since)
            query.append(URLQueryItem(name: "filter", value: "(updated>'\(iso)')"))
        }
        comps.queryItems = query
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]] else { return [] }
        return items.map { Self.entryDTO(from: $0, fallback: nil) }
    }

    // MARK: 媒体上传（multipart + 进度）

    func uploadMedia(_ file: MediaUploadRequest) -> AsyncThrowingStream<UploadEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let token = try await ensureToken()
                    let remoteId = try await self.multipartUpload(file, token: token) { progress in
                        continuation.yield(.progress(progress))
                    }
                    let urlStr = self.baseURL
                        .appendingPathComponent("api/files/media/\(remoteId)/\(file.fileName)")
                        .absoluteString
                    continuation.yield(.completed(remoteId: remoteId, url: urlStr))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Realtime（SSE）

    func subscribeRealtime() -> AsyncStream<RealtimeEvent> {
        AsyncStream { continuation in
            // 简化实现：轮询替代 SSE，稳定且对家庭规模足够。
            // SSE 长连可后续接 EventSource；这里每 8 秒拉一次增量。
            let task = Task {
                continuation.yield(.connected)
                var since = Date().addingTimeInterval(-1)
                while !Task.isCancelled {
                    if let entries = try? await self.fetchEntries(since: since) {
                        for e in entries { continuation.yield(.entryChanged(e)) }
                        since = Date()
                    }
                    try? await Task.sleep(for: .seconds(8))
                }
                continuation.yield(.disconnected)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: 连接测试

    func ping() async throws -> Bool {
        let url = baseURL.appendingPathComponent("api/health")
        let (data, resp) = try await URLSession.shared.data(from: url)
        try Self.check(resp, data)
        return true
    }

    // MARK: - 私有：REST 基础

    private func findRecord(collection: String, localId: String, token: String) async throws -> String? {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("api/collections/\(collection)/records"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "filter", value: "(localId='\(localId)')"),
            URLQueryItem(name: "perPage", value: "1"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]],
              let first = items.first, let id = first["id"] as? String else { return nil }
        return id
    }

    private func post(collection: String, json: [String: Any], token: String) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent("api/collections/\(collection)/records")
        return try await send(url: url, method: "POST", json: json, token: token)
    }

    private func patch(collection: String, id: String, json: [String: Any], token: String) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent("api/collections/\(collection)/records/\(id)")
        return try await send(url: url, method: "PATCH", json: json, token: token)
    }

    private func send(url: URL, method: String, json: [String: Any], token: String) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func multipartUpload(_ file: MediaUploadRequest, token: String,
                                 onProgress: @escaping @Sendable (Double) -> Void) async throws -> String {
        let url = baseURL.appendingPathComponent("api/collections/media/records")
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let fileData = try Data(contentsOf: file.fileURL)
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("localId", file.mediaId.uuidString)
        field("entryLocalId", file.entryLocalId.uuidString)
        field("mediaType", file.type.rawValue)
        // 文件
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(file.fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // 用 delegate 捕获上传进度
        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (data, resp) = try await session.upload(for: req, from: body)
        try Self.check(resp, data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String else {
            throw APIError.server(500, "上传响应异常")
        }
        return id
    }

    // MARK: - 私有：编解码

    private static func entryBody(_ dto: EntryDTO) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = [
            "localId": dto.localId,
            "happenedAt": iso.string(from: dto.happenedAt),
            "authorRole": dto.authorRole,
            "isArchived": dto.isArchived,
            "createdAt": iso.string(from: dto.createdAt),
        ]
        if let v = dto.title { body["title"] = v }
        if let v = dto.note { body["note"] = v }
        if let v = dto.firstPersonNote { body["firstPersonNote"] = v }
        if let v = dto.locationName { body["locationName"] = v }
        if let v = dto.latitude { body["latitude"] = v }
        if let v = dto.longitude { body["longitude"] = v }
        if let v = dto.mood { body["mood"] = v }
        if let v = dto.editedAt { body["editedAt"] = iso.string(from: v) }
        return body
    }

    private static func entryDTO(from obj: [String: Any], fallback: EntryDTO?) -> EntryDTO {
        let iso = ISO8601DateFormatter()
        func date(_ key: String) -> Date? {
            (obj[key] as? String).flatMap { iso.date(from: $0) ?? flexibleDate($0) }
        }
        return EntryDTO(
            id: obj["id"] as? String ?? fallback?.id,
            localId: obj["localId"] as? String ?? fallback?.localId ?? UUID().uuidString,
            title: obj["title"] as? String ?? fallback?.title,
            note: obj["note"] as? String ?? fallback?.note,
            firstPersonNote: obj["firstPersonNote"] as? String ?? fallback?.firstPersonNote,
            happenedAt: date("happenedAt") ?? fallback?.happenedAt ?? .now,
            locationName: obj["locationName"] as? String ?? fallback?.locationName,
            latitude: obj["latitude"] as? Double ?? fallback?.latitude,
            longitude: obj["longitude"] as? Double ?? fallback?.longitude,
            authorRole: obj["authorRole"] as? String ?? fallback?.authorRole ?? "",
            mood: obj["mood"] as? String ?? fallback?.mood,
            isArchived: obj["isArchived"] as? Bool ?? fallback?.isArchived ?? false,
            editedAt: date("editedAt") ?? fallback?.editedAt,
            createdAt: date("createdAt") ?? fallback?.createdAt ?? .now
        )
    }

    /// 兼容 PocketBase 的 "2024-01-01 12:00:00.000Z" 格式。
    private static func flexibleDate(_ s: String) -> Date? {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZ"
        return fmt.date(from: s)
    }

    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw APIError.unauthorized
        default:
            let msg = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw APIError.server(http.statusCode, String(msg))
        }
    }
}

// MARK: - Token 容器（actor，线程安全）
private actor TokenBox {
    private var token: String?
    func get() -> String? { token }
    func set(_ t: String?) { token = t }
}

// MARK: - 上传进度 delegate
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let onProgress: @Sendable (Double) -> Void
    init(onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
