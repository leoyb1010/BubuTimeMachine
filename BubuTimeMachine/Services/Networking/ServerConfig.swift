import Foundation
import Observation

// MARK: - 服务器配置
/// 设置页可改 Base URL；存 @AppStorage（URL）+ Keychain（token，后续接入）。
/// App 启动读取，决定使用 Mock 还是真实 PocketBaseClient。
@Observable
final class ServerConfig {
    /// 服务器基础地址，例如默认 Cloudflare 公网地址。
    var baseURLString: String {
        didSet {
            UserDefaults.standard.set(baseURLString, forKey: Self.baseURLKey)
            // 换服务器 / 恢复到别的后端：清空旧同步游标，否则新服务器的历史记录拉不全。
            // 仅在地址真的变化时清，避免设置页写回同值触发不必要的全量重拉。
            if oldValue != baseURLString {
                SyncEngine.resetAllCursors()
            }
        }
    }

    /// 局域网直连地址（可选，如 http://192.168.1.10:8090）。主地址走 Tailscale/隧道回落公网中继时，
    /// 同一 Wi-Fi 传照片会绕外网——填了这个，照片/视频传输自动与主地址赛跑择优，家里秒传。
    var lanBaseURLString: String {
        didSet { UserDefaults.standard.set(lanBaseURLString, forKey: Self.lanBaseURLKey) }
    }

    var lanBaseURL: URL? {
        let trimmed = lanBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    /// 当前家庭身份（爸爸/妈妈/姥姥），用于署名与多视角。
    var currentRoleRaw: String {
        didSet {
            UserDefaults.standard.set(currentRoleRaw, forKey: Self.roleKey)
            // 镜像到 App Group，供 Intent/Widget 读取当前署名身份。
            SharedDefaults.currentRole = FamilyRole(rawValue: currentRoleRaw) ?? .mama
            let newRole = FamilyRole(rawValue: currentRoleRaw) ?? .mama
            // 从「父母」切到「长辈」时，记住切换前的父母身份，供退出简单模式时切回（避免误署长辈名）。
            if newRole.isElder, !(FamilyRole(rawValue: oldValue)?.isElder ?? false) {
                roleBeforeElderRaw = oldValue
            }
            // 身份决定模式：切到长辈自动进「简单模式」，切回父母自动回完整 App。
            simpleModeEnabled = newRole.isElder
        }
    }

    /// 简单模式（老人模式）开关：大字大按钮、只保留 拍照 / 录音 / 看布布。
    /// 跟随身份自动开关（见 currentRoleRaw.didSet），也可在设置里手动覆盖。
    var simpleModeEnabled: Bool {
        didSet { UserDefaults.standard.set(simpleModeEnabled, forKey: Self.simpleModeKey) }
    }

    /// 切到长辈身份前最后一次的父母身份（退出简单模式时切回）。
    var roleBeforeElderRaw: String? {
        didSet { UserDefaults.standard.set(roleBeforeElderRaw, forKey: Self.roleBeforeElderKey) }
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
            if accountPassword.isEmpty {
                KeychainStore.delete(Self.passwordKey)
                credentialSaveFailed = false
            } else {
                // 写不进钥匙串时这次运行照常同步（密码还在内存里），但下次冷启动会读不到、悄悄变离线。
                // 记下来让界面提示「需要重新登录」，而不是等家人发现照片没同步（D9-09）。
                credentialSaveFailed = !KeychainStore.setVerified(accountPassword, for: Self.passwordKey)
            }
        }
    }

    /// 本次登录的密码没能存进钥匙串。
    private(set) var credentialSaveFailed = false

    /// 填过账号却读不到密码：换了新手机（钥匙串条目只在本机）或上次没存住。同步已悄悄停了，需要重新登录。
    var needsReauthentication: Bool {
        credentialSaveFailed ||
        (!accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && accountPassword.isEmpty)
    }

    /// 给界面用的一句话；不需要时为 nil。
    var reauthenticationMessage: String? {
        guard needsReauthentication else { return nil }
        return credentialSaveFailed
            ? "密码没能安全保存到这台设备，下次打开会断开同步。请到「账号」里重新登录一次。"
            : "需要重新登录才能继续同步：这台设备上没有找到账号密码（换手机或系统清理后常见）。"
    }

