import Foundation
import CryptoKit
import SQLite3
import Testing
@testable import BubuTimeMachine

struct StoreUpgradeBackupTests {
    @Test("升级快照包含 WAL 最新提交，并且重复运行不覆盖旧副本")
    func snapshotIncludesWALAndDoesNotOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.store")
        let target = directory.appendingPathComponent("backup.store")
        var database: OpaquePointer?
        #expect(sqlite3_open(source.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        #expect(sqlite3_exec(database, "PRAGMA journal_mode=WAL; CREATE TABLE facts(value TEXT); INSERT INTO facts VALUES ('latest');", nil, nil, nil) == SQLITE_OK)
        try StoreUpgradeBackup.snapshot(source: source, destination: target)
        let first = try Data(contentsOf: target)
        #expect(sqlite3_exec(database, "INSERT INTO facts VALUES ('newer');", nil, nil, nil) == SQLITE_OK)
        try StoreUpgradeBackup.snapshot(source: source, destination: target)
        #expect(try Data(contentsOf: target) == first)
        var snapshot: OpaquePointer?
        #expect(sqlite3_open_v2(target.path, &snapshot, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(snapshot) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(snapshot, "SELECT count(*) FROM facts", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 1)
    }

    @Test("损坏的已有快照必须阻止迁移，不能用新库覆盖它")
    func corruptSnapshotStopsUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("backup.store")
        let bytes = Data("damaged".utf8)
        try bytes.write(to: target)
        #expect(throws: (any Error).self) {
            try StoreUpgradeBackup.snapshot(source: directory.appendingPathComponent("missing"), destination: target)
        }
        #expect(try Data(contentsOf: target) == bytes)
    }
    @Test("旧沙盒迁移原子发布包含 WAL 的独立快照")
    func legacyStorePublicationIncludesWAL() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.store")
        let target = directory.appendingPathComponent("target.store")
        var database: OpaquePointer?
        #expect(sqlite3_open(source.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        #expect(sqlite3_exec(database, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE facts(value TEXT); INSERT INTO facts VALUES ('old'); PRAGMA wal_checkpoint(TRUNCATE); INSERT INTO facts VALUES ('latest');", nil, nil, nil) == SQLITE_OK)

        #expect(try StorageMigrator.copyStoreIfAbsent(from: source, to: target))
        #expect(FileManager.default.fileExists(atPath: source.path))
        var snapshot: OpaquePointer?
        #expect(sqlite3_open_v2(target.path, &snapshot, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(snapshot) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(snapshot, "SELECT count(*) FROM facts", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 2)
        #expect(!FileManager.default.fileExists(atPath: target.path + "-wal"))
    }

    @Test("已有健康、声音或胶囊库永不被旧沙盒替换",
          arguments: ["ZHEALTHRECORD", "ZVOICENOTE", "ZTIMECAPSULE"])
    func existingFactStoreIsNeverReplaced(table: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.store")
        var database: OpaquePointer?
        #expect(sqlite3_open(target.path, &database) == SQLITE_OK)
        #expect(sqlite3_exec(database, "CREATE TABLE \(table)(value TEXT); INSERT INTO \(table) VALUES ('keep');", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)
        let original = try Data(contentsOf: target)
        #expect(try !StorageMigrator.copyStoreIfAbsent(
            from: directory.appendingPathComponent("missing-source.store"), to: target))
        #expect(try Data(contentsOf: target) == original)
    }

    @Test("迁移失败不能留下可误认成功的活动库")
    func failedLegacySnapshotDoesNotPublish() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("broken.store")
        let target = directory.appendingPathComponent("target.store")
        try Data("not sqlite".utf8).write(to: source)
        #expect(throws: (any Error).self) {
            try StorageMigrator.copyStoreIfAbsent(from: source, to: target)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(try Data(contentsOf: source) == Data("not sqlite".utf8))
    }

    @Test("遗留的单独日志文件必须保留，不能接到另一个库上")
    func orphanedJournalStopsLegacyPublication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.store")
        let journal = URL(fileURLWithPath: target.path + "-wal")
        let bytes = Data("preserve".utf8)
        try bytes.write(to: journal)
        #expect(throws: (any Error).self) {
            try StorageMigrator.copyStoreIfAbsent(
                from: directory.appendingPathComponent("missing-source.store"), to: target)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(try Data(contentsOf: journal) == bytes)
    }

    @Test("换机恢复发布失败不留下半份活动库，原备份完整并可重试", arguments: [false, true])
    func failedTransferredPublicationKeepsBackupAndCanRetry(existingEmptyStore: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("active.store")
        let source = directory.appendingPathComponent("synthetic.store")
        try makeSyntheticTransferArchive(at: source, populatedTables: ["ZENTRY", "ZMEDIA", "ZVOICENOTE"])
        let backup = StoreUpgradeBackup.destination(for: store)
        try StoreUpgradeBackup.snapshot(source: source, destination: backup)
        let originalBackup = try Data(contentsOf: backup)
        let originalChecksum = try Data(contentsOf: backup.appendingPathExtension("sha256"))
        if existingEmptyStore { try makeSyntheticTransferArchive(at: store) }

        let manager = TransferPublicationFileManager()
        manager.failPublication = true
        #expect(throws: (any Error).self) {
            try StoreUpgradeBackup.restoreTransferredBackupIfNeeded(store: store, fm: manager)
        }
        #expect(manager.publicationAttempted)
        #expect(!FileManager.default.fileExists(atPath: store.path))
        #expect(!FileManager.default.fileExists(atPath: store.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: store.path + "-shm"))
        #expect(try Data(contentsOf: backup) == originalBackup)
        #expect(try Data(contentsOf: backup.appendingPathExtension("sha256")) == originalChecksum)
        try StoreUpgradeBackup.validate(backup)
        if existingEmptyStore {
            let safety = backup.deletingLastPathComponent()
                .appendingPathComponent("empty-store-before-transfer-restore.store")
            try StoreUpgradeBackup.validate(safety)
            let counts = try StoreUpgradeBackup.factCounts(safety)
            #expect(counts.values.allSatisfy { $0 == 0 })
        }

        let restored = try StoreUpgradeBackup.restoreTransferredBackupIfNeeded(store: store)
        #expect(restored)
        let actualCounts = try StoreUpgradeBackup.factCounts(store)
        let expectedCounts = try StoreUpgradeBackup.factCounts(backup)
        #expect(actualCounts == expectedCounts)
        #expect(try transferValue(in: store, table: "ZENTRY") == "synthetic-ZENTRY-完整内容")
        #expect(try Data(contentsOf: backup) == originalBackup)
        #expect(try Data(contentsOf: backup.appendingPathExtension("sha256")) == originalChecksum)
    }

    @Test("换机恢复原子移动已验证快照，正文、哈希和原备份不变", arguments: [false, true])
    func transferredBackupPublishesValidatedSnapshotAtomically(existingEmptyStore: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("active.store")
        let source = directory.appendingPathComponent("synthetic.store")
        let populatedTables: Set<String> = ["ZENTRY", "ZMEDIA", "ZCHILDPROFILE", "ZHEALTHRECORD", "ZTIMECAPSULE"]
        try makeSyntheticTransferArchive(at: source, populatedTables: populatedTables)
        let backup = StoreUpgradeBackup.destination(for: store)
        try StoreUpgradeBackup.snapshot(source: source, destination: backup)
        let originalBackup = try Data(contentsOf: backup)
        let originalChecksum = try Data(contentsOf: backup.appendingPathExtension("sha256"))
        if existingEmptyStore { try makeSyntheticTransferArchive(at: store) }

        let manager = TransferPublicationFileManager()
        let restored = try StoreUpgradeBackup.restoreTransferredBackupIfNeeded(store: store, fm: manager)
        #expect(restored)
        let stagedBytes = try #require(manager.stagedBytes)
        let stagedFileNumber = try #require(manager.stagedFileNumber)
        let activeAttributes = try FileManager.default.attributesOfItem(atPath: store.path)
        // A copy can preserve every byte and still expose partial content during publication.
        // Keeping the staging inode proves the active file was moved rather than recopied.
        #expect(activeAttributes[.systemFileNumber] as? NSNumber == stagedFileNumber)
        let activeBytes = try Data(contentsOf: store)
        #expect(SHA256.hash(data: activeBytes) == SHA256.hash(data: stagedBytes))
        for table in populatedTables {
            #expect(try transferValue(in: store, table: table) == "synthetic-\(table)-完整内容")
        }
        #expect(!FileManager.default.fileExists(atPath: store.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: store.path + "-shm"))
        #expect(try Data(contentsOf: backup) == originalBackup)
        #expect(try Data(contentsOf: backup.appendingPathExtension("sha256")) == originalChecksum)
        try StoreUpgradeBackup.validate(backup)
    }

    @Test("换机恢复保留已有事实、待删除记录和未知历史库",
          arguments: ["ZENTRY", "ZHEALTHRECORD", "ZVOICENOTE", "ZTIMECAPSULE",
                      "ZFIRSTTIME", "ZGROWTHMOVIE", "ZFEEDEVENT", "ZPENDINGDELETION", "historic_fact"])
    func transferredBackupNeverReplacesExistingFactsOrUnknownStore(table: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("active.store")
        let source = directory.appendingPathComponent("synthetic.store")
        try makeSyntheticTransferArchive(at: source, populatedTables: ["ZENTRY"])
        let backup = StoreUpgradeBackup.destination(for: store)
        try StoreUpgradeBackup.snapshot(source: source, destination: backup)
        if table == "historic_fact" {
            try makeSyntheticTransferArchive(at: store, populatedTables: [table], tables: [table])
        } else {
            try makeSyntheticTransferArchive(at: store, populatedTables: [table])
        }
        let original = try Data(contentsOf: store)
        let originalBackup = try Data(contentsOf: backup)
        let manager = TransferPublicationFileManager()
        manager.failPublication = true

        let restored = try StoreUpgradeBackup.restoreTransferredBackupIfNeeded(store: store, fm: manager)
        #expect(!restored)
        #expect(!manager.publicationAttempted)
        #expect(try Data(contentsOf: store) == original)
        #expect(try Data(contentsOf: backup) == originalBackup)
        #expect(try transferValue(in: store, table: table) == "synthetic-\(table)-完整内容")
    }

    private func makeSyntheticTransferArchive(
        at file: URL,
        populatedTables: Set<String> = [],
        tables: [String] = [
            "ZENTRY", "ZMEDIA", "ZCHILDPROFILE", "ZMILESTONE", "ZHEALTHRECORD", "ZTIMECAPSULE",
            "ZVOICEMEMO", "ZVOICENOTE", "ZCOMMENT", "ZFAMILYMEMBER", "ZVACCINERECORD", "ZGROWTHMEASUREMENT",
            "ZFIRSTTIME", "ZGROWTHMOVIE", "ZFEEDEVENT", "ZPENDINGDELETION"
        ]
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open(file.path, &database) == SQLITE_OK, let database else {
            throw StoreUpgradeBackup.BackupError.cannotOpen
        }
        defer { sqlite3_close(database) }
        for table in tables {
            let insert = populatedTables.contains(table)
                ? "INSERT INTO \(table) VALUES ('synthetic-\(table)-完整内容');" : ""
            guard sqlite3_exec(database, "CREATE TABLE \(table)(value TEXT); \(insert)", nil, nil, nil) == SQLITE_OK else {
                throw StoreUpgradeBackup.BackupError.cannotCopy
            }
        }
    }

    private func transferValue(in file: URL, table: String) throws -> String {
        var database: OpaquePointer?
        guard sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { throw StoreUpgradeBackup.BackupError.cannotOpen }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM \(table)", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw StoreUpgradeBackup.BackupError.invalidSnapshot }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
            throw StoreUpgradeBackup.BackupError.invalidSnapshot
        }
        return String(cString: value)
    }
}

/// Per-test file manager: failure is injected only at the final active-store publication.
/// The old copy path deliberately leaves a truncated file, as an interrupted copy can do.
private nonisolated final class TransferPublicationFileManager: FileManager, @unchecked Sendable {
    var failPublication = false
    private(set) var publicationAttempted = false
    private(set) var stagedBytes: Data?
    private(set) var stagedFileNumber: NSNumber?

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try observePublication(from: srcURL)
        if failPublication { throw CocoaError(.fileWriteOutOfSpace) }
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try observePublication(from: srcURL)
        if failPublication {
            let bytes = try Data(contentsOf: srcURL)
            try Data(bytes.prefix(4_096)).write(to: dstURL)
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try super.copyItem(at: srcURL, to: dstURL)
    }

    private func observePublication(from source: URL) throws {
        publicationAttempted = true
        stagedBytes = try Data(contentsOf: source)
        stagedFileNumber = try attributesOfItem(atPath: source.path)[.systemFileNumber] as? NSNumber
    }
}
