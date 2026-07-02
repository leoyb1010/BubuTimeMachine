import Foundation

// MARK: - 账号服务（单家庭多账号）
/// 这是「我们一家自己用」的 App：所有账号同属一个家庭、共享同一个布布的数据（不做按账号隔离）。
/// 「独立账号」的价值是：每位家人有自己的登录身份（自动对应署名角色），而不是数据各看各的。
///
/// 服务端关闭公开注册：新账号由 PocketBase 超管创建，再在这里登录。
///
/// 服务器地址固定走 ServerConfig.defaultBaseURL；登录成功后把邮箱密码写入 ServerConfig，
/// 同步层（PocketBaseClient）复用这套凭据，无需改动既有同步逻辑。
@MainActor
final class AccountService {
    /// 用户名 → 固定家庭邮箱域。用户只感知「用户名」，避免邮箱难记/填错导致登录不一致。
    /// 例：用户名 yuanbo → 实际账号 yuanbo@bubu.family。注册和登录都用同一拼接结果，绝不会对不上。
    private static let emailDomain = "bubu.family"

    static func emailFor(username: String) -> String {
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // 用户若直接填了完整邮箱也兼容。
        return u.contains("@") ? u : "\(u)@\(emailDomain)"
    }

    enum AccountError: LocalizedError {
        case emptyField
        case registrationClosed
        case server(String)

        var errorDescription: String? {
            switch self {
            case .emptyField: return "请先填写服务器地址、用户名和至少 8 位密码"
            case .registrationClosed: return "家里服务器已关闭公开注册。请先在 PocketBase 后台创建账号，再用「登录」进入。"
            case .server(let m): return m
            }
        }
    }

    /// 登录：用户名 → 拼邮箱 → 校验密码，成功后写入凭据供同步层使用。
    func login(username: String, password: String, role: FamilyRole, config: ServerConfig) async throws {
        let e = Self.emailFor(username: username)
        guard let baseURL = config.baseURL,
              !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              password.count >= 8 else {
            throw AccountError.emptyField
        }
        _ = try await authWithPassword(identity: e, password: password, baseURL: baseURL)
        persist(email: e, password: password, role: role, config: config)
    }

    /// 公开注册已关闭：新账号由 PocketBase 超管创建。
    func register(username: String, password: String, familyCode: String,
                  role: FamilyRole, config: ServerConfig) async throws {
        throw AccountError.registrationClosed
    }

    /// 登出：清掉本地凭据（数据仍在本地，连不上服务器，离线可用）。
    func logout(config: ServerConfig) {
        config.accountEmail = ""
        config.accountPassword = ""
    }

    // MARK: 私有

    private func persist(email: String, password: String, role: FamilyRole, config: ServerConfig) {
        config.accountEmail = email
        config.accountPassword = password   // didSet 会写入 Keychain
        config.currentRole = role
    }

    @discardableResult
    private func authWithPassword(identity: String, password: String, baseURL: URL) async throws -> String {
        let url = baseURL.appendingPathComponent("api/collections/users/auth-with-password")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "identity": identity, "password": password,
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data, context: "登录")
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["token"] as? String, !token.isEmpty else {
            throw AccountError.server("登录响应异常")
        }
        return token
    }

    private static func check(_ resp: URLResponse, _ data: Data, context: String) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            // PocketBase 错误体常含 message，尽量给人话。
            var msg = "\(context)失败（\(http.statusCode)）"
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let m = obj["message"] as? String, !m.isEmpty {
                msg = m
            }
            if http.statusCode == 400 && context == "注册" {
                msg = "这个邮箱可能已注册，换一个或直接登录"
            }
            throw AccountError.server(msg)
        }
    }
}