    /// AI 服务（FastAPI）地址。默认空：必须用户自己填，绝不默认把数据发到任何外部服务器。
    var aiBaseURLString: String {
        didSet { UserDefaults.standard.set(aiBaseURLString, forKey: Self.aiURLKey) }
    }
    /// 是否启用真实 AI（关闭则用 Mock，离线可玩）。
    var aiEnabled: Bool {
        didSet { UserDefaults.standard.set(aiEnabled, forKey: Self.aiEnabledKey) }
    }
    /// Separate, explicit consent: only the report selected for import may leave the device.
    var schoolVisionEnabled: Bool {
        didSet { UserDefaults.standard.set(schoolVisionEnabled, forKey: Self.schoolVisionKey) }
    }
    /// 是否允许把搜索词发给家中自托管 AI 服务做照片画面检索。默认关闭，文字搜索始终本地可用。
    var semanticSearchEnabled: Bool {
        didSet { UserDefaults.standard.set(semanticSearchEnabled, forKey: Self.semanticSearchEnabledKey) }
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
        guard let candidate = URL(string: aiBaseURLString),
              Self.isTrustedAIURL(
                candidate,
                serverURL: baseURL,
                packagedAIURL: URL(string: Self.defaultAIBaseURL)
              ) else { return nil }
        return candidate
    }

    /// AI 请求携带可访问家庭 PocketBase 的短期 Bearer，目标地址因此必须受限。
    /// 正式包只信任构建时注入的 AI 地址，或与 PocketBase 同源的反向代理；
    /// Debug 额外允许本机回环，方便隔离开发，绝不把登录态发给任意输入的主机。
    nonisolated static func isTrustedAIURL(
        _ candidate: URL,
        serverURL: URL?,
        packagedAIURL: URL?,
        allowLoopback: Bool = _isDebugAssertConfiguration()
    ) -> Bool {
        guard let scheme = candidate.scheme?.lowercased(),
              let host = candidate.host?.lowercased(),
              candidate.user == nil,
              candidate.password == nil else { return false }
        let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard scheme == "https" || (allowLoopback && isLoopback && scheme == "http") else {
            return false
        }
        if let packagedAIURL,
           packagedAIURL.scheme?.lowercased() == scheme,
           packagedAIURL.host?.lowercased() == host,
           packagedAIURL.port == candidate.port {
            return true
        }
        if let serverURL,
           serverURL.scheme?.lowercased() == scheme,
           serverURL.host?.lowercased() == host,
           serverURL.port == candidate.port {
            return true
        }
        return allowLoopback && isLoopback
    }

    var hasServerCredentials: Bool {
        !accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !accountPassword.isEmpty
    }

