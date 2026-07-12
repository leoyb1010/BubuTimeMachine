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

    /// 主 App 进程启动后注入 App.init 建的容器（与 SwiftUI @Query/UI 同一个）。
    /// 注入后，进程内 App Intents / 通知回复 / 手表写入都经此拿到「同一个」容器：
    /// 写入能触发主 UI @Query 刷新、refreshWidgetSnapshot 读到最新数据，
    /// 不再出现「同一 store 上两个容器互相看不到对方写入」的问题。
    ///
    /// 进程隔离保证：extension（Widget/Intent）是独立进程，静态存储不与主 App 共享，
    /// 该值在 extension 进程里天然恒为 nil，故 extension 永远走下面的惰性自建共享容器，
    /// 绝不可能拿到主 App 的容器。
    @MainActor static var injected: ModelContainer?

    /// extension 进程惰性自建的共享容器，指向 App Group 共享 store。
    /// 仅在 `injected` 为 nil（即 extension 进程，或主 App 尚未完成注入）时启用。
    /// 共享库暂时打不开时返回 nil，避免直接崩溃成空白。
    private static let lazyShared: ModelContainer? = {
        let config = ModelConfiguration(schema: schema, url: BubuStorage.storeURL)
        do {
            return try ModelContainer(for: schema, migrationPlan: BubuMigrationPlan.self,
                                      configurations: [config])
        } catch {
            log.error("无法创建共享 SwiftData 容器：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    /// 进程内统一入口：主 App 进程返回注入的 App 容器；extension 进程回退到自建共享容器。
    /// Widget/Intent 渲染层用它避免共享库暂时打不开时直接崩溃成空白。
    @MainActor static var sharedIfAvailable: ModelContainer? {
        injected ?? lazyShared
    }

    /// 主流程需要强一致数据时仍可使用强制入口；extension 渲染层不要用它。
    @MainActor static var shared: ModelContainer {
        guard let container = sharedIfAvailable else {
            fatalError("无法创建共享 SwiftData 容器")
        }
        return container
    }
}
