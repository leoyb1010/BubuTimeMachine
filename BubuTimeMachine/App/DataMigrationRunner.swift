import Foundation
import OSLog
import SwiftData

// MARK: - 版本化一次性数据迁移框架
/// 收编那些「本该只做一次、却被放在 bootstrap 每次启动都跑」的动作。
/// 设计目标：
/// - 每个迁移是一个具名 `DataMigration`（唯一 id + 执行闭包）。
/// - 完成标记存 UserDefaults：`bubu.datamigration.<id>.done`。
/// - 顺序执行未完成的迁移；**成功才落标记**；失败留痕（不落标记，下次启动重试），
///   且单个迁移失败不阻塞后续迁移，也不阻塞 App 启动。
/// - 新增迁移 = 往注册数组里加一个 `DataMigration`（供后续批次：生日归一化、胶囊 v2→v3…）。

/// 一个具名迁移。`run` 抛错即视为失败：runner 不落完成标记，下次启动重试。
@MainActor
struct DataMigration {
    let id: String
    let run: (ModelContext) throws -> Void

    init(id: String, run: @escaping (ModelContext) throws -> Void) {
        self.id = id
        self.run = run
    }
}

@MainActor
struct DataMigrationRunner {
    private static let keyPrefix = "bubu.datamigration."
    private static let log = Logger(subsystem: "com.bubu.timemachine", category: "DataMigration")

    private let migrations: [DataMigration]
    private let defaults: UserDefaults

    init(migrations: [DataMigration], defaults: UserDefaults = .standard) {
        self.migrations = migrations
        self.defaults = defaults
    }

    static func doneKey(for id: String) -> String { "\(keyPrefix)\(id).done" }

    func hasCompleted(_ id: String) -> Bool { defaults.bool(forKey: Self.doneKey(for: id)) }

    /// 顺序执行所有未完成的迁移。成功落标记；失败留痕但不阻塞后续迁移与启动。
    func runPendingMigrations(context: ModelContext) {
        for migration in migrations {
            let key = Self.doneKey(for: migration.id)
            guard !defaults.bool(forKey: key) else { continue }
            do {
                try migration.run(context)
                defaults.set(true, forKey: key)
                Self.log.notice("数据迁移完成：\(migration.id, privacy: .public)")
            } catch {
                // 不落标记：下次启动重试。不 break：各迁移相互独立，后续照常执行。
                Self.log.error("数据迁移失败（下次启动重试）：\(migration.id, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
