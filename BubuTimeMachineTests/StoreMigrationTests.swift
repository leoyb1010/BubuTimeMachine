import Testing
import Foundation
import SwiftData
import CryptoKit
import SQLite3
@testable import BubuTimeMachine

// MARK: - 「旧版 store 还打得开吗」回归
///
/// 这是 30 年家庭档案唯一真正的底线测试：**升级之后，全家已经装机的那份数据还能打开。**
///
/// 背景（2026-09-04 审计 §1.1）：`BubuSchemaV1.models` 返回的是工程里**当前**的模型类，
/// 不是冻结快照——类改一个字段，所谓的「V1 历史快照」跟着变，版本化等于没做；
/// `stages` 也是空的。而 `BubuSchema.swift` 底部那段「下一次改模型必读」的 V2 模板
/// 照抄必然 abort（同文件 :39-44 自己已经写明并真机验证过）。
///
/// 在那套机制真正修好之前，唯一能挡住「升级后全家打开是空 App」的，就是这条测试：
/// 把一份**真实装机数据**（由 v2.12.2 的构建实际写出来、WAL 已合并的自包含单文件）
/// 放进测试 bundle，每次跑测试都用**生产同款配置 + 迁移计划**去打开它。
///
/// 任何一次让 SwiftData 无法推断迁移的模型改动，都会在这里变红，
/// 而不是等到用户升级完打开是一个空的家。
///
/// 基线文件：`Fixtures/LegacyStore_v2.12.2.store`（4 条时光 / 1 份档案 / 130 个里程碑 / 4 条媒体）。
/// 以后做破坏性 schema 变更时，**先让这条测试绿**，再考虑发版。
@MainActor
struct StoreMigrationTests {

    private static let fixtureName = "LegacyStore_v2.12.2"

