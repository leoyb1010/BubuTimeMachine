import Foundation

nonisolated enum LearningServiceError: LocalizedError, Equatable {
    case invalidAddress, unauthorized, unavailableMedia, invalidResponse, server(Int)
    var errorDescription: String? {
        switch self {
        case .invalidAddress: "课程地址不可用，请检查家庭服务设置。"
        case .unauthorized: "家庭身份已过期或没有访问权限，请重新连接后再试。"
        case .unavailableMedia: "这份素材已不可访问，请先刷新家庭记录。"
        case .invalidResponse: "解析服务返回的内容暂时无法读取，请稍后重试。"
        case .server: "第二大脑暂时没有响应，请稍后重试。"
        }
    }
    var invalidatesCache: Bool { self == .unauthorized || self == .unavailableMedia }
}

/// Caller supplies the trusted ServerConfig.aiBaseURL after checking the feature’s access policy.
nonisolated struct LearningServiceRoutes: Sendable {
    let root: URL
    init(baseURL: URL) {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.query = nil
        components.fragment = nil
        root = components.url!.appendingPathComponent("learning")
    }

    func pageRequest(day: String, childID: String?, token: String) throws -> URLRequest {
        guard !token.isEmpty else { throw LearningServiceError.unauthorized }
        var components = URLComponents(url: root, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "date", value: day)]
        if let childID, !childID.isEmpty { components.queryItems?.append(URLQueryItem(name: "child", value: childID)) }
        guard let url = components.url else { throw LearningServiceError.invalidAddress }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    func analysisURL(mediaID: String, retry: Bool = false) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !mediaID.isEmpty, mediaID.unicodeScalars.allSatisfy(allowed.contains) else {
            throw LearningServiceError.invalidAddress
        }
        let url = root.appendingPathComponent("api/media").appendingPathComponent(mediaID).appendingPathComponent("analysis")
        return retry ? url.appendingPathComponent("retry") : url
    }

    func allowsNavigation(to url: URL) -> Bool {
        guard url.scheme?.lowercased() == root.scheme?.lowercased(),
              url.host?.lowercased() == root.host?.lowercased(),
              effectivePort(url) == effectivePort(root), url.user == nil, url.password == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.percentEncodedPath.removingPercentEncoding,
              !path.contains("\\"), !path.contains("%"),
              !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return false }
        return path == root.path || path.hasPrefix(root.path + "/")
    }

    private func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : url.scheme?.lowercased() == "http" ? 80 : nil)
    }
}
