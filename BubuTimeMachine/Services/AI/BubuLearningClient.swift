import Foundation
import AVFoundation
import CryptoKit
import ImageIO
import UIKit
import Synchronization

// MARK: - DTOs
// Server JSON is snake_case; the decoder converts keys. Every URL the server
// returns is a same-origin `/learning/...` path that still needs the bearer.

nonisolated struct OnlineTimelineSegment: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let start: Double
    let end: Double
    let text: String
}

nonisolated struct OnlineTimelineItem: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let contentHash: String
    let kind: String
    let capturedAt: String?
    let localDay: String?
    let description: String
    let ocr: String
    let tags: [String]
    let segments: [OnlineTimelineSegment]
    let labelProvenanceText: String
    let previewUrl: String
    let largeUrl: String
    let mediaUrl: String
    // 2.25: layout, people, place and family decisions; optional for older servers.
    let aspect: Double?
    let people: [String]?
    let place: String?
    let confirmedByFamily: Bool?
    let descriptionAdjusted: Bool?
    let transcriptHidden: Int?

    var isVideo: Bool { kind == "video" }
    /// Width / height, clamped so a panorama or a tall screenshot can't break a row.
    var layoutAspect: Double { min(max(aspect ?? 1, 0.56), 2.2) }
    var capturedDate: Date? { capturedAt.flatMap(BubuLearningDates.parseISO) }
}

nonisolated struct OnlineTimelineMonthCount: Codable, Sendable, Hashable { let month: String; let count: Int }
nonisolated struct OnlineTimelinePerson: Decodable, Sendable, Hashable {
    let name: String
    let label: String?
    let count: Int
    var display: String { label?.isEmpty == false ? label! : name }
}
nonisolated struct OnlineTimelinePeople: Decodable, Sendable { let items: [OnlineTimelinePerson] }
nonisolated struct OnlineTimelineItems: Decodable, Sendable { let items: [OnlineTimelineItem] }

nonisolated struct OnlineTimelinePage: Codable, Sendable {
    let items: [OnlineTimelineItem]
    let total: Int
    let page: Int
    let hasMore: Bool
    let photos: Int
    let videos: Int
    let snapshotId: String
    let months: [OnlineTimelineMonthCount]?
}

nonisolated struct LearningContextDTO: Decodable, Sendable {
    struct User: Decodable, Sendable { let id: String; let canReview: Bool }
    struct Child: Decodable, Sendable, Hashable { let id: String; let name: String }
    let user: User
    let children: [Child]
    let defaultChild: String?
}

nonisolated struct LearningClipDTO: Decodable, Sendable, Hashable {
    let sourceId: String?
    let segmentId: String?
    let role: String
    let text: String?
    let start: Double?
    let end: Double?
    let audioUrl: String?
    let imageUrl: String?
}

nonisolated struct LearningChoiceDTO: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let label: String
    let color: String?
    let colors: [String]?
    let evidence: LearningClipDTO?
    let imageUrl: String?
}

nonisolated struct LearningActivityDTO: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let concept: String?
    let instruction: String?
    let correctChoice: String?
    let prompt: LearningClipDTO?
    let answer: LearningClipDTO?
    let choices: [LearningChoiceDTO]

    var isChoice: Bool { ["listen_choice", "color_choice", "sort"].contains(kind) }
    var kindLabel: String {
        switch kind {
        case "listen_choice": "听一听，找一找"
        case "color_choice": "认颜色"
        case "sort": "放一放"
        case "speak": "跟老师说"
        case "music": "一起唱"
        default: "互动"
        }
    }
}

nonisolated struct LearningPackDTO: Decodable, Sendable, Hashable {
    struct Payload: Decodable, Sendable, Hashable {
        let title: String
        let summary: String
        let activities: [LearningActivityDTO]
        let warnings: [String]
    }
    struct Confirmation: Codable, Sendable, Hashable { let activityId: String; let digest: String }
    let id: String
    let childId: String
    let schoolDate: String
    let revision: Int
    let status: String
    let title: String
    let payload: Payload
    let confirmations: [Confirmation]
}

nonisolated struct LearningSegmentDTO: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let start: Double
    let end: Double
    let text: String
}