    private func fixtureURL() throws -> URL {
        let bundle = Bundle(for: BundleToken.self)
        return try #require(
            bundle.url(forResource: Self.fixtureName, withExtension: "store", subdirectory: "Fixtures"),
            "测试 bundle 里找不到旧版 store 基线，检查 project.yml 的 resources 配置")
    }

    /// 把 bundle 里的基线复制到临时目录再打开——绝不在 bundle 原件上跑迁移。
    private func copyFixture() throws -> URL {
        // Fixtures 以 folder reference 进 bundle，所以要带 subdirectory 才找得到。
        let source = try fixtureURL()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("BubuTimeMachine.store")
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }

    private func copyStandaloneFixture(to destination: URL) throws {
        try FileManager.default.copyItem(at: fixtureURL(), to: destination)
        var database: OpaquePointer?
        guard sqlite3_open_v2(destination.path, &database,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else { throw StoreUpgradeBackup.BackupError.cannotOpen }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
            throw StoreUpgradeBackup.BackupError.cannotCopy
        }
    }

    @Test("旧版装机 store 能被当前 schema 打开，且数据一条不少")
    func legacyStoreStillOpens() throws {
        let url = try copyFixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // 生产同款：同一个 schema、同一个迁移计划、同一种 url 配置。
        // 任何一个环节和 App 里不一致，这条测试就失去意义。
        let config = ModelConfiguration(schema: SharedModelContainer.schema, url: url)
        let container = try ModelContainer(for: SharedModelContainer.schema,
                                           migrationPlan: BubuMigrationPlan.self,
                                           configurations: [config])
        let context = ModelContext(container)

        // 基线里的真实数量。少了就是迁移把数据吃了，多了说明 fixture 被污染。
        #expect(try context.fetchCount(FetchDescriptor<ChildProfile>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<Media>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<Milestone>()) == 130)

        // 不只是行数对得上：正文得读得出来，字段没有错位。
        let profile = try #require(try context.fetch(FetchDescriptor<ChildProfile>()).first)
        #expect(profile.name == "布布")

        let entries = try context.fetch(
            FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.happenedAt, order: .reverse)]))
        #expect(entries.first?.note?.isEmpty == false)
    }

    @Test("schema 登记表与工程里的 @Model 一一对应")
    func schemaRegistryIsComplete() {
        // 新增一个 @Model 却忘了登记到 BubuSchemaV1.models，该实体不会进 store，
        // 表现是「这个功能的数据每次重启都没了」，而且没有任何报错。
        // 这里把清单写死，逼着下次改模型的人同步更新两处。
        let expected: Set<String> = [
            "Entry", "Media", "Milestone", "FirstTime",
            "TimeCapsule", "VoiceMemo", "Comment", "GrowthMovie",
            "FamilyMember", "ChildProfile", "VoiceNote", "HealthRecord",
            "FeedEvent", "VaccineRecord", "GrowthMeasurement",
            "PendingDeletion",
        ]
        let registered = Set(BubuSchemaV1.models.map { String(describing: $0) })
        #expect(registered == expected,
                "BubuSchemaV1.models 与预期清单不一致：多了 \(registered.subtracting(expected))，少了 \(expected.subtracting(registered))")
    }

    @Test("schema 版本号冻结在 (1,3,0)")
    func versionIdentifierIsFrozen() {
        // 铁律 2：这是现有用户 store 里已经戳好的版本号。下调会让 SwiftData 以为
        // store 来自更新的版本而拒绝打开；空涨则会触发一次没有 stage 的迁移。
        #expect(BubuSchemaV1.versionIdentifier == Schema.Version(1, 3, 0))
    }

    @Test("换机恢复了儿童档案但丢失首启标记时直接进入主界面")
    func restoredProfileCompletesOnboarding() {
        #expect(AppEnvironment.resolvedOnboardingState(stored: false, childProfileCount: 1))
        #expect(!AppEnvironment.resolvedOnboardingState(stored: false, childProfileCount: 0))
        #expect(AppEnvironment.resolvedOnboardingState(stored: true, childProfileCount: 0))
    }

    @Test("换机只恢复 Documents 时，从保护副本自动找回空活动库")
    func transferredBackupRestoresEmptyStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TransferredStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("BubuTimeMachine.store")

        // 先模拟换机后 App 第一次启动已创建的空 V2 活动库。
        try autoreleasepool {
            let schema = SharedModelContainer.schema
            let container = try ModelContainer(for: schema, migrationPlan: BubuMigrationPlan.self,
                                               configurations: [ModelConfiguration(schema: schema, url: store)])
            try ModelContext(container).save()
        }

        let backup = StoreUpgradeBackup.destination(for: store)
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try copyStandaloneFixture(to: backup)
        let digest = SHA256.hash(data: try Data(contentsOf: backup)).map { String(format: "%02x", $0) }.joined()
        try digest.write(
            to: backup.appendingPathExtension("sha256"), atomically: true, encoding: .utf8)
        let counts = try StoreUpgradeBackup.factCounts(backup)
        let audit: [String: Any] = ["before": counts]
        try JSONSerialization.data(withJSONObject: audit).write(
            to: directory.appendingPathComponent("Documents/upgrade-audit-initial.json"), options: .atomic)

        let container = try BubuStoreLoader.open(at: store)
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<ChildProfile>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<Media>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<Milestone>()) == 130)
        #expect(try String(contentsOf: backup.appendingPathExtension("sha256"), encoding: .utf8) == digest)
    }

    @Test("换机恢复绝不覆盖非空活动库")
    func transferredBackupNeverOverwritesNonemptyStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NonemptyStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("BubuTimeMachine.store")
        try copyStandaloneFixture(to: store)
        let original = try Data(contentsOf: store)
        let backup = StoreUpgradeBackup.destination(for: store)
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try copyStandaloneFixture(to: backup)
        let digest = SHA256.hash(data: try Data(contentsOf: backup))
            .map { String(format: "%02x", $0) }.joined()
        try digest.write(to: backup.appendingPathExtension("sha256"), atomically: true, encoding: .utf8)

        #expect(try StoreUpgradeBackup.restoreTransferredBackupIfNeeded(store: store) == false)
        #expect(try Data(contentsOf: store) == original)
    }

    @Test("行数一致不能绕过备份 SHA 校验，也不能重签损坏副本")
    func matchingCountsDoNotOverrideChecksum() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("BubuTimeMachine.store")
        let backup = StoreUpgradeBackup.destination(for: store)
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try copyStandaloneFixture(to: backup)
        try "mismatch".write(to: backup.appendingPathExtension("sha256"), atomically: true, encoding: .utf8)
        let counts = try StoreUpgradeBackup.factCounts(backup)
        try JSONSerialization.data(withJSONObject: ["before": counts]).write(to: directory.appendingPathComponent("Documents/upgrade-audit-initial.json"))
        #expect(throws: (any Error).self) { try StoreUpgradeBackup.restoreTransferredBackupIfNeeded(store: store) }
        #expect(!FileManager.default.fileExists(atPath: store.path))
        #expect(try String(contentsOf: backup.appendingPathExtension("sha256"), encoding: .utf8) == "mismatch")
    }

    @Test("旧备份损坏不阻断健康的非空活动库")
    func damagedBackupDoesNotBlockCurrentStore() throws {
        let store = try copyFixture()
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
        // Normalize WAL fixture before readonly inspection.
        var db: OpaquePointer?
        #expect(sqlite3_open(store.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let backup = StoreUpgradeBackup.destination(for: store)
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: backup)
        #expect(try StoreUpgradeBackup.restoreTransferredBackupIfNeeded(store: store) == false)
        #expect(try StoreUpgradeBackup.factCounts(store)["ZENTRY"] == 4)
    }

    @Test("无法识别的活动库不能被判空覆盖")
    func unrecognizedCurrentStoreIsNeverReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = directory.appendingPathComponent("archive.store")
        var db: OpaquePointer?
        #expect(sqlite3_open(store.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "CREATE TABLE historic_fact (value TEXT); INSERT INTO historic_fact VALUES ('keep')", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let original = try Data(contentsOf: store)
        let backup = StoreUpgradeBackup.destination(for: store)
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try copyStandaloneFixture(to: backup)
        #expect(try StoreUpgradeBackup.restoreTransferredBackupIfNeeded(store: store) == false)
        #expect(try Data(contentsOf: store) == original)
    }
}

/// 用来定位测试 bundle。
private final class BundleToken {}
