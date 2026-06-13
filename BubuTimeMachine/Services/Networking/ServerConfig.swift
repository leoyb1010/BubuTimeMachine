import Foundation
import Observation

// MARK: - 服务器配置
/// 设置页可改 Base URL；存 @AppStorage（URL）+ Keychain（token，后续接入）。
/// App 启动读取，决定使用 Mock 还是真实 PocketBaseClient。
@Observable
final class ServerConfig {
    /// 服务器基础地址，例如默认 Cloudflare 公网地址。
    var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: Self.baseURLKey) }
    }

    /// 当前家庭身份（爸爸/妈妈/姥姥），用于署名与多视角。
    var currentRoleRaw: String {
        didSet {
            UserDefaults.standard.set(currentRoleRaw, forKey: Self.roleKey)
            // 镜像到 App Group，供 Intent/Widget 读取当前署名身份。
            SharedDefaults.currentRole = FamilyRole(rawValue: currentRoleRaw) ?? .mama
        }
    }

    var currentRole: FamilyRole {
        get { FamilyRole(rawValue: currentRoleRaw) ?? .mama }
        set { currentRoleRaw = newValue.rawValue }
    }

    /// 孩子的名字，用于 AI 第一人称改写等场景。
    var childName: String {
        didSet {
            UserDefaults.standard.set(childName, forKey: Self.childNameKey)
            SharedDefaults.childName = childName
        }
    }

    /// 家庭共享登录账户（PocketBase users）。
    var accountEmail: String {
        didSet { UserDefaults.standard.set(accountEmail, forKey: Self.emailKey) }
    }
    var accountPassword: String {
        didSet {
            if accountPassword.isEmpty { KeychainStore.delete(Self.passwordKey) }
            else { KeychainStore.set(accountPassword, for: Self.passwordKey) }
        }
    }

    /// AI 服务（FastAPI）地址。默认空：必须用户自己填，绝不默认把数据发到任何外部服务器。
    var aiBaseURLString: String {
        didSet { UserDefaults.standard.set(aiBaseURLString, forKey: Self.aiURLKey) }
    }
    /// AI 服务访问密钥（与服务端 .env 的 AI_API_KEY 一致），存 Keychain。
    var aiAPIKey: String {
        didSet {
            if aiAPIKey.isEmpty { KeychainStore.delete(Self.aiKeyKey) }
            else { KeychainStore.set(aiAPIKey, for: Self.aiKeyKey) }
        }
    }
    /// 是否启用真实 AI（关闭则用 Mock，离线可玩）。
    var aiEnabled: Bool {
        didSet { UserDefaults.standard.set(aiEnabled, forKey: Self.aiEnabledKey) }
    }
    /// 是否开启"那年今日"每日提醒。
    var dailyReminderEnabled: Bool {
        didSet { UserDefaults.standard.set(dailyReminderEnabled, forKey: Self.reminderKey) }
    }

    var baseURL: URL? {
        guard !baseURLString.isEmpty else { return nil }
        return URL(string: baseURLString)
    }

    var aiBaseURL: URL? {
        guard !aiBaseURLString.isEmpty else { return nil }
        return URL(string: aiBaseURLString)
    }

    var hasServerCredentials: Bool {
        !accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !accountPassword.isEmpty
    }

    /// 是否已配置真实服务器；未配置时全程走 Mock，仍可离线使用。
    var isConfigured: Bool { baseURL != nil && hasServerCredentials }

    /// 是否可用真实 AI。
    var isAIConfigured: Bool {
        aiEnabled && aiBaseURL != nil && !aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static let baseURLKey = "bubu.server.baseURL"
    private static let roleKey = "bubu.server.role"
    private static let childNameKey = "bubu.child.name"
    private static let emailKey = "bubu.server.email"
    private static let passwordKey = "bubu.server.password"
    private static let aiURLKey = "bubu.ai.baseURL"
    private static let aiKeyKey = "bubu.ai.apiKey"
    private static let aiEnabledKey = "bubu.ai.enabled"
    private static let reminderKey = "bubu.reminder.enabled"

    /// 默认指向家庭自托管服务；真实用户是家庭内测版本，首装即可同步/使用 AI。
    static let defaultBaseURL = "https://bubu-api.leoyuan.top"
    static let defaultAIBaseURL = "https://bubu-ai.leoyuan.top"
    /// 可用 Info.plist 或调试环境注入，避免把真实密钥提交到 GitHub。
    private static var defaultAIAPIKey: String {
        let infoValue = Bundle.main.object(forInfoDictionaryKey: "BUBU_DEFAULT_AI_API_KEY") as? String
        let envValue = ProcessInfo.processInfo.environment["BUBU_DEFAULT_AI_API_KEY"]
        return [infoValue, envValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("$(") } ?? ""
    }
    /// 设置页占位示例。
    static let baseURLPlaceholder = "https://你的服务器地址:8090"
    static let aiBaseURLPlaceholder = "https://你的AI服务地址:8000"

    init() {
        self.baseURLString = UserDefaults.standard.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURL
        self.currentRoleRaw = UserDefaults.standard.string(forKey: Self.roleKey) ?? FamilyRole.mama.rawValue
        self.childName = UserDefaults.standard.string(forKey: Self.childNameKey) ?? "布布"
        self.accountEmail = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""
        let legacyPassword = UserDefaults.standard.string(forKey: Self.passwordKey)
        if let legacyPassword, !legacyPassword.isEmpty {
            KeychainStore.set(legacyPassword, for: Self.passwordKey)
            UserDefaults.standard.removeObject(forKey: Self.passwordKey)
        }
        self.accountPassword = KeychainStore.string(for: Self.passwordKey) ?? legacyPassword ?? ""
        self.aiBaseURLString = UserDefaults.standard.string(forKey: Self.aiURLKey) ?? Self.defaultAIBaseURL
        let storedAIKey = KeychainStore.string(for: Self.aiKeyKey) ?? ""
        let initialAIKey = storedAIKey.isEmpty ? Self.defaultAIAPIKey : storedAIKey
        self.aiAPIKey = initialAIKey
        if storedAIKey.isEmpty, !initialAIKey.isEmpty {
            KeychainStore.set(initialAIKey, for: Self.aiKeyKey)
        }
        // 家庭内测默认启用真实 AI；如果用户手动关闭过，则尊重用户设置。
        self.aiEnabled = UserDefaults.standard.object(forKey: Self.aiEnabledKey) as? Bool ?? true
        self.dailyReminderEnabled = UserDefaults.standard.bool(forKey: Self.reminderKey)
        // didSet 不在 init 内触发，显式把身份/名字镜像到 App Group，供 Intent/Widget 首次即可读。
        SharedDefaults.mirror(role: FamilyRole(rawValue: currentRoleRaw) ?? .mama, childName: childName)
    }
}
