import Foundation
import AVFoundation
import CryptoKit
import UIKit

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
nonisolated struct OnlineTimelinePerson: Decodable, Sendable, Hashable { let name: String; let count: Int }
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

nonisolated enum BubuLearningDates {
    static func parseISO(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func day(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
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

    /// One ephemeral session for the whole app; clients are cheap values rebuilt with views.
    static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }()

    init(baseURL: URL, scope: String, token: @escaping @Sendable () async throws -> String,
         session: URLSession = BubuLearningClient.sharedSession) {
        routes = LearningServiceRoutes(baseURL: baseURL)
        self.scope = scope
        self.token = token
        self.session = session
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
        case 401, 403: throw LearningServiceError.unauthorized
        case 404: throw LearningServiceError.unavailableMedia
        case 409: throw BubuLearningClientError.conflict
        case 413: throw BubuLearningClientError.message("文件太大了，单个文件请小于 256 MB。")
        case 422: throw BubuLearningClientError.message(Self.detail(data) ?? "内容没有通过检查，请核对后重试。")
        default: throw LearningServiceError.server(http.statusCode)
        }
    }

    private static func detail(_ data: Data?) -> String? {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["detail"] as? String, !text.isEmpty else { return nil }
        return text
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
        var request = try await authorized(url(path), method: method)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await session.data(for: request, delegate: LearningRedirectBlocker())
        try check(response, data: data)
        do { return try Self.decoder.decode(T.self, from: data) } catch { throw LearningServiceError.invalidResponse }
    }

    /// Protected bytes (images, short clips). Thumbnails also land in a per-account disk cache.
    @concurrent
    func mediaData(_ path: String, cache: Bool = false) async throws -> Data {
        let file = cache ? LearningMediaCache.file(scope: scope, path: path) : nil
        if let file, let data = try? Data(contentsOf: file) { return data }
        let request = try await authorized(url(path), timeout: 60)
        let (data, response) = try await session.data(for: request, delegate: LearningRedirectBlocker())
        try check(response, data: nil)
        guard data.count <= 64 * 1_048_576 else { throw LearningServiceError.invalidResponse }
        if let file { try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        return data
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
                      language: String, first: LearningUploadFile, totalFiles: Int) async throws -> LearningCourseDetailDTO {
        var fields = [("school_date", schoolDate), ("title", title), ("kind", kind.rawValue),
                      ("language", language), ("total_files", String(totalFiles))]
        if let childID { fields.insert(("child_id", childID), at: 0) }
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
    var errorDescription: String? {
        switch self {
        case .conflict: "内容刚刚更新过，请刷新后重新核对。"
        case .message(let text): text
        }
    }
}

nonisolated func learningErrorText(_ error: Error, fallback: String = "暂时连接不到家庭服务，请检查网络后重试。") -> String {
    if let error = error as? BubuLearningClientError { return error.errorDescription ?? fallback }
    if let error = error as? LearningServiceError { return error.errorDescription ?? fallback }
    if error is APIError { return LearningServiceError.unauthorized.errorDescription ?? fallback }
    return fallback
}

/// Endpoints are canonical; refusing redirects keeps the bearer on this origin and route.
private nonisolated final class LearningRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Per-account thumbnail cache in Caches. Keys include the content revision in the path.
nonisolated enum LearningMediaCache {
    static func file(scope: String, path: String) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = caches.appendingPathComponent("BubuLearningMedia", isDirectory: true)
            .appendingPathComponent(hash(scope).prefix(16).description, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(hash(path) + ".bin")
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Decoded images shared across the timeline grid and detail pages.
nonisolated final class LearningImageMemory: @unchecked Sendable {
    static let shared = LearningImageMemory()
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 600
        return cache
    }()
    func image(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func store(_ image: UIImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
}