    /// 是否已配置真实服务器；未配置时全程走 Mock，仍可离线使用。
    var isConfigured: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitest-in-memory") || ProcessInfo.processInfo.environment["BUBU_UNIT_TEST_HOST"] == "1" {
            return false
        }
        #endif
        return baseURL != nil && hasServerCredentials
    }

    /// 是否可用真实 AI。
    var isAIConfigured: Bool {
        aiEnabled && aiBaseURL != nil && isConfigured
    }

    private static let baseURLKey = "bubu.server.baseURL"
    private static let lanBaseURLKey = "bubu.server.lanBaseURL"
    private static let roleKey = "bubu.server.role"
    private static let childNameKey = "bubu.child.name"
    private static let emailKey = "bubu.server.email"
    private static let passwordKey = "bubu.server.password"
    private static let aiURLKey = "bubu.ai.baseURL"
    private static let legacyAIKeyKey = "bubu.ai.apiKey"
    private static let aiEnabledKey = "bubu.ai.enabled"
    private static let schoolVisionKey = "bubu.school.vision.enabled"
    private static let semanticSearchEnabledKey = "bubu.ai.semanticSearch.enabled"
    private static let reminderKey = "bubu.reminder.enabled"
    private static let simpleModeKey = "bubu.simpleMode.enabled"
    private static let roleBeforeElderKey = "bubu.simpleMode.roleBeforeElder"

    /// 出厂默认服务器地址：不写死源码（避免泄露家庭域名），打包时经 Info.plist 注入。
    /// 之前 Release 分支只显示"已内置 ✓"却是空串、又没有输入框——新装机永远登录不上。
    static var defaultBaseURL: String { injectedValue("BUBU_DEFAULT_BASE_URL") }
    static var defaultAIBaseURL: String { injectedValue("BUBU_DEFAULT_AI_BASE_URL") }
    private static func injectedValue(_ key: String) -> String {
        let infoValue = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let envValue = ProcessInfo.processInfo.environment[key]
        return [infoValue, envValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("$(") } ?? ""
    }
    /// 设置页占位示例。
    static let baseURLPlaceholder = "https://你的服务器地址:8090"
    static let aiBaseURLPlaceholder = "https://你的AI服务地址:8000"

    init() {
        let initialBaseURL = UserDefaults.standard.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURL
        self.baseURLString = initialBaseURL
        self.lanBaseURLString = UserDefaults.standard.string(forKey: Self.lanBaseURLKey) ?? ""
        self.currentRoleRaw = UserDefaults.standard.string(forKey: Self.roleKey) ?? FamilyRole.mama.rawValue
        self.childName = UserDefaults.standard.string(forKey: Self.childNameKey) ?? "布布"
        let initialAccountEmail = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""
        self.accountEmail = initialAccountEmail
        let legacyPassword = UserDefaults.standard.string(forKey: Self.passwordKey)
        if let legacyPassword, !legacyPassword.isEmpty {
            KeychainStore.set(legacyPassword, for: Self.passwordKey)
            UserDefaults.standard.removeObject(forKey: Self.passwordKey)
        }
        let initialAccountPassword = KeychainStore.string(for: Self.passwordKey) ?? legacyPassword ?? ""
        self.accountPassword = initialAccountPassword
        let initialAIBaseURL = UserDefaults.standard.string(forKey: Self.aiURLKey)
            ?? Self.defaultAIBaseURL
        self.aiBaseURLString = initialAIBaseURL
        // v2.7 起 AI 复用 PocketBase 用户登录态；清掉旧共享 key，避免被发往误填的主机。
        KeychainStore.delete(Self.legacyAIKeyKey)
        // 数据外发必须用户显式开启（CLAUDE.md 铁律）。这里**只能** `?? false`：
        // 曾经的兜底是「打包 AI 地址非空 + 账号密码非空 → 默认开」，而 AI 地址是出厂硬编码的，
        // 于是用户只要为了同步填完家庭账号密码，下次冷启动 AI 就自己变成开——记录原文
        // （含疫苗/症状）随即经家庭服务转发给 DeepSeek 云端，用户从未碰过那个开关。
        // 更隐蔽的是 aiEnabled 的持久化写在 didSet 里，而 **Swift 在 init 内赋值不触发 didSet**，
        // 兜底值永不落盘 → 每次冷启动重新求值，关掉也可能被再次打开。
        // 结论：没存过就是关。开启入口只有设置页那个开关（旁边已写明外发目的地）。
        self.aiEnabled = UserDefaults.standard.object(forKey: Self.aiEnabledKey) as? Bool ?? false
        // 例外（用户 2026-10-27 明确要求「直接内置」）：亲子桥识别默认开——新装手机曾因没开它一直用本机 OCR，
        // 把 10月27日 读成 10月2日。只发用户主动导入的那张日表，且只到家里 mini（再交第二大脑 Gemini）。
        // 关掉时 didSet 会落盘 false，之后一直保持关闭。
        self.schoolVisionEnabled = UserDefaults.standard.object(forKey: Self.schoolVisionKey) as? Bool ?? true
        self.semanticSearchEnabled = UserDefaults.standard.object(
            forKey: Self.semanticSearchEnabledKey
        ) as? Bool ?? false
        self.dailyReminderEnabled = UserDefaults.standard.bool(forKey: Self.reminderKey)
        // 简单模式：已存过就用存的；从没存过时，按当前身份是否长辈给默认值（长辈默认开）。
        let storedRole = FamilyRole(rawValue: UserDefaults.standard.string(forKey: Self.roleKey) ?? "") ?? .mama
        self.simpleModeEnabled = UserDefaults.standard.object(forKey: Self.simpleModeKey) as? Bool ?? storedRole.isElder
        self.roleBeforeElderRaw = UserDefaults.standard.string(forKey: Self.roleBeforeElderKey)
        #if DEBUG
        // 联调专用：UI 测试把模拟器指向本机回环的测试服务（测试账号来自测试环境变量，绝不用于正式包）。
        let environment = ProcessInfo.processInfo.environment
        if ProcessInfo.processInfo.arguments.contains("-uitest-server-config"),
           let pb = environment["BUBU_UITEST_PB_URL"], let ai = environment["BUBU_UITEST_AI_URL"],
           let email = environment["BUBU_UITEST_EMAIL"], let password = environment["BUBU_UITEST_PASSWORD"] {
            self.baseURLString = pb
            self.aiBaseURLString = ai
            self.accountEmail = email
            self.accountPassword = password
        }
        #endif
        // didSet 不在 init 内触发，显式把身份/名字镜像到 App Group，供 Intent/Widget 首次即可读。
        SharedDefaults.mirror(role: FamilyRole(rawValue: currentRoleRaw) ?? .mama, childName: childName)
        consumeSchoolVisionSetup()
    }

    private func consumeSchoolVisionSetup() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BubuSchoolVisionSetup.json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4096,
              let data = try? Data(contentsOf: url),
              let enabled = SchoolVisionSetup.enabled(in: data, expectedService: Self.defaultAIBaseURL) else { return }
        do {
            if let token = SchoolVisionSetup.credential(in: data, expectedService: Self.defaultAIBaseURL) {
                KeychainStore.set(token, for: SchoolVisionSetup.credentialKey)
                // Do not consume a credential we failed to retain (e.g. device still locked).
                guard KeychainStore.string(for: SchoolVisionSetup.credentialKey) == token else { return }
            }
            // Consume before persisting so a stale file cannot override a later switch-off.
            try FileManager.default.removeItem(at: url)
            aiBaseURLString = Self.defaultAIBaseURL
            schoolVisionEnabled = enabled
        } catch { return }
    }
}