nonisolated struct LearningSourceDTO: Decodable, Sendable, Hashable, Identifiable {
    struct Analysis: Decodable, Sendable, Hashable {
        let description: String
        let ocr: String
        let tags: [String]
        let segments: [LearningSegmentDTO]
        let warnings: [String]
    }
    let id: String
    let name: String
    let kind: String
    let mime: String
    let schoolDate: String
    let state: String
    let revision: Int
    let analysis: Analysis
    let error: String
    let originalUrl: String?
}

nonisolated struct LearningPackRefDTO: Decodable, Sendable, Hashable { let id: String; let status: String }

nonisolated struct LearningCourseDTO: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let childId: String
    let schoolDate: String
    let title: String
    let kind: String
    let language: String
    let createdAt: String?
    let state: String
    let sourceCount: Int
    let expectedFiles: Int?
    let activityCount: Int
    let pack: LearningPackRefDTO?
    /// Parent's note on what the teacher taught; absent on older servers.
    var note: String? = nil

    var kindLabel: String { LearningCourseKind(rawValue: kind)?.label ?? "课程" }
}

nonisolated struct LearningCourseDetailDTO: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let childId: String
    let schoolDate: String
    let title: String
    let kind: String
    let language: String
    let state: String
    let sourceCount: Int
    let expectedFiles: Int?
    let activityCount: Int
    let pack: LearningPackDTO?
    let sources: [LearningSourceDTO]
    /// Parent's note on what the teacher taught; absent on older servers.
    var note: String? = nil

    var kindLabel: String { LearningCourseKind(rawValue: kind)?.label ?? "课程" }
}

nonisolated struct LearningCourseList: Decodable, Sendable { let items: [LearningCourseDTO] }

nonisolated struct LearningReviewDTO: Decodable, Sendable {
    struct Item: Decodable, Sendable, Hashable {
        let packId: String
        let activityId: String
        let concept: String
        let reason: String
        let activity: LearningActivityDTO
    }
    let windowStart: String
    let windowEnd: String
    let items: [Item]
}

nonisolated enum LearningCourseKind: String, CaseIterable, Identifiable, Sendable {
    case teaching, practice, song
    var id: String { rawValue }
    var label: String {
        switch self { case .teaching: "教学"; case .practice: "练习"; case .song: "儿歌" }
    }
    var symbol: String {
        switch self { case .teaching: "book.fill"; case .practice: "hand.raised.fill"; case .song: "music.note" }
    }
}

nonisolated struct LearningAttemptBody: Codable, Sendable, Hashable {
    let id: String
    let childId: String
    let packId: String
    let activityId: String
    let kind: String
    var choice: String?
    var assistance: Bool?
}

nonisolated struct LearningUploadFile: Sendable, Hashable {
    let url: URL
    let fileName: String
    let mimeType: String
}

/// Family dates are Shanghai calendar days on the server; every key, range and label here uses that zone.
nonisolated enum BubuLearningDates {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }()
    // ISO8601DateFormatter is thread-safe for parsing but not marked Sendable.
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parseISO(_ value: String) -> Date? {
        isoFractional.date(from: value) ?? isoPlain.date(from: value)
    }

    static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }

    static func day(_ value: String) -> Date? { dayFormatter.date(from: value) }

    /// "2026-10" for a Shanghai calendar day.
    static func monthKey(_ date: Date) -> String { String(dayString(date).prefix(7)) }
}

// MARK: - Client

