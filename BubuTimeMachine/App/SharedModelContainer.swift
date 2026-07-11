import Foundation
import OSLog
import SwiftData

// MARK: - 共享 ModelContainer（App Intents / Widget / extension 复用）
/// App Intents 可能在 App 外（后台、extension 进程）执行，拿不到 SwiftUI 注入的容器，
/// 需要一个能独立构建、指向同一 App Group store 的容器入口。
/// 与 BubuTimeMachineApp 用同一份 schema + 同一个 BubuStorage.storeURL，保证读写同一份数据。
enum SharedModelContainer {
    private static let log = Logger(subsystem: "com.bubu.timemachine", category: "SharedModelContainer")

    /// 全实体 schema：来自版本化的 BubuSchemaV1（唯一真相源，App/Widget/Intent 共用）。
    static let schema = Schema(versionedSchema: BubuSchemaV1.self)

    /// 进程内单例容器，指向 App Group 共享 store。Widget/Intent 进程用 `sharedIfAvailable`
    /// 避免共享库暂时打不开时直接崩溃成空白。
    static let sharedIfAvailable: ModelContainer? = {
        let config = ModelConfiguration(schema: schema, url: BubuStorage.storeURL)
        do {
            return try ModelContainer(for: schema, migrationPlan: BubuMigrationPlan.self,
                                      configurations: [config])
        } catch {
            log.error("无法创建共享 SwiftData 容器：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    /// 主流程需要强一致数据时仍可使用强制入口；extension 渲染层不要用它。
    static let shared: ModelContainer = {
        guard let container = sharedIfAvailable else {
            fatalError("无法创建共享 SwiftData 容器")
        }
        return container
    }()
}
