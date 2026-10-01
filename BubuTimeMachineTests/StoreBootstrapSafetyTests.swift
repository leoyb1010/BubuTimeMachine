import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

/// Synthetic temporary stores only; never opens the installed-data migration fixture.
@MainActor
struct StoreBootstrapSafetyTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreBootstrap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeLegacyStore(at url: URL) throws {
        try autoreleasepool {
            let schema = Schema(versionedSchema: BubuSchemaV1.self)
            let container = try ModelContainer(for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            context.insert(BubuSchemaV1.Entry(
                happenedAt: Date(timeIntervalSince1970: 1_700_000_000),
                authorRole: "synthetic parent", note: "legacy bootstrap fact"))
            try context.save()
        }
    }

    @Test("扩展先启动不创建空库；主 App 迁移后同一扩展可重试打开")
    func extensionFirstDoesNotSuppressLegacyMigration() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("legacy.store")
        let destination = root.appendingPathComponent("shared.store")
        try makeLegacyStore(at: source)
        let cache = SharedModelContainer.ExistingStoreCache()

        #expect(throws: StoreUpgradeBackup.BackupError.self) {
            try cache.open(at: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: destination.path + "-wal"))

        // Production app sequence: acquire loader lock, publish a legacy snapshot, migrate.
        try autoreleasepool {
            let app = try BubuStoreLoader.open(at: destination) {
                #expect(try StorageMigrator.copyStoreIfAbsent(from: source, to: destination))
            }
            #expect(try ModelContext(app).fetchCount(FetchDescriptor<Entry>()) == 1)
        }

        let extensionContainer = try cache.open(at: destination)
        let entries = try ModelContext(extensionContainer).fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 1)
        #expect(entries.first?.note == "legacy bootstrap fact")
        #expect(try cache.open(at: destination) === extensionContainer)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("缺少活动库时扩展不执行准备闭包，也不提前恢复备份")
    func extensionCannotBootstrapFromProtectionBackup() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("legacy.store")
        let destination = root.appendingPathComponent("shared.store")
        try makeLegacyStore(at: source)
        let backup = StoreUpgradeBackup.destination(for: destination)
        try StoreUpgradeBackup.snapshot(source: source, destination: backup)
        let original = try Data(contentsOf: backup)
        var preparationRan = false

        #expect(throws: StoreUpgradeBackup.BackupError.self) {
            try BubuStoreLoader.open(at: destination, requiresExistingStore: true) {
                preparationRan = true
            }
        }
        #expect(!preparationRan)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try Data(contentsOf: backup) == original)

        let app = try BubuStoreLoader.open(at: destination)
        #expect(try ModelContext(app).fetchCount(FetchDescriptor<Entry>()) == 1)
    }
}