/// Bearer-only client for the family learning/timeline service. Never follows
/// redirects, never sends cookies, and only resolves same-origin `/learning` paths.
nonisolated struct BubuLearningClient: Sendable {
    let routes: LearningServiceRoutes
    /// Identity for caches; contains no credential.
    let scope: String
    private let token: @Sendable () async throws -> String
    private let session: URLSession

    private let mediaSession: URLSession

    /// One ephemeral session for JSON calls; clients are cheap values rebuilt with views.
    static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }()

    /// Images and clips get their own connections so a scrolling grid never starves JSON calls.
    static let mediaSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }()

    init(baseURL: URL, scope: String, token: @escaping @Sendable () async throws -> String,
         session: URLSession = BubuLearningClient.sharedSession,
         mediaSession: URLSession = BubuLearningClient.mediaSession) {
        routes = LearningServiceRoutes(baseURL: baseURL)
        self.scope = scope
        self.token = token
        self.session = session
        self.mediaSession = mediaSession
    }

    @MainActor
    init?(env: AppEnvironment) {
        guard let access = LearningServiceAccess(env, requiresAIEnabled: false) else { return nil }
        let api = env.apiClient
        self.init(baseURL: access.baseURL, scope: access.account + "\n" + access.baseURL.absoluteString,
                  token: { try await api.authenticate(role: "ai").token })
    }

    /// `path` is either a server-returned `/learning/...` path (may carry a query) or `api/...` relative to root.
    func url(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        var components: URLComponents
        if path.hasPrefix("/") {
            guard let given = URLComponents(string: path), given.path.hasPrefix("/learning/") else {
                throw LearningServiceError.invalidAddress
            }
            components = URLComponents(url: routes.root, resolvingAgainstBaseURL: false)!
            components.percentEncodedPath = routes.root.path + String(given.percentEncodedPath.dropFirst("/learning".count))
            components.percentEncodedQuery = given.percentEncodedQuery
        } else {
            components = URLComponents(url: routes.root.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        }
        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
            // URLComponents leaves "+" as-is and servers read it as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url, routes.allowsNavigation(to: url) else { throw LearningServiceError.invalidAddress }
        return url
    }

    private func authorized(_ url: URL, method: String = "GET", timeout: TimeInterval = 30) async throws -> URLRequest {
        let value = try await token()
        guard !value.isEmpty else { throw LearningServiceError.unauthorized }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(value)", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "X-Bubu-Learning")
        return request
    }

    private func check(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse, let responseURL = http.url,
              routes.allowsNavigation(to: responseURL) else { throw LearningServiceError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw LearningServiceError.unauthorized
        // 403 is "signed in, but this account may not do that" (e.g. a non-parent reviewing). Reconnecting won't help.
        case 403: throw BubuLearningClientError.message(Self.detail(data) ?? LearningErrorKind.forbiddenText)
        case 404: throw LearningServiceError.unavailableMedia
        case 409: throw BubuLearningClientError.conflict
        case 413: throw BubuLearningClientError.message("文件太大了，单个文件请小于 256 MB。")
        case 422: throw BubuLearningClientError.message(Self.detail(data) ?? "内容没有通过检查，请核对后重试。")
        case 429: throw BubuLearningClientError.message(Self.detail(data) ?? LearningErrorKind.tooFrequentText)
        case 503: throw BubuLearningClientError.unavailable(Self.detail(data))
        default: throw LearningServiceError.server(http.statusCode)
        }
    }

    /// The server's own Chinese explanation. Framework defaults ("Not authenticated", "Forbidden") are English
    /// and mean nothing to a parent, so only text containing Chinese is passed through.
    static func detail(_ data: Data?) -> String? {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["detail"] as? String, containsChinese(text) else { return nil }
        return text
    }

    static func containsChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    /// Ask waits for the model (server TIMEOUT=60), so it gets a little longer than the rest.
    static func requestTimeout(for path: String) -> TimeInterval {
        path == "api/ask" ? 65 : 30
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    @concurrent
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        var request = try await authorized(url(path, query: query))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request, delegate: LearningRedirectBlocker())
        try check(response, data: data)
        do { return try Self.decoder.decode(T.self, from: data) } catch { throw LearningServiceError.invalidResponse }
    }

    @concurrent
    func send<T: Decodable & Sendable>(_ method: String, _ path: String, body: (any Encodable & Sendable)? = nil,
                                       as type: T.Type = T.self) async throws -> T {
        var request = try await authorized(url(path), method: method, timeout: Self.requestTimeout(for: path))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await session.data(for: request, delegate: LearningRedirectBlocker())
        try check(response, data: data)
        // 204 No Content (e.g. DELETE) carries no body.
        if data.isEmpty, let empty = LearningEmptyResponse() as? T { return empty }
        do { return try Self.decoder.decode(T.self, from: data) } catch { throw LearningServiceError.invalidResponse }
    }

    /// Protected bytes (images, short clips). Thumbnails and detail images also land in a per-account disk cache.
    @concurrent
    func mediaData(_ path: String, cache: Bool = false) async throws -> Data {
        let file = cache ? LearningMediaCache.file(scope: scope, path: path) : nil
        if let file, let data = try? Data(contentsOf: file) {
            LearningMediaCache.touch(file)
            return data
        }
        try await LearningMediaGate.shared.acquire()
        defer { Task { await LearningMediaGate.shared.release() } }
        let request = try await authorized(url(path), timeout: 60)
        let (data, response) = try await mediaSession.data(for: request, delegate: LearningRedirectBlocker())
        try check(response, data: data)
        guard data.count <= 64 * 1_048_576 else { throw LearningServiceError.invalidResponse }
        if let file { try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        return data
    }

    /// Items by id, fetched in chunks of 60 (the server's cap), in the order given.
    @concurrent
    func items(ids: [String]) async throws -> [OnlineTimelineItem] {
        var found: [String: OnlineTimelineItem] = [:]
        var start = 0
        while start < ids.count {
            let chunk = ids[start..<min(start + 60, ids.count)]
            start += 60
            let page = try await get("api/online-timeline/items", query: [URLQueryItem(name: "ids", value: chunk.joined(separator: ","))],
                                     as: OnlineTimelineItems.self)
            for item in page.items { found[item.id] = item }
        }
        var seen = Set<String>()
        return ids.compactMap { id in seen.insert(id).inserted ? found[id] : nil }
    }

    /// Streams a protected original (video) with Range requests; the header stays on this asset only.
    func authorizedAsset(_ path: String) async throws -> AVURLAsset {
        let request = try await authorized(url(path))
        let headers = request.allHTTPHeaderFields ?? [:]
        return AVURLAsset(url: request.url!, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    }

    // MARK: Course upload

    /// The family service sits behind a proxy that caps each request (~100 MB), so a
    /// lesson goes up one file per request: the first creates the course and announces
    /// how many follow; the server composes only after all of them have arrived.
    @concurrent
    func createCourse(childID: String?, schoolDate: String, title: String, kind: LearningCourseKind,
                      language: String, note: String? = nil,
                      first: LearningUploadFile, totalFiles: Int) async throws -> LearningCourseDetailDTO {
        var fields = [("school_date", schoolDate), ("title", title), ("kind", kind.rawValue),
                      ("language", language), ("total_files", String(totalFiles))]
        if let childID { fields.insert(("child_id", childID), at: 0) }
        // Parent's "今天老师教了什么"; only sent when filled in.
        if let note, !note.isEmpty { fields.append(("note", note)) }
        return try await multipart("api/courses", fields: fields, fileField: "files", file: first)
    }

    @concurrent
    func addCourseFile(courseID: String, file: LearningUploadFile) async throws -> LearningCourseDetailDTO {
        try await multipart("api/courses/\(courseID)/files", fields: [], fileField: "file", file: file)
    }

    private func multipart(_ path: String, fields: [(String, String)], fileField: String,
                           file: LearningUploadFile) async throws -> LearningCourseDetailDTO {
        let boundary = "bubu-\(UUID().uuidString)"
        let body = FileManager.default.temporaryDirectory.appendingPathComponent("bubu-course-\(UUID().uuidString).multipart")
        defer { try? FileManager.default.removeItem(at: body) }
        guard FileManager.default.createFile(atPath: body.path, contents: nil) else { throw LearningServiceError.invalidResponse }
        let handle = try FileHandle(forWritingTo: body)
        do {
            for (name, value) in fields {
                try handle.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
            }
            let safeName = file.fileName.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
            try handle.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(safeName)\"\r\nContent-Type: \(file.mimeType)\r\n\r\n".utf8))
            let input = try FileHandle(forReadingFrom: file.url)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                try handle.write(contentsOf: chunk)
            }
            try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        var request = try await authorized(url(path), method: "POST", timeout: 900)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.upload(for: request, fromFile: body, delegate: LearningRedirectBlocker())
        try check(response, data: data)
        do { return try Self.decoder.decode(LearningCourseDetailDTO.self, from: data) } catch { throw LearningServiceError.invalidResponse }
    }
}

