import Foundation
import SwiftData
import CoreData
import Darwin

/// App 和 Widget 共用的升级入口。先保护、再规范旧的隐式模型，最后执行版本化迁移。
enum BubuStoreLoader {
    static func open(at url: URL) throws -> ModelContainer {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent().appendingPathComponent("Documents/UpgradeBackups")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = Darwin.open(directory.appendingPathComponent("migration.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw StoreUpgradeBackup.BackupError.cannotOpen }
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        let deadline = Date().addingTimeInterval(4)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard Date() < deadline else { throw StoreUpgradeBackup.BackupError.cannotOpen }
            usleep(50_000)
        }
        if manager.fileExists(atPath: url.path) {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType, at: url, options: [NSReadOnlyPersistentStoreOption: true])
            let versions = metadata[NSStoreModelVersionIdentifiersKey] as? [String] ?? []
            if versions.isEmpty || versions == ["1.3.0"] {
                try StoreUpgradeBackup.prepare(store: url)
                // 早期版本都叫 V1，但形状曾增加可选字段。先走旧版本已使用的隐式轻量迁移，
                // 规范到冻结 V1，再走 V1→V2，避免把真实旧库误判成 unknown model version。
                try autoreleasepool {
                    let legacy = Schema(versionedSchema: BubuSchemaV1.self)
                    let config = ModelConfiguration(schema: legacy, url: url)
                    _ = try ModelContainer(for: legacy, configurations: [config])
                }
            }
        }
        let schema = SharedModelContainer.schema
        return try ModelContainer(for: schema, migrationPlan: BubuMigrationPlan.self,
                                  configurations: [ModelConfiguration(schema: schema, url: url)])
    }
}
