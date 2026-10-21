import Foundation

nonisolated struct MediaAnalysisClient: Sendable {
    private let routes: LearningServiceRoutes
    private let session: URLSession
    init(baseURL: URL, session: URLSession = URLSession(configuration: .ephemeral)) {
        routes = LearningServiceRoutes(baseURL: baseURL)
        self.session = session
    }

    func fetch(mediaID: String, token: String) async throws -> MediaAnalysisDTO {
        try await request(mediaID: mediaID, token: token, retry: false)
    }
    func retry(mediaID: String, token: String) async throws -> MediaAnalysisDTO {
        try await request(mediaID: mediaID, token: token, retry: true)
    }

    @concurrent
    private func request(mediaID: String, token: String, retry: Bool) async throws -> MediaAnalysisDTO {
        guard !token.isEmpty else { throw LearningServiceError.unauthorized }
        let url = try routes.analysisURL(mediaID: mediaID, retry: retry)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpShouldHandleCookies = false // Native calls use this account's bearer only, never a previous Web session.
        request.httpMethod = retry ? "POST" : "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if retry {
            request.setValue("1", forHTTPHeaderField: "X-Bubu-Learning")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
        }
        let (data, response) = try await session.data(for: request, delegate: LearningNoRedirect())
        guard let http = response as? HTTPURLResponse,
              let responseURL = http.url, routes.allowsNavigation(to: responseURL) else {
            throw LearningServiceError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw LearningServiceError.unauthorized
        case 404: throw LearningServiceError.unavailableMedia
        default: throw LearningServiceError.server(http.statusCode)
        }
        guard data.count <= 4 * 1_048_576 else { throw LearningServiceError.invalidResponse }
        var dto: MediaAnalysisDTO
        do { dto = try JSONDecoder().decode(MediaAnalysisDTO.self, from: data) }
        catch { throw LearningServiceError.invalidResponse }
        guard dto.mediaID.isEmpty || dto.mediaID == mediaID else { throw LearningServiceError.invalidResponse }
        if dto.mediaID.isEmpty { dto.mediaID = mediaID }
        return dto
    }
}

/// API endpoints are canonical. Refusing redirects prevents a bearer from reaching another route or origin.
private nonisolated final class LearningNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
