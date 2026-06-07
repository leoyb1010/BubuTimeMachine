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

    var baseURL: URL? {
        guard !baseURLString.isEmpty else { return nil }
        return URL(string: baseURLString)
    }

    /// 是否已配置真实服务器；未配置时全程走 Mock，仍可离线使用。
    var isConfigured: Bool { baseURL != nil }

    private static let baseURLKey = "bubu.server.baseURL"
    private static let roleKey = "bubu.server.role"
    private static let childNameKey = "bubu.child.name"

    init() {
        self.baseURLString = UserDefaults.standard.string(forKey: Self.baseURLKey) ?? ""
        self.currentRoleRaw = UserDefaults.standard.string(forKey: Self.roleKey) ?? FamilyRole.mama.rawValue
        self.childName = UserDefaults.standard.string(forKey: Self.childNameKey) ?? "布布"
    }
}
