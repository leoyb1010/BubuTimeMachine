import Foundation
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
}
