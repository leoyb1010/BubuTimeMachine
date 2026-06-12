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

    /// 复用已有 token；过期由各请求的 401 自动重登兜底。
    /// 不再每个同步周期跑一次密码登录（省电、少打服务器）。
    func authenticate(role: String) async throws -> AuthToken {
        AuthToken(token: try await ensureToken(), role: role, expiresAt: nil)
    }

    /// 真正的密码登录。
    private func login() async throws -> String {
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
        return token
    }

    private func ensureToken() async throws -> String {
        if let t = await tokenBox.get() { return t }
        return try await login()
    }

    /// token 过期（401/403）时清掉缓存、重新登录并重试一次；
    /// 瞬时网络抖动（超时/连接被重置/5xx 网关错误，常见于 Cloudflare 隧道/Tailscale）自动退避重试，
    /// 避免家用网络的偶发抖动被上层当成「同步失败」反复报红。
    private func withAuthRetry<T>(_ op: (String) async throws -> T) async throws -> T {
        func attempt() async throws -> T {
            let token = try await ensureToken()
            do {
                return try await op(token)
            } catch APIError.unauthorized {
                await tokenBox.set(nil)
                let fresh = try await ensureToken()
                return try await op(fresh)
            }
        }
        var lastError: Error?
        for i in 0..<3 {
            do { return try await attempt() }
            catch {
                lastError = error
                guard Self.isTransient(error), i < 2 else { throw error }
                try? await Task.sleep(for: .milliseconds(400 * (i + 1)))
            }
        }
        throw lastError ?? APIError.network("请求失败")
    }

    /// 是否为可自愈的瞬时错误（值得退避重试，而非直接判失败）。
    private static func isTransient(_ error: Error) -> Bool {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .networkConnectionLost, .notConnectedToInternet, .resourceUnavailable,
                 .badServerResponse, .secureConnectionFailed, .httpTooManyRedirects:
                return true
            default: return false
            }
        }
        if case APIError.server(let code, _) = error, (500...599).contains(code) {
            return true   // 502/503/504：网关/隧道瞬时不可用
        }
        if case APIError.network = error { return true }
        return false
    }

    // MARK: Entry CRUD（幂等）

    func createEntry(_ dto: EntryDTO) async throws -> EntryDTO {
        let body = Self.entryBody(dto)

        // 先按 localId 查是否已存在
        if let existing = try await findRecord(collection: "entries",
                                               localId: dto.localId) {
            let updated = try await patch(collection: "entries", id: existing,
                                          json: body)
            return Self.entryDTO(from: updated, fallback: dto)
        }
        let created = try await post(collection: "entries", json: body)
        return Self.entryDTO(from: created, fallback: dto)
    }

    func fetchEntries(since: Date?) async throws -> [EntryDTO] {
        let items = try await fetchRecords(collection: "entries", since: since)
        return items.map { Self.entryDTO(from: $0, fallback: nil) }
    }

    func fetchMedia(since: Date?) async throws -> [MediaDTO] {
        let items = try await fetchRecords(collection: "media", since: since)
        return items.map { self.mediaDTO(from: $0) }
    }

    func upsertMilestone(_ dto: MilestoneDTO) async throws -> MilestoneDTO {
        let obj = try await upsert(collection: "milestones", localId: dto.localId, body: Self.milestoneBody(dto))
        return Self.milestoneDTO(from: obj, fallback: dto)
    }

    func fetchMilestones(since: Date?) async throws -> [MilestoneDTO] {
        return try await fetchRecords(collection: "milestones", since: since).map { Self.milestoneDTO(from: $0, fallback: nil) }
    }

    func upsertFirstTime(_ dto: FirstTimeDTO) async throws -> FirstTimeDTO {
        let obj = try await upsert(collection: "firsttimes", localId: dto.localId, body: Self.firstTimeBody(dto))
        return Self.firstTimeDTO(from: obj, fallback: dto)
    }

    func fetchFirstTimes(since: Date?) async throws -> [FirstTimeDTO] {
        return try await fetchRecords(collection: "firsttimes", since: since).map { Self.firstTimeDTO(from: $0, fallback: nil) }
    }

    func upsertFamilyMember(_ dto: FamilyMemberDTO) async throws -> FamilyMemberDTO {
        let obj = try await upsert(collection: "members", localId: dto.localId, body: Self.memberBody(dto))
        return Self.memberDTO(from: obj, fallback: dto)
    }

    func fetchFamilyMembers(since: Date?) async throws -> [FamilyMemberDTO] {
        return try await fetchRecords(collection: "members", since: since).map { Self.memberDTO(from: $0, fallback: nil) }
    }

    func upsertChildProfile(_ dto: ChildProfileDTO) async throws -> ChildProfileDTO {
        let obj = try await upsert(collection: "childprofile", localId: dto.localId, body: Self.childProfileBody(dto))
        return self.childProfileDTO(from: obj, fallback: dto)
    }

    func fetchChildProfiles(since: Date?) async throws -> [ChildProfileDTO] {
        return try await fetchRecords(collection: "childprofile", since: since).map { self.childProfileDTO(from: $0, fallback: nil) }
    }

    func uploadChildAvatar(profileLocalId: UUID, fileURL: URL, fileName: String) -> AsyncThrowingStream<UploadEvent, Error> {
        uploadGenericFile(collection: "childprofile", localId: profileLocalId.uuidString,
                          fields: [:], fileField: "avatar", fileURL: fileURL, fileName: fileName)
    }

    func upsertHealthRecord(_ dto: HealthRecordDTO) async throws -> HealthRecordDTO {
        let obj = try await upsert(collection: "healthrecords", localId: dto.localId, body: Self.healthBody(dto))
        return Self.healthDTO(from: obj, fallback: dto)
    }

    func fetchHealthRecords(since: Date?) async throws -> [HealthRecordDTO] {
        return try await fetchRecords(collection: "healthrecords", since: since).map { Self.healthDTO(from: $0, fallback: nil) }
    }

    func upsertVaccineRecord(_ dto: VaccineRecordDTO) async throws -> VaccineRecordDTO {
        let obj = try await upsert(collection: "vaccinerecords", localId: dto.localId, body: Self.vaccineBody(dto))
        return Self.vaccineDTO(from: obj, fallback: dto)
    }

    func fetchVaccineRecords(since: Date?) async throws -> [VaccineRecordDTO] {
        return try await fetchRecords(collection: "vaccinerecords", since: since).map { Self.vaccineDTO(from: $0, fallback: nil) }
    }

    func deleteVaccineRecord(remoteId: String) async throws {
        try await delete(collection: "vaccinerecords", id: remoteId)
    }

    func upsertGrowthMeasurement(_ dto: GrowthMeasurementDTO) async throws -> GrowthMeasurementDTO {
        let obj = try await upsert(collection: "growthmeasurements", localId: dto.localId, body: Self.growthBody(dto))
        return Self.growthDTO(from: obj, fallback: dto)
    }

    func fetchGrowthMeasurements(since: Date?) async throws -> [GrowthMeasurementDTO] {
        return try await fetchRecords(collection: "growthmeasurements", since: since).map { Self.growthDTO(from: $0, fallback: nil) }
    }

    func upsertComment(_ dto: CommentDTO) async throws -> CommentDTO {
        let obj = try await upsert(collection: "comments", localId: dto.localId, body: Self.commentBody(dto))
        return self.commentDTO(from: obj, fallback: dto)
    }

    func fetchComments(since: Date?) async throws -> [CommentDTO] {
        return try await fetchRecords(collection: "comments", since: since).map { self.commentDTO(from: $0, fallback: nil) }
    }

    func uploadCommentVoice(commentId: UUID, entryLocalId: UUID, fileURL: URL, fileName: String) -> AsyncThrowingStream<UploadEvent, Error> {
        uploadGenericFile(collection: "comments", localId: commentId.uuidString,
                          fields: ["entryLocalId": entryLocalId.uuidString],
                          fileField: "voiceFile", fileURL: fileURL, fileName: fileName)
    }

    func upsertVoiceNote(_ dto: VoiceNoteDTO) async throws -> VoiceNoteDTO {
        let obj = try await upsert(collection: "voicenotes", localId: dto.localId, body: Self.voiceNoteBody(dto))
        return self.voiceNoteDTO(from: obj, fallback: dto)
    }

    func fetchVoiceNotes(since: Date?) async throws -> [VoiceNoteDTO] {
        return try await fetchRecords(collection: "voicenotes", since: since).map { self.voiceNoteDTO(from: $0, fallback: nil) }
    }

    func uploadVoiceNote(voiceId: UUID, entryLocalId: UUID, fileURL: URL, fileName: String) -> AsyncThrowingStream<UploadEvent, Error> {
        uploadGenericFile(collection: "voicenotes", localId: voiceId.uuidString,
                          fields: ["entryLocalId": entryLocalId.uuidString],
                          fileField: "file", fileURL: fileURL, fileName: fileName)
    }

    func upsertVoiceMemo(_ dto: VoiceMemoDTO) async throws -> VoiceMemoDTO {
        let obj = try await upsert(collection: "voicememos", localId: dto.localId, body: Self.voiceMemoBody(dto))
        return self.voiceMemoDTO(from: obj, fallback: dto)
    }

    func fetchVoiceMemos(since: Date?) async throws -> [VoiceMemoDTO] {
        return try await fetchRecords(collection: "voicememos", since: since).map { self.voiceMemoDTO(from: $0, fallback: nil) }
    }

    func uploadVoiceMemo(memoId: UUID, fileURL: URL, fileName: String) -> AsyncThrowingStream<UploadEvent, Error> {
        uploadGenericFile(collection: "voicememos", localId: memoId.uuidString,
                          fields: [:], fileField: "file", fileURL: fileURL, fileName: fileName)
    }

    func upsertTimeCapsule(_ dto: TimeCapsuleDTO) async throws -> TimeCapsuleDTO {
        let obj = try await upsert(collection: "timecapsules", localId: dto.localId,
                                   body: Self.timeCapsuleBody(dto))
        return self.timeCapsuleDTO(from: obj, fallback: dto)
    }

    func fetchTimeCapsules(since: Date?) async throws -> [TimeCapsuleDTO] {
        return try await fetchRecords(collection: "timecapsules", since: since)
            .map { self.timeCapsuleDTO(from: $0, fallback: nil) }
    }

    func uploadTimeCapsuleBlob(capsuleId: UUID, dto: TimeCapsuleDTO, fileURL: URL, fileName: String) -> AsyncThrowingStream<UploadEvent, Error> {
        uploadGenericFile(collection: "timecapsules", localId: capsuleId.uuidString,
                          fields: Self.timeCapsuleStringFields(dto),
                          fileField: "encryptedBlob", fileURL: fileURL, fileName: fileName)
    }

    func deleteTimeCapsule(remoteId: String) async throws {
        try await delete(collection: "timecapsules", id: remoteId)
    }

    func downloadFile(from remoteURL: String) async throws -> Data {
        guard let url = URL(string: remoteURL) else { throw APIError.network("文件地址不正确") }
        return try await withAuthRetry { token in
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            try Self.check(resp, data)
            return data
        }
    }

    // MARK: 媒体上传（multipart + 进度）

    /// 上传结果：PocketBase 会清洗并追加随机后缀改写文件名，远端 URL 必须用响应里的真实文件名拼。
    private struct UploadedFileResult: Sendable {
        let recordId: String
        let storedFileName: String
    }

    func uploadMedia(_ file: MediaUploadRequest) -> AsyncThrowingStream<UploadEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await self.withAuthRetry { token in
                        try await self.multipartUpload(file, token: token) { progress in
                            continuation.yield(.progress(progress))
                        }
                    }
                    let urlStr = self.baseURL
                        .appendingPathComponent("api/files/media/\(result.recordId)/\(result.storedFileName)")
                        .absoluteString
                    continuation.yield(.completed(remoteId: result.recordId, url: urlStr))
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

    /// PocketBase filter 字符串里的单引号转义，杜绝注入面。
    private static func filterEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "'", with: "\\'")
    }

    private func findRecord(collection: String, localId: String) async throws -> String? {
        try await withAuthRetry { token in
            var comps = URLComponents(
                url: self.baseURL.appendingPathComponent("api/collections/\(collection)/records"),
                resolvingAgainstBaseURL: false)!
            comps.queryItems = [
                URLQueryItem(name: "filter", value: "(localId='\(Self.filterEscape(localId))')"),
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
    }

    private func post(collection: String, json: [String: Any]) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent("api/collections/\(collection)/records")
        return try await send(url: url, method: "POST", json: json)
    }

    private func upsert(collection: String, localId: String, body: [String: Any]) async throws -> [String: Any] {
        if let existing = try await findRecord(collection: collection, localId: localId) {
            return try await patch(collection: collection, id: existing, json: body)
        }
        return try await post(collection: collection, json: body)
    }

    /// 翻页拉增量：统一使用 App 自有的 clientUpdatedAt 游标，避免依赖 PocketBase 系统字段。
    private func fetchRecords(collection: String, since: Date?, sort: String? = "clientUpdatedAt") async throws -> [[String: Any]] {
        var all: [[String: Any]] = []
        var page = 1
        while true {
            let (items, totalPages) = try await fetchPage(collection: collection, since: since, sort: sort, page: page)
            all.append(contentsOf: items)
            if page >= totalPages || items.isEmpty { break }
            page += 1
        }
        return all
    }

    private func fetchPage(collection: String, since: Date?, sort: String?,
                           page: Int) async throws -> (items: [[String: Any]], totalPages: Int) {
        try await withAuthRetry { token in
            var comps = URLComponents(
                url: self.baseURL.appendingPathComponent("api/collections/\(collection)/records"),
                resolvingAgainstBaseURL: false)!
            comps.queryItems = Self.listRecordsQueryItems(since: since, sort: sort, page: page)
            var req = URLRequest(url: comps.url!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            try Self.check(resp, data)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = obj["items"] as? [[String: Any]] else { return ([], 1) }
            let totalPages = obj["totalPages"] as? Int ?? 1
            return (items, totalPages)
        }
    }

    static func listRecordsQueryItems(since: Date?, sort: String?, page: Int) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "perPage", value: "200"),
                     URLQueryItem(name: "page", value: "\(page)")]
        if let sort, !sort.isEmpty {
            query.append(URLQueryItem(name: "sort", value: sort))
        }
        if let since {
            query.append(URLQueryItem(name: "filter", value: "(clientUpdatedAt>'\(syncTimestampString(since))')"))
        }
        return query
    }

    private func patch(collection: String, id: String, json: [String: Any]) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent("api/collections/\(collection)/records/\(id)")
        return try await send(url: url, method: "PATCH", json: json)
    }

    private func delete(collection: String, id: String) async throws {
        let url = baseURL.appendingPathComponent("api/collections/\(collection)/records/\(id)")
        _ = try await send(url: url, method: "DELETE", json: [:])
    }

    private func send(url: URL, method: String, json: [String: Any]) async throws -> [String: Any] {
        try await withAuthRetry { token in
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if method != "DELETE" {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: json)
            }
            let (data, resp) = try await URLSession.shared.data(for: req)
            try Self.check(resp, data)
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }
    }

    private func uploadGenericFile(collection: String, localId: String, fields: [String: String],
                                   fileField: String, fileURL: URL, fileName: String) -> AsyncThrowingStream<UploadEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await self.withAuthRetry { token in
                        try await self.multipartUpload(collection: collection,
                                                       localId: localId,
                                                       fields: fields,
                                                       fileField: fileField,
                                                       fileURL: fileURL,
                                                       fileName: fileName,
                                                       token: token) { progress in
                            continuation.yield(.progress(progress))
                        }
                    }
                    let urlStr = self.baseURL
                        .appendingPathComponent("api/files/\(collection)/\(result.recordId)/\(result.storedFileName)")
                        .absoluteString
                    continuation.yield(.completed(remoteId: result.recordId, url: urlStr))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func multipartUpload(collection: String, localId: String, fields: [String: String], fileField: String,
                                 fileURL: URL, fileName: String, token: String,
                                 onProgress: @escaping @Sendable (Double) -> Void) async throws -> UploadedFileResult {
        let existingId = try await findRecord(collection: collection, localId: localId)
        let url = existingId.map {
            baseURL.appendingPathComponent("api/collections/\(collection)/records/\($0)")
        } ?? baseURL.appendingPathComponent("api/collections/\(collection)/records")
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = existingId == nil ? "POST" : "PATCH"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var uploadFields = fields
        uploadFields["localId"] = localId
        Self.addSyncTimestamp(to: &uploadFields)
        let bodyURL = try multipartBodyFile(boundary: boundary, fields: uploadFields,
                                            fileField: fileField, fileURL: fileURL, fileName: fileName)
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        // URLSession 强持有 delegate，不 invalidate 会逐次泄漏 session + delegate
        defer { session.finishTasksAndInvalidate() }
        let (data, resp) = try await session.upload(for: req, fromFile: bodyURL)
        try Self.check(resp, data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String else { throw APIError.server(500, "上传响应异常") }
        let storedFileName = (obj[fileField] as? String) ?? fileName
        return UploadedFileResult(recordId: id, storedFileName: storedFileName)
    }

    private func multipartUpload(_ file: MediaUploadRequest, token: String,
                                 onProgress: @escaping @Sendable (Double) -> Void) async throws -> UploadedFileResult {
        let existingId = try await findRecord(collection: "media", localId: file.mediaId.uuidString)
        let url = existingId.map {
            baseURL.appendingPathComponent("api/collections/media/records/\($0)")
        } ?? baseURL.appendingPathComponent("api/collections/media/records")
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = existingId == nil ? "POST" : "PATCH"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var fields = [
            "localId": file.mediaId.uuidString,
            "entryLocalId": file.entryLocalId.uuidString,
            "mediaType": file.type.rawValue,
        ]
        Self.addSyncTimestamp(to: &fields)
        let bodyURL = try multipartBodyFile(
            boundary: boundary,
            fields: fields,
            fileField: "file",
            fileURL: file.fileURL,
            fileName: file.fileName
        )
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        // 用 delegate 捕获上传进度
        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        // URLSession 强持有 delegate，不 invalidate 会逐次泄漏 session + delegate
        defer { session.finishTasksAndInvalidate() }
        let (data, resp) = try await session.upload(for: req, fromFile: bodyURL)
        try Self.check(resp, data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String else {
            throw APIError.server(500, "上传响应异常")
        }
        let storedFileName = (obj["file"] as? String) ?? file.fileName
        return UploadedFileResult(recordId: id, storedFileName: storedFileName)
    }

    private func multipartBodyFile(boundary: String, fields: [String: String], fileField: String,
                                   fileURL: URL, fileName: String) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bubu-upload-\(UUID().uuidString).body")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: tempURL)
        defer { try? output.close() }

        func write(_ string: String) throws {
            try output.write(contentsOf: Data(string.utf8))
        }

        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            try write("\(value)\r\n")
        }

        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n")
        try write("Content-Type: application/octet-stream\r\n\r\n")

        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while true {
            let chunk = try input.read(upToCount: 1_048_576)
            guard let chunk, !chunk.isEmpty else { break }
            try output.write(contentsOf: chunk)
        }

        try write("\r\n--\(boundary)--\r\n")
        return tempURL
    }

    // MARK: - 私有：编解码

    static func syncTimestampString(_ date: Date = .now) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func addSyncTimestamp(to body: inout [String: Any], date: Date = .now) {
        body["clientUpdatedAt"] = syncTimestampString(date)
    }

    static func addSyncTimestamp(to fields: inout [String: String], date: Date = .now) {
        fields["clientUpdatedAt"] = syncTimestampString(date)
    }

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
        if let v = dto.familyId { body["familyId"] = v }
        if let v = dto.authorUserId { body["authorUserId"] = v }
        if let v = dto.note { body["note"] = v }
        if let v = dto.firstPersonNote { body["firstPersonNote"] = v }
        if let v = dto.locationName { body["locationName"] = v }
        if let v = dto.latitude { body["latitude"] = v }
        if let v = dto.longitude { body["longitude"] = v }
        if let v = dto.mood { body["mood"] = v }
        if let v = dto.editedAt { body["editedAt"] = iso.string(from: v) }
        addSyncTimestamp(to: &body)
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
            familyId: obj["familyId"] as? String ?? fallback?.familyId,
            authorUserId: obj["authorUserId"] as? String ?? fallback?.authorUserId,
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

    private func mediaDTO(from obj: [String: Any]) -> MediaDTO {
        let iso = ISO8601DateFormatter()
        let id = obj["id"] as? String
        let fileName = (obj["file"] as? String) ?? ""
        let remoteURL = id.flatMap { recordId in
            fileName.isEmpty ? nil : baseURL.appendingPathComponent("api/files/media/\(recordId)/\(fileName)").absoluteString
        }
        return MediaDTO(
            id: id,
            localId: obj["localId"] as? String ?? UUID().uuidString,
            entryLocalId: obj["entryLocalId"] as? String ?? "",
            mediaType: obj["mediaType"] as? String ?? "photo",
            remoteURL: remoteURL,
            durationSeconds: obj["durationSeconds"] as? Double,
            width: obj["width"] as? Int,
            height: obj["height"] as? Int,
            aiTags: obj["aiTags"] as? [String] ?? [],
            createdAt: (obj["created"] as? String).flatMap { iso.date(from: $0) ?? Self.flexibleDate($0) } ?? .now
        )
    }

    private static func milestoneBody(_ dto: MilestoneDTO) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = ["localId": dto.localId, "title": dto.title, "category": dto.category, "emoji": dto.emoji, "isCustom": dto.isCustom]
        if let v = dto.detail { body["detail"] = v }
        if let v = dto.happenedAt { body["happenedAt"] = iso.string(from: v) }
        if let v = dto.ageDescription { body["ageDescription"] = v }
        addSyncTimestamp(to: &body)
        return body
    }

    private static func milestoneDTO(from obj: [String: Any], fallback: MilestoneDTO?) -> MilestoneDTO {
        let iso = ISO8601DateFormatter()
        func date(_ key: String) -> Date? { (obj[key] as? String).flatMap { iso.date(from: $0) ?? flexibleDate($0) } }
        return MilestoneDTO(id: obj["id"] as? String ?? fallback?.id,
                            localId: obj["localId"] as? String ?? fallback?.localId ?? UUID().uuidString,
                            title: obj["title"] as? String ?? fallback?.title ?? "",
                            category: obj["category"] as? String ?? fallback?.category ?? "",
                            emoji: obj["emoji"] as? String ?? fallback?.emoji ?? "🌟",
                            detail: obj["detail"] as? String ?? fallback?.detail,
                            happenedAt: date("happenedAt") ?? fallback?.happenedAt,
                            ageDescription: obj["ageDescription"] as? String ?? fallback?.ageDescription,
                            isCustom: obj["isCustom"] as? Bool ?? fallback?.isCustom ?? false,
                            createdAt: date("created") ?? fallback?.createdAt ?? .now)
    }

    private static func firstTimeBody(_ dto: FirstTimeDTO) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = ["localId": dto.localId, "what": dto.what, "happenedAt": iso.string(from: dto.happenedAt), "detectedByAI": dto.detectedByAI, "confirmedByParent": dto.confirmedByParent]
        if let v = dto.entryLocalId { body["entryLocalId"] = v }
        addSyncTimestamp(to: &body)
        return body
    }

    private static func firstTimeDTO(from obj: [String: Any], fallback: FirstTimeDTO?) -> FirstTimeDTO {
        let iso = ISO8601DateFormatter()
        func date(_ key: String) -> Date? { (obj[key] as? String).flatMap { iso.date(from: $0) ?? flexibleDate($0) } }
        return FirstTimeDTO(id: obj["id"] as? String ?? fallback?.id,
                            localId: obj["localId"] as? String ?? fallback?.localId ?? UUID().uuidString,
                            what: obj["what"] as? String ?? fallback?.what ?? "",
                            happenedAt: date("happenedAt") ?? fallback?.happenedAt ?? .now,
                            detectedByAI: obj["detectedByAI"] as? Bool ?? fallback?.detectedByAI ?? false,
                            confirmedByParent: obj["confirmedByParent"] as? Bool ?? fallback?.confirmedByParent ?? false,
                            entryLocalId: obj["entryLocalId"] as? String ?? fallback?.entryLocalId,
                            createdAt: date("created") ?? fallback?.createdAt ?? .now)
    }

    private static func memberBody(_ dto: FamilyMemberDTO) -> [String: Any] {
        var body: [String: Any] = ["localId": dto.localId, "name": dto.name, "relation": dto.relation, "avatarEmoji": dto.avatarEmoji, "themeColorHex": dto.themeColorHex, "isPrimary": dto.isPrimary]
        addSyncTimestamp(to: &body)
        return body
    }

    private static func memberDTO(from obj: [String: Any], fallback: FamilyMemberDTO?) -> FamilyMemberDTO {
        FamilyMemberDTO(id: obj["id"] as? String ?? fallback?.id,
                        localId: obj["localId"] as? String ?? fallback?.localId ?? UUID().uuidString,
                        name: obj["name"] as? String ?? fallback?.name ?? "",
                        relation: obj["relation"] as? String ?? fallback?.relation ?? "",
                        avatarEmoji: obj["avatarEmoji"] as? String ?? fallback?.avatarEmoji ?? "🙂",
                        themeColorHex: obj["themeColorHex"] as? String ?? fallback?.themeColorHex ?? "#F28C9E",
                        isPrimary: obj["isPrimary"] as? Bool ?? fallback?.isPrimary ?? false,
                        createdAt: fallback?.createdAt ?? .now)
    }

    private static func childProfileBody(_ dto: ChildProfileDTO) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = ["localId": dto.localId, "name": dto.name, "birthday": iso.string(from: dto.birthday)]
        if let v = dto.gender { body["gender"] = v }
        if let v = dto.birthPlace { body["birthPlace"] = v }
        addSyncTimestamp(to: &body)
        return body
    }

    private func childProfileDTO(from obj: [String: Any], fallback: ChildProfileDTO?) -> ChildProfileDTO {
        let iso = ISO8601DateFormatter()
        func date(_ key: String) -> Date? { (obj[key] as? String).flatMap { iso.date(from: $0) ?? Self.flexibleDate($0) } }
        let avatarFile = (obj["avatar"] as? String) ?? ""
        let avatarRemoteURL = remoteFileURL(collection: "childprofile", recordId: obj["id"] as? String, fileName: avatarFile)
        return ChildProfileDTO(id: obj["id"] as? String ?? fallback?.id,
                               localId: obj["localId"] as? String ?? fallback?.localId ?? UUID().uuidString,
                               name: obj["name"] as? String ?? fallback?.name ?? "布布",
                               birthday: date("birthday") ?? fallback?.birthday ?? .now,
                               gender: obj["gender"] as? String ?? fallback?.gender,
                               birthPlace: obj["birthPlace"] as? String ?? fallback?.birthPlace,
                               avatarRemoteURL: avatarRemoteURL ?? fallback?.avatarRemoteURL,
                               createdAt: fallback?.createdAt ?? .now)
    }

    private static func vaccineBody(_ dto: VaccineRecordDTO) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = ["localId": dto.localId, "vaccineName": dto.vaccineName,
                                   "injectedAt": iso.string(from: dto.injectedAt), "sourceRaw": dto.source]
        if let v = dto.doseId { body["doseId"] = v }
        if let v = dto.doseLabel { body["doseLabel"] = v }
        if let v = dto.hospital { body["hospital"] = v }
        if let v = dto.injectionSite { body["injectionSite"] = v }
        if let v = dto.reaction { body["reaction"] = v }
        if let v = dto.note { body["note"] = v }
        addSyncTimestamp(to: &body)
        return body
    }

    private static func vaccineDTO(from obj: [String: Any], fallback: VaccineRecordDTO?) -> VaccineRecordDTO {
        let iso = ISO8601DateFormatter()
        func date(_ key: String) -> Date? { (obj[key] as? String).flatMap { iso.date(from: $0) ?? flexibleDate($0) } }
        return VaccineRecordDTO(id: obj["id"] as? String ?? fallback?.id,
                                localId: obj["localId"] as? String ?? fallback?.localId ?? UUID().uuidString,
                                doseId: obj["doseId"] as? String ?? fallback?.doseId,
                                vaccineName: obj["vaccineName"] as? String ?? fallback?.vaccineName ?? "",
                                doseLabel: obj["doseLabel"] as? String ?? fallback?.doseLabel,
                                injectedAt: date("injectedAt") ?? fallback?.injectedAt ?? .now,
                                hospital: obj["hospital"] as? String ?? fallback?.hospital,
                                injectionSite: obj["injectionSite"] as? String ?? fallback?.injectionSite,
                                reaction: obj["reaction"] as? String ?? fallback?.reaction,
                                note: obj["note"] as? String ?? fallback?.note,
                                source: obj["sourceRaw"] as? String ?? fallback?.source ?? "manual",
                                createdAt: date("created") ?? fallback?.createdAt ?? .now)
    }

    private static func growthBody(_ dto: GrowthMeasurementDTO) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = ["localId": dto.localId,
                                   "measuredAt": iso.string(from: dto.measuredAt), "sourceRaw": dto.source]
        if let v = dto.heightCm { body["heightCm"] = v }
        if let v = dto.weightKg { body["weightKg"] = v }
        if let v = dto.headCircumferenceCm { body["headCircumferenceCm"] = v }
        if let v = dto.note { body["note"] = v }
        addSyncTimestamp(to: &body)
        return body
    }

    private static func growthDTO(from obj: [String: Any], fallback: GrowthMeasurementDTO?) -> GrowthMeasurementDTO {
        let iso = ISO8601DateFormatter()
        func date(_ key: String) -> Date? { (obj[key] as? String).flatMap { iso.date(from: $0) ?? flexibleDate($0) } }
        return GrowthMeasurementDTO(id: obj["id"] as? String ?? fallback?.id,
                                    localId: obj["localId"] as? String ?? fallback?.localId ?? UUID().uuidString,
                                    measuredAt: date("measuredAt") ?? fallback?.measuredAt ?? .now,
                                    heightCm: obj["heightCm"] as? Double ?? fallback?.heightCm,
                                    weightKg: obj["weightKg"] as? Double ?? fallback?.weightKg,
                                    headCircumferenceCm: obj["headCircumferenceCm"] as? Double ?? fallback?.headCircumferenceCm,
                                    note: obj["note"] as? String ?? fallback?.note,
                                    source: obj["sourceRaw"] as? String ?? fallback?.source ?? "manual",
                                    createdAt: date("created") ?? fallback?.createdAt ?? .now)
    }

    private static func healthBody(_ dto: HealthRecordDTO) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = ["localId": dto.localId, "kind": dto.kind, "title": dto.title, "recordedAt": iso.string(from: dto.recordedAt)]
        if let v = dto.detail { body["detail"] = v }
        if let v = dto.amountText { body["amountText"] = v }
        if let v = dto.reaction { body["reaction"] = v }
        if let v = dto.amountValue { body["amountValue"] = v }
        if let v = dto.amountUnit { body["amountUnit"] = v }
        if let v = dto.startAt { body["startAt"] = iso.string(from: v) }
        if let v = dto.endAt { body["endAt"] = iso.string(from: v) }
        if let v = dto.severity { body["severity"] = v }
        if let v = dto.temperatureCelsius { body["temperatureCelsius"] = v }
        body["tags"] = dto.tags
        addSyncTimestamp(to: &body)
        return body
    }

    private static func healthDTO(from obj: [String: Any], fallback: HealthRecordDTO?) -> HealthRecordDTO {
        let iso = ISO8601DateFormatter()
        func date(_ key: String) -> Date? { (obj[key] as? String).flatMap { iso.date(from: $0) ?? flexibleDate($0) } }
        return HealthRecordDTO(id: obj["id"] as? String ?? fallback?.id,
                               localId: obj["localId"] as? String ?? fallback?.localId ?? UUID().uuidString,
                               kind: obj["kind"] as? String ?? fallback?.kind ?? "meal",
                               title: obj["title"] as? String ?? fallback?.title ?? "",
                               detail: obj["detail"] as? String ?? fallback?.detail,
                               recordedAt: date("recordedAt") ?? fallback?.recordedAt ?? .now,
                               amountText: obj["amountText"] as? String ?? fallback?.amountText,
                               reaction: obj["reaction"] as? String ?? fallback?.reaction,
                               amountValue: obj["amountValue"] as? Double ?? fallback?.amountValue,
                               amountUnit: obj["amountUnit"] as? String ?? fallback?.amountUnit,
                               startAt: date("startAt") ?? fallback?.startAt,
                               endAt: date("endAt") ?? fallback?.endAt,
                               severity: obj["severity"] as? String ?? fallback?.severity,
                               temperatureCelsius: obj["temperatureCelsius"] as? Double ?? fallback?.temperatureCelsius,
                               tags: obj["tags"] as? [String] ?? fallback?.tags ?? [],
                               createdAt: date("created") ?? fallback?.createdAt ?? .now)
    }

    private static func commentBody(_ dto: CommentDTO) -> [String: Any] {
        var body: [String: Any] = ["localId": dto.localId, "entryLocalId": dto.entryLocalId, "authorRole": dto.authorRole, "voiceDuration": dto.voiceDuration, "voiceWaveform": dto.voiceWaveform]
        if let v = dto.text { body["text"] = v }
        addSyncTimestamp(to: &body)
        return body
    }

    private func commentDTO(from obj: [String: Any], fallback: CommentDTO?) -> CommentDTO {
        let iso = ISO8601DateFormatter()
        let id = obj["id"] as? String
        let fileName = (obj["voiceFile"] as? String) ?? ""
        let remoteURL = remoteFileURL(collection: "comments", recordId: id, fileName: fileName)
        return CommentDTO(id: id ?? fallback?.id,
                          localId: obj["localId"] as? String ?? fallback?.localId ?? UUID().uuidString,
                          entryLocalId: obj["entryLocalId"] as? String ?? fallback?.entryLocalId ?? "",
                          authorRole: obj["authorRole"] as? String ?? fallback?.authorRole ?? "",
                          text: obj["text"] as? String ?? fallback?.text,
                          remoteURL: remoteURL ?? fallback?.remoteURL,
                          voiceDuration: obj["voiceDuration"] as? Double ?? fallback?.voiceDuration ?? 0,
                          voiceWaveform: obj["voiceWaveform"] as? [Float] ?? fallback?.voiceWaveform ?? [],
                          createdAt: (obj["created"] as? String).flatMap { iso.date(from: $0) ?? Self.flexibleDate($0) } ?? fallback?.createdAt ?? .now)
    }

    private static func voiceNoteBody(_ dto: VoiceNoteDTO) -> [String: Any] {
        var body: [String: Any] = ["localId": dto.localId, "entryLocalId": dto.entryLocalId, "authorRole": dto.authorRole, "durationSeconds": dto.durationSeconds, "waveform": dto.waveform]
        if let v = dto.transcript { body["transcript"] = v }
        addSyncTimestamp(to: &body)
        return body
    }

    private func voiceNoteDTO(from obj: [String: Any], fallback: VoiceNoteDTO?) -> VoiceNoteDTO {
        let iso = ISO8601DateFormatter()
        let id = obj["id"] as? String
        let fileName = (obj["file"] as? String) ?? ""
        let remoteURL = remoteFileURL(collection: "voicenotes", recordId: id, fileName: fileName)
        return VoiceNoteDTO(id: id ?? fallback?.id,
                            localId: obj["localId"] as? String ?? fallback?.localId ?? UUID().uuidString,
                            entryLocalId: obj["entryLocalId"] as? String ?? fallback?.entryLocalId ?? "",
                            authorRole: obj["authorRole"] as? String ?? fallback?.authorRole ?? "",
                            remoteURL: remoteURL ?? fallback?.remoteURL,
                            durationSeconds: obj["durationSeconds"] as? Double ?? fallback?.durationSeconds ?? 0,
                            transcript: obj["transcript"] as? String ?? fallback?.transcript,
                            waveform: obj["waveform"] as? [Float] ?? fallback?.waveform ?? [],
                            createdAt: (obj["created"] as? String).flatMap { iso.date(from: $0) ?? Self.flexibleDate($0) } ?? fallback?.createdAt ?? .now)
    }

    private static func voiceMemoBody(_ dto: VoiceMemoDTO) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = ["localId": dto.localId, "kind": dto.kind, "recordedAt": iso.string(from: dto.recordedAt)]
        if let v = dto.transcript { body["transcript"] = v }
        if let v = dto.ageYears { body["ageYears"] = v }
        if let v = dto.durationSeconds { body["durationSeconds"] = v }
        addSyncTimestamp(to: &body)
        return body
    }

    private func voiceMemoDTO(from obj: [String: Any], fallback: VoiceMemoDTO?) -> VoiceMemoDTO {
        let iso = ISO8601DateFormatter()
        func date(_ key: String) -> Date? { (obj[key] as? String).flatMap { iso.date(from: $0) ?? Self.flexibleDate($0) } }
        let id = obj["id"] as? String
        let fileName = (obj["file"] as? String) ?? ""
        let remoteURL = remoteFileURL(collection: "voicememos", recordId: id, fileName: fileName)
        return VoiceMemoDTO(id: id ?? fallback?.id,
                            localId: obj["localId"] as? String ?? fallback?.localId ?? UUID().uuidString,
                            kind: obj["kind"] as? String ?? fallback?.kind ?? "childVoice",
                            remoteURL: remoteURL ?? fallback?.remoteURL,
                            transcript: obj["transcript"] as? String ?? fallback?.transcript,
                            ageYears: obj["ageYears"] as? Int ?? fallback?.ageYears,
                            recordedAt: date("recordedAt") ?? fallback?.recordedAt ?? .now,
                            durationSeconds: obj["durationSeconds"] as? Double ?? fallback?.durationSeconds,
                            createdAt: date("created") ?? fallback?.createdAt ?? .now)
    }

    private static func timeCapsuleBody(_ dto: TimeCapsuleDTO) -> [String: Any] {
        var body = timeCapsuleStringFields(dto).reduce(into: [String: Any]()) { result, pair in
            result[pair.key] = pair.value
        }
        body["isLocked"] = dto.isLocked
        return body
    }

    private static func timeCapsuleStringFields(_ dto: TimeCapsuleDTO) -> [String: String] {
        let iso = ISO8601DateFormatter()
        var fields: [String: String] = [
            "localId": dto.localId,
            "title": dto.title,
            "fromRole": dto.fromRole,
            "unlockAt": iso.string(from: dto.unlockAt),
            "isLocked": dto.isLocked ? "true" : "false",
        ]
        if let emoji = dto.coverEmoji { fields["coverEmoji"] = emoji }
        addSyncTimestamp(to: &fields)
        return fields
    }

    private func timeCapsuleDTO(from obj: [String: Any], fallback: TimeCapsuleDTO?) -> TimeCapsuleDTO {
        let iso = ISO8601DateFormatter()
        func date(_ key: String) -> Date? { (obj[key] as? String).flatMap { iso.date(from: $0) ?? Self.flexibleDate($0) } }
        let id = obj["id"] as? String
        let fileName = (obj["encryptedBlob"] as? String) ?? ""
        let remoteURL = remoteFileURL(collection: "timecapsules", recordId: id, fileName: fileName)
        return TimeCapsuleDTO(
            id: id ?? fallback?.id,
            localId: obj["localId"] as? String ?? fallback?.localId ?? UUID().uuidString,
            title: obj["title"] as? String ?? fallback?.title ?? "",
            fromRole: obj["fromRole"] as? String ?? fallback?.fromRole ?? "",
            unlockAt: date("unlockAt") ?? fallback?.unlockAt ?? .now,
            isLocked: obj["isLocked"] as? Bool ?? fallback?.isLocked ?? true,
            encryptedBlobRemoteURL: remoteURL ?? fallback?.encryptedBlobRemoteURL,
            coverEmoji: obj["coverEmoji"] as? String ?? fallback?.coverEmoji,
            createdAt: date("created") ?? fallback?.createdAt ?? .now
        )
    }

    private func remoteFileURL(collection: String, recordId: String?, fileName: String) -> String? {
        guard let recordId, !fileName.isEmpty else { return nil }
        return baseURL.appendingPathComponent("api/files/\(collection)/\(recordId)/\(fileName)").absoluteString
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
