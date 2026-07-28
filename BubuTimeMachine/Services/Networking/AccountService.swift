import Foundation

// MARK: - 账号服务（单家庭多账号）
/// 这是「我们一家自己用」的 App：所有账号同属一个家庭、共享同一个布布的数据（不做按账号隔离）。
/// 「独立账号」的价值是：每位家人有自己的登录身份（自动对应署名角色），而不是数据各看各的。
///
/// 服务端关闭公开注册：新账号由 PocketBase 超管创建，再在这里登录。
///
/// 登录成功后把邮箱密码写入 ServerConfig，同步层（PocketBaseClient）复用这套凭据。
@MainActor
final class AccountService {
    /// 用户名 → 固定家庭邮箱域。用户只感知「用户名」，避免邮箱难记/填错导致登录不一致。
    /// 例：用户名 yuanbo → 实际账号 yuanbo@bubu.family。注册和登录都用同一拼接结果，绝不会对不上。
    private static let emailDomain = "bubu.family"
    /// 登录返回的用户记录 id，改密码时要用（PATCH /api/collections/users/records/{id}）。
    private static let recordIdKey = "bubu.account.recordId"

    static func emailFor(username: String) -> String {
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // 用户若直接填了完整邮箱也兼容。
        return u.contains("@") ? u : "\(u)@\(emailDomain)"
    }

    /// 从完整邮箱还原出用户名（账号页展示用）。
    static func usernameFrom(email: String) -> String {
        guard let at = email.firstIndex(of: "@") else { return email }
        return String(email[email.startIndex..<at])
    }

    static var storedRecordId: String? {
        UserDefaults.standard.string(forKey: recordIdKey)
    }

    enum AccountError: LocalizedError {
        case missingServer
        case missingUsername
        case weakPassword
        case notLoggedIn
        case passwordMismatch
        case samePassword
        case registrationClosed
        case server(String)

        var errorDescription: String? {
            switch self {
            case .missingServer: return "还没填服务器地址，先到「服务器与 AI 配置」里填上。"
            case .missingUsername: return "请填写用户名。"
            case .weakPassword: return "密码至少 8 位。"
            case .notLoggedIn: return "请先登录，再修改密码。"
            case .passwordMismatch: return "两次输入的新密码不一样。"
            case .samePassword: return "新密码和原密码相同，换一个吧。"
            case .registrationClosed: return "家里服务器已关闭公开注册。请先在 PocketBase 后台创建账号，再用「登录」进入。"
            case .server(let m): return m
            }
        }
    }

    /// 登录：用户名 → 拼邮箱 → 校验密码，成功后写入凭据供同步层使用。
    func login(username: String, password: String, role: FamilyRole, config: ServerConfig) async throws {
        // 三种缺失分别报错：合并成一句「请填服务器地址、用户名和至少 8 位密码」时用户无从下手。
        guard let baseURL = config.baseURL else { throw AccountError.missingServer }
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AccountError.missingUsername
        }
        guard password.count >= 8 else { throw AccountError.weakPassword }
        let e = Self.emailFor(username: username)
        let auth = try await authWithPassword(identity: e, password: password, baseURL: baseURL)
        UserDefaults.standard.set(auth.recordId, forKey: Self.recordIdKey)
        persist(email: e, password: password, role: role, config: config)
    }

    /// 修改密码：PocketBase 的 auth 集合支持本人 PATCH 自己的记录（oldPassword + password + passwordConfirm）。
    /// 服务端 updateRule 已是 `id = @request.auth.id`，无需任何服务端改动。
    ///
    /// 关键收尾：改成功后必须把新密码写回 ServerConfig（→ 钥匙串）并让调用方重建 API 客户端，
    /// 否则同步层握着的仍是旧密码，token 一过期就再也登不上。
    func changePassword(old: String, new: String, confirm: String, config: ServerConfig) async throws {
        guard let baseURL = config.baseURL else { throw AccountError.missingServer }
        guard config.hasServerCredentials, let recordId = Self.storedRecordId else {
            throw AccountError.notLoggedIn
        }
        guard new.count >= 8 else { throw AccountError.weakPassword }
        guard new == confirm else { throw AccountError.passwordMismatch }
        guard new != old else { throw AccountError.samePassword }

        // 先用旧密码换一次 token：既验证旧密码正确，又拿到 PATCH 需要的授权。
        let auth = try await authWithPassword(identity: config.accountEmail, password: old, baseURL: baseURL)

        let url = baseURL.appendingPathComponent("api/collections/users/records/\(recordId)")
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "oldPassword": old, "password": new, "passwordConfirm": confirm,
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data, context: "修改密码")

        // 落新密码到钥匙串。调用方随后 reloadServices 让同步层用上新凭据。
        config.accountPassword = new
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
        UserDefaults.standard.removeObject(forKey: Self.recordIdKey)
    }

    // MARK: 私有

    private struct AuthResult {
        let token: String
        let recordId: String
    }

    private func persist(email: String, password: String, role: FamilyRole, config: ServerConfig) {
        config.accountEmail = email
        config.accountPassword = password   // didSet 会写入 Keychain
        config.currentRole = role
    }

    @discardableResult
    private func authWithPassword(identity: String, password: String, baseURL: URL) async throws -> AuthResult {
        let url = baseURL.appendingPathComponent("api/collections/users/auth-with-password")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
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
        let recordId = (obj["record"] as? [String: Any])?["id"] as? String ?? ""
        return AuthResult(token: token, recordId: recordId)
    }

    /// 网络/服务端错误统一转中文人话：直接抛 localizedDescription 会把
    /// "The request timed out." 这类英文原文丢到中文界面上。
    static func friendlyMessage(_ error: Error) -> String {
        if let accountError = error as? AccountError {
            return accountError.errorDescription ?? "出错了，稍后再试"
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut: return "服务器没有响应，检查一下地址和网络"
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                return "连不上这个服务器地址，确认地址填对了、服务器开着"
            case NSURLErrorNotConnectedToInternet: return "手机现在没有网络"
            case NSURLErrorNetworkConnectionLost: return "网络中断了，请重试"
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
                return "安全连接建立失败，检查服务器证书"
            default: return "网络出错了（\(ns.code)），稍后再试"
            }
        }
        return error.localizedDescription
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
            if http.statusCode == 400 {
                switch context {
                case "注册": msg = "这个邮箱可能已注册，换一个或直接登录"
                case "登录": msg = "用户名或密码不对"
                case "修改密码": msg = "原密码不对，或新密码不符合要求（至少 8 位）"
                default: break
                }
            }
            throw AccountError.server(msg)
        }
    }
}