nonisolated enum BubuLearningClientError: LocalizedError, Equatable {
    case conflict
    case message(String)
    /// 503: the server is up but can't read the library right now; carries its `detail`.
    case unavailable(String?)
    var errorDescription: String? {
        switch self {
        case .conflict: "内容刚刚更新过，请刷新后重新核对。"
        case .message(let text): text
        case .unavailable(let detail): detail ?? LearningErrorKind.serviceUnavailableText
        }
    }
}

/// What went wrong, in the terms a parent can act on.
nonisolated enum LearningErrorKind: Equatable, Sendable {
    case cancelled
    /// The phone itself has no network.
    case offline
    /// Network is fine but the home server doesn't answer (timeout, refused, proxy 502/504).
    case serverUnreachable
    case unauthorized
    /// 503 with the server's own explanation.
    case serviceUnavailable(String?)
    case other

    static let offlineText = "手机现在没有网络，连上网络后再试。"
    static let serverUnreachableText = "家里的服务器没有回应，可能需要在 Mac mini 上处理一下，请稍后重试。"
    static let unauthorizedText = "家里服务器的登录过期了，请到 设置 → 高级 → 服务器与 AI 配置 重新连接。"
    static let serviceUnavailableText = "家里的服务器暂时读不到素材库，请稍后重试。"
    static let forbiddenText = "这个账号没有这项权限（需要家长账号）。"
    static let tooFrequentText = "操作有点太频繁了，稍等一会儿再试。"

    init(_ error: Error) {
        if isCancellation(error) { self = .cancelled; return }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                self = .offline
            // -1005 is almost always the tunnel or the server dropping the connection, not the phone's network.
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost:
                self = .serverUnreachable
            default:
                self = .other
            }
            return
        }
        switch error {
        case BubuLearningClientError.unavailable(let detail): self = .serviceUnavailable(detail)
        case LearningServiceError.unauthorized: self = .unauthorized
        case LearningServiceError.server(let code) where code == 502 || code == 504: self = .serverUnreachable
        case APIError.unauthorized, APIError.forbidden, APIError.notConfigured: self = .unauthorized
        case APIError.network: self = .serverUnreachable
        default: self = .other
        }
    }
}

