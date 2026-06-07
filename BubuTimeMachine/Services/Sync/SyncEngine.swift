import Foundation
import Observation

// MARK: - 同步引擎
/// 监听 SwiftData 变更与 PocketBase Realtime，双向收敛 syncState。
/// M1 阶段为骨架：本地优先，不实际联网；M2 接入真实订阅与状态收敛。
@Observable
@MainActor
final class SyncEngine {
    enum ConnectionState: Sendable {
        case offline        // 未配置或断网，全功能本地可用
        case connecting
        case online
    }

    private(set) var connectionState: ConnectionState = .offline

    private let apiClient: APIClient
    private let config: ServerConfig

    init(apiClient: APIClient, config: ServerConfig) {
        self.apiClient = apiClient
        self.config = config
    }

    /// 启动同步：M1 仅在已配置服务器时尝试连接，否则保持离线（不影响使用）。
    func start() {
        guard config.isConfigured else {
            connectionState = .offline
            return
        }
        connectionState = .connecting
        Task {
            let ok = (try? await apiClient.ping()) ?? false
            connectionState = ok ? .online : .offline
        }
    }
}
