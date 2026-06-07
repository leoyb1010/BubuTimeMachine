import Foundation
import Observation

// MARK: - 全局依赖容器（DI）
/// @Observable 持有全部服务与全局状态，通过 .environment() 注入，便于 Mock 与测试。
/// 接口先行：默认装配 Mock，已配置服务器时（M2）切换为真实 PocketBaseClient。
@Observable
@MainActor
final class AppEnvironment {
    let config: ServerConfig
    let apiClient: APIClient
    let aiService: AIService
    let mediaStore: MediaStore
    let syncEngine: SyncEngine
    let uploadQueue: UploadQueue
    let crypto: CapsuleCrypto
    let theme: ThemeManager
    let photoAnalyzer: PhotoAnalyzer

    /// 当前身份（成员 id）。nil 表示尚未选择/未完成首启引导。
    var currentMemberId: UUID? {
        didSet {
            if let id = currentMemberId {
                UserDefaults.standard.set(id.uuidString, forKey: Self.memberKey)
            }
        }
    }

    /// 首启引导是否完成（已设置布布生日 + 至少一个成员）。
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Self.onboardedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.onboardedKey) }
    }

    private static let memberKey = "bubu.current.memberId"
    private static let onboardedKey = "bubu.onboarded"

    init() {
        let config = ServerConfig()
        let api: APIClient = MockAPIClient()

        self.config = config
        self.apiClient = api
        self.aiService = MockAIService()
        self.mediaStore = MediaStore()
        self.syncEngine = SyncEngine(apiClient: api, config: config)
        self.uploadQueue = UploadQueue(apiClient: api)
        self.crypto = CapsuleCrypto()
        self.theme = ThemeManager()
        self.photoAnalyzer = PhotoAnalyzer()

        if let raw = UserDefaults.standard.string(forKey: Self.memberKey) {
            self.currentMemberId = UUID(uuidString: raw)
        }
    }

    /// App 启动后调用：启动同步层（离线时无副作用）。
    func bootstrap() {
        syncEngine.start()
    }
}
