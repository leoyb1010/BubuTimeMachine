import Foundation

// MARK: - API 客户端协议（PocketBaseClient 实现）
/// 接口先行：UI 与同步层只依赖此协议，先 Mock 后接真实 PocketBase。
protocol APIClient: Sendable {
    func authenticate(role: String) async throws -> AuthToken
    func createEntry(_ dto: EntryDTO) async throws -> EntryDTO
    func fetchEntries(since: Date?) async throws -> [EntryDTO]
    /// 分片上传：返回可观察进度的异步流。
    func uploadMedia(_ file: MediaUploadRequest) -> AsyncThrowingStream<UploadEvent, Error>
    func subscribeRealtime() -> AsyncStream<RealtimeEvent>
    /// 连接测试：设置页「连接测试」按钮调用。
    func ping() async throws -> Bool
}

// MARK: - 客户端错误
enum APIError: LocalizedError, Sendable {
    case notConfigured
    case unauthorized
    case network(String)
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "还没有连接到家里的服务器"
        case .unauthorized:  return "身份过期了，请重新进入"
        case .network(let m): return "网络不太通：\(m)"
        case .server(let code, let m): return "服务器开小差了（\(code)）：\(m)"
        }
    }
}