/// Both Swift task cancellation and a cancelled URLSession task mean "nobody is waiting" — never show an error.
nonisolated func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let error = error as? URLError, error.code == .cancelled { return true }
    return false
}

nonisolated struct LearningEmptyResponse: Decodable, Sendable {}

nonisolated func learningErrorText(_ error: Error, fallback: String = "暂时连接不到家庭服务，请检查网络后重试。") -> String {
    switch LearningErrorKind(error) {
    case .offline: return LearningErrorKind.offlineText
    case .serverUnreachable: return LearningErrorKind.serverUnreachableText
    case .unauthorized: return LearningErrorKind.unauthorizedText
    case .serviceUnavailable(let detail): return detail ?? LearningErrorKind.serviceUnavailableText
    case .cancelled: return fallback
    case .other: break
    }
    if let error = error as? BubuLearningClientError { return error.errorDescription ?? fallback }
    if let error = error as? LearningServiceError { return error.errorDescription ?? fallback }
    if error is APIError { return LearningErrorKind.unauthorizedText }
    return fallback
}

/// Any error, in a sentence a parent can read. System errors come back in English or as codes
/// ("NSCocoaErrorDomain error 640"), so they are mapped or replaced by `fallback`; the raw error goes to the log only.
nonisolated func bubuErrorText(_ error: Error, fallback: String) -> String {
    #if DEBUG
    print("[bubuErrorText]", error)
    #endif
    if let error = error as? CocoaError {
        switch error.code {
        case .fileWriteOutOfSpace: return "手机存储空间不够了，清理一些空间后再试。"
        case .fileNoSuchFile, .fileReadNoSuchFile: return "文件找不到了，可能已经被移走或删除。"
        case .fileWriteNoPermission, .fileReadNoPermission: return "没有权限读写这个文件，请重新选择后再试。"
        case .fileWriteVolumeReadOnly: return "这个位置只能读不能写，请换个位置保存。"
        case .fileReadCorruptFile: return "文件好像损坏了，打不开。"
        default: return fallback
        }
    }
    if error is URLError || error is LearningServiceError || error is BubuLearningClientError || error is APIError {
        return learningErrorText(error, fallback: fallback)
    }
    // Our own errors are already written in Chinese; anything else is the system talking.
    if let text = (error as? LocalizedError)?.errorDescription, BubuLearningClient.containsChinese(text) { return text }
    return fallback
}

