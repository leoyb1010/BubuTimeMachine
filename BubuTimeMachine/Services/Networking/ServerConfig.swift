import Foundation
import Observation

// MARK: - 服务器配置
/// 设置页可改 Base URL；存 @AppStorage（URL）+ Keychain（token，后续接入）。
/// App 启动读取，决定使用 Mock 还是真实 PocketBaseClient。
@Observable
final class ServerConfig {
    /// 服务器基础地址，例如 Tailscale 内网地址 http://100.x.x.x:8090
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

    /// AI 服务（FastAPI）地址，例如 http://100.x.x.x:8000
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

    /// 是否已配置真实服务器；未配置时全程走 Mock，仍可离线使用。
    var isConfigured: Bool { baseURL != nil && !accountEmail.isEmpty }

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

    init() {
        self.baseURLString = UserDefaults.standard.string(forKey: Self.baseURLKey) ?? ""
        self.currentRoleRaw = UserDefaults.standard.string(forKey: Self.roleKey) ?? FamilyRole.mama.rawValue
        self.childName = UserDefaults.standard.string(forKey: Self.childNameKey) ?? "布布"
        self.accountEmail = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""
        let legacyPassword = UserDefaults.standard.string(forKey: Self.passwordKey)
        if let legacyPassword, !legacyPassword.isEmpty {
            KeychainStore.set(legacyPassword, for: Self.passwordKey)
            UserDefaults.standard.removeObject(forKey: Self.passwordKey)
        }
        self.accountPassword = KeychainStore.string(for: Self.passwordKey) ?? legacyPassword ?? ""
        self.aiBaseURLString = UserDefaults.standard.string(forKey: Self.aiURLKey) ?? ""
        self.aiEnabled = UserDefaults.standard.bool(forKey: Self.aiEnabledKey)
        self.dailyReminderEnabled = UserDefaults.standard.bool(forKey: Self.reminderKey)
    }
}
