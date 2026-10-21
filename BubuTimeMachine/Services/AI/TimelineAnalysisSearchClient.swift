import Foundation

nonisolated struct TimelineAnalysisSearchResponse: Decodable, Sendable {
    let items: [Hit]
    let total: Int
    let hasMore: Bool

    nonisolated struct Hit: Decodable, Sendable {
        let entryLocalID: String
        let mediaID: String
        let mediaLocalID: String?
        let capturedAt: String?
        let description: String?
        let tags: [String]?
        let source: String?
        let identityStatus: String?
        let matchReason: String?
        enum CodingKeys: String, CodingKey {
            case entryLocalID = "entry_local_id", mediaID = "media_id", mediaLocalID = "media_local_id"
            case capturedAt = "captured_at", description, tags, source, identityStatus = "identity_status", matchReason = "match_reason"
        }
    }
    enum CodingKeys: String, CodingKey { case items, total, hasMore = "has_more" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([Hit].self, forKey: .items)
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? items.count
        hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }
    var confirmedHits: [Hit] {
        Array(items.prefix(50)).filter { $0.identityStatus == "confirmed" && UUID(uuidString: $0.entryLocalID) != nil }
    }
    func missingEntryCount(availableIDs: Set<UUID>) -> Int {
        Set(confirmedHits.compactMap { UUID(uuidString: $0.entryLocalID) }).subtracting(availableIDs).count
    }
}

nonisolated struct TimelineAnalysisSearchClient: Sendable {
    let baseURL: URL
    var session = URLSession(configuration: .ephemeral)

    static func makeRequest(baseURL: URL, query: String, filters: TimelineFilters,
                            sort: TimelineSortMode, token: String, calendar: Calendar = .current) throws -> URLRequest {
        guard !token.isEmpty else { throw LearningServiceError.unauthorized }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              filters.kind != .audio else { throw LearningServiceError.invalidAddress }
        let root = LearningServiceRoutes(baseURL: baseURL).root.appendingPathComponent("api/timeline/search")
        var parts = URLComponents(url: root, resolvingAgainstBaseURL: false)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        parts.queryItems = [
            URLQueryItem(name: "query", value: query.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "kind", value: filters.kind.rawValue),
            URLQueryItem(name: "order", value: sort.ascending ? "asc" : "desc"),
            URLQueryItem(name: "limit", value: "50")
        ]
        if let start = filters.start { parts.queryItems?.append(URLQueryItem(name: "start", value: formatter.string(from: start))) }
        if let end = filters.end { parts.queryItems?.append(URLQueryItem(name: "end", value: formatter.string(from: end))) }
        guard let url = parts.url else { throw LearningServiceError.invalidAddress }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    @concurrent
    func search(query: String, filters: TimelineFilters, sort: TimelineSortMode, token: String) async throws -> TimelineAnalysisSearchResponse {
        let request = try Self.makeRequest(baseURL: baseURL, query: query, filters: filters, sort: sort, token: token)
        let (data, response) = try await session.data(for: request, delegate: TimelineNoRedirect())
        guard let http = response as? HTTPURLResponse, let url = http.url,
              LearningServiceRoutes(baseURL: baseURL).allowsNavigation(to: url) else { throw LearningServiceError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw LearningServiceError.unauthorized
        default: throw LearningServiceError.server(http.statusCode)
        }
        guard data.count <= 4 * 1_048_576 else { throw LearningServiceError.invalidResponse }
        do { return try JSONDecoder().decode(TimelineAnalysisSearchResponse.self, from: data) }
        catch { throw LearningServiceError.invalidResponse }
    }
}

private nonisolated final class TimelineNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
