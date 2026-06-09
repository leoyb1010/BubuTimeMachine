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
        didSet { UserDefaults.standard.set(currentRoleRaw, forKey: Self.roleKey) }
    }

    var currentRole: FamilyRole {
        get { FamilyRole(rawValue: currentRoleRaw) ?? .mama }
        set { currentRoleRaw = newValue.rawValue }
    }

    /// 孩子的名字，用于 AI 第一人称改写等场景。
    var childName: String {
        didSet { UserDefaults.standard.set(childName, forKey: Self.childNameKey) }
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

    /// AI 服务（FastAPI）地址，例如默认 Cloudflare 公网地址。
    var aiBaseURLString: String {
        didSet { UserDefaults.standard.set(aiBaseURLString, forKey: Self.aiURLKey) }
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
    var isAIConfigured: Bool { aiEnabled && aiBaseURL != nil }

    private static let baseURLKey = "bubu.server.baseURL"
    private static let roleKey = "bubu.server.role"
    private static let childNameKey = "bubu.child.name"
    private static let emailKey = "bubu.server.email"
    private static let passwordKey = "bubu.server.password"
    private static let aiURLKey = "bubu.ai.baseURL"
    private static let aiEnabledKey = "bubu.ai.enabled"
    private static let reminderKey = "bubu.reminder.enabled"

    /// 默认公网地址：通过 Cloudflare Tunnel 暴露家里 Mac mini 上的服务，
    /// 任何网络（家庭 WiFi / 运营商 4G/5G）都可直连，无需 Tailscale。
    /// 用户仍可在设置页改写为自己的内网地址。
    static let defaultBaseURL = "https://bubu-api.leoyuan.top"
    static let defaultAIBaseURL = "https://bubu-ai.leoyuan.top"

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
        // AI 首次默认开启（已有公网地址）；用户改过则尊重其设置。
        self.aiEnabled = UserDefaults.standard.object(forKey: Self.aiEnabledKey) as? Bool ?? true
        self.dailyReminderEnabled = UserDefaults.standard.bool(forKey: Self.reminderKey)
    }
}
