import Foundation
import Observation

// MARK: - 全局依赖容器（DI）
/// @Observable 持有 APIClient / AIService / SyncEngine / UploadQueue / MediaStore / ServerConfig，
/// 通过 .environment() 全局注入，便于 Mock 与测试。
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

    init() {
        let config = ServerConfig()
        // M0/M1：始终使用 Mock，保证离线全功能可用。
        // M2：当 config.isConfigured 时改为 PocketBaseClient(baseURL:)。
        let api: APIClient = MockAPIClient()

        self.config = config
        self.apiClient = api
        self.aiService = MockAIService()
        self.mediaStore = MediaStore()
        self.syncEngine = SyncEngine(apiClient: api, config: config)
        self.uploadQueue = UploadQueue(apiClient: api)
        self.crypto = CapsuleCrypto()
    }

    /// App 启动后调用：启动同步层（离线时无副作用）。
    func bootstrap() {
        syncEngine.start()
    }
}