/// Caps concurrent image/clip downloads; waiting callers that get cancelled (cell scrolled away) leave the queue.
actor LearningMediaGate {
    static let shared = LearningMediaGate(limit: 6)
    private let limit: Int
    private var running = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async throws {
        try Task.checkCancellation()
        if running < limit { running += 1; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                enqueue(id, continuation)
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func enqueue(_ id: UUID, _ continuation: CheckedContinuation<Void, Error>) {
        // Cancelled before we got here: the onCancel hop would find nothing to remove.
        if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
        waiters.append((id, continuation))
    }

    func release() {
        if waiters.isEmpty { running = max(0, running - 1); return }
        waiters.removeFirst().continuation.resume()
    }

    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

/// Endpoints are canonical; refusing redirects keeps the bearer on this origin and route.
private nonisolated final class LearningRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Per-account image cache in Caches. Keys include the content revision in the path, so edits leave
/// orphans behind; the whole folder is trimmed least-recently-used to `limitBytes` once per launch.
nonisolated enum LearningMediaCache {
    static let limitBytes = 200 * 1_048_576
    private static let state = Mutex<(folders: Set<String>, pruned: Bool)>(([], false))

    static var root: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BubuLearningMedia", isDirectory: true)
    }

    static func file(scope: String, path: String) -> URL? {
        guard let root else { return nil }
        let folder = root.appendingPathComponent(hash(scope).prefix(16).description, isDirectory: true)
        // One mkdir per folder per launch instead of one per cell.
        let (create, prune) = state.withLock { state -> (Bool, Bool) in
            let create = state.folders.insert(folder.path).inserted
            let prune = !state.pruned
            state.pruned = true
            return (create, prune)
        }
        if create { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        if prune { Task.detached(priority: .background) { Self.prune(root, limit: limitBytes) } }
        return folder.appendingPathComponent(hash(path) + ".bin")
    }

    /// Marks a hit as recently used (the modification date is the LRU clock).
    static func touch(_ file: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
    }

    /// Deletes the least recently used files until the folder fits in `limit` bytes. Returns the bytes kept.
    @discardableResult
    static func prune(_ folder: URL, limit: Int) -> Int {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return 0 }
        var files: [(url: URL, date: Date, size: Int)] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            files.append((url, values.contentModificationDate ?? .distantPast,
                          values.totalFileAllocatedSize ?? values.fileSize ?? 0))
        }
        var total = files.reduce(0) { $0 + $1.size }
        for file in files.sorted(by: { $0.date < $1.date }) where total > limit {
            if (try? FileManager.default.removeItem(at: file.url)) != nil { total -= file.size }
        }
        return total
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Decoded (already downsampled) images shared across the timeline grid and detail pages, bounded by bytes.
nonisolated final class LearningImageMemory: @unchecked Sendable {
    static let shared = LearningImageMemory()
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 100 * 1_048_576
        return cache
    }()
    func image(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
    }

    static func cost(of image: UIImage) -> Int {
        if let cgImage = image.cgImage { return cgImage.bytesPerRow * cgImage.height }
        return Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }
}

/// Decode at (about) the displayed pixel size instead of the full image.
nonisolated enum LearningImageDecoder {
    /// Pixel buckets keep the cache small and let one decode serve similar-sized cells.
    static let buckets: [Int] = [256, 512, 1024, 2048]

    /// Nearest bucket, leaning small: up to 1.3× over a bucket still uses it (a 370pt card at 3× is 1110px
    /// and decodes at 1024 — about 3 MB — instead of jumping to 2048 and decoding the whole 1600px source).
    static func bucket(forPixels pixels: CGFloat) -> Int {
        guard let index = buckets.firstIndex(where: { CGFloat($0) >= pixels }) else { return buckets[buckets.count - 1] }
        if index > 0, pixels <= CGFloat(buckets[index - 1]) * 1.3 { return buckets[index - 1] }
        return buckets[index]
    }

    static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
