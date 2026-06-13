import Foundation

// MARK: - 账号服务（单家庭多账号）
/// 这是「我们一家自己用」的 App：所有账号同属一个家庭、共享同一个布布的数据（不做按账号隔离）。
/// 「独立账号」的价值是：每位家人有自己的登录身份（自动对应署名角色），而不是数据各看各的。
///
/// 注册用「家庭码」把关——只有知道家庭码的人才能在你的自托管服务器上建账号，挡住陌生人。
/// 家庭码校验放客户端即可（App 不公开 + 服务器仅家人知道，对自家场景足够）。
///
/// 服务器地址固定走 ServerConfig.defaultBaseURL；注册/登录成功后把邮箱密码写入 ServerConfig，
/// 同步层（PocketBaseClient）复用这套凭据，无需改动既有同步逻辑。
@MainActor
final class AccountService {
    /// 家庭码（只有家人知道）。如需更换，改这里发新版即可。
    static let familyCode = "BUBU-HOME"

    enum AccountError: LocalizedError {
        case wrongFamilyCode
        case emptyField
        case server(String)

        var errorDescription: String? {
            switch self {
            case .wrongFamilyCode: return "家庭码不对，问问家里人正确的家庭码"
            case .emptyField: return "请把邮箱和密码填完整"
            case .server(let m): return m
            }
        }
    }

    private var baseURL: URL { URL(string: ServerConfig.defaultBaseURL)! }

    /// 登录：校验邮箱密码，成功后把凭据写入 config 供同步层使用。
    func login(email: String, password: String, role: FamilyRole, config: ServerConfig) async throws {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty, !password.isEmpty else { throw AccountError.emptyField }
        _ = try await authWithPassword(identity: e, password: password)
        persist(email: e, password: password, role: role, config: config)
    }

    /// 注册：校验家庭码 → 在 PocketBase 建 users 记录 → 自动登录 → 写入凭据。
    func register(email: String, password: String, familyCode: String,
                  role: FamilyRole, config: ServerConfig) async throws {
        guard familyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                == Self.familyCode else { throw AccountError.wrongFamilyCode }
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty, password.count >= 6 else { throw AccountError.emptyField }

        // PocketBase users 创建：email + password + passwordConfirm。
        let url = baseURL.appendingPathComponent("api/collections/users/records")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": e, "password": password, "passwordConfirm": password,
            "name": role.displayName
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data, context: "注册")

        // 注册成功后立即登录拿 token 校验，并写入凭据。
        _ = try await authWithPassword(identity: e, password: password)
        persist(email: e, password: password, role: role, config: config)
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
    private func authWithPassword(identity: String, password: String) async throws -> String {
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
