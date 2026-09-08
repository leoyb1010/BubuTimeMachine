import Foundation
import CoreData
import CryptoKit
import SQLite3

/// V1→V2 之前保留包含 WAL 最新内容的独立 SQLite 快照。备份失败则不开始迁移。
nonisolated enum StoreUpgradeBackup {
    enum BackupError: Error { case cannotOpen, cannotCopy, invalidSnapshot }

    static func destination(for store: URL) -> URL {
        store.deletingLastPathComponent().appendingPathComponent("Documents/UpgradeBackups/pre-v2.store")
    }

    @discardableResult
    static func prepare(store: URL) throws -> URL? {
        guard FileManager.default.fileExists(atPath: store.path) else { return nil }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: store, options: [NSReadOnlyPersistentStoreOption: true])
        if (metadata[NSStoreModelVersionIdentifiersKey] as? [String])?.contains("2.0.0") == true { return nil }
        let target = destination(for: store)
        try snapshot(source: store, destination: target)
        return target
    }

    static func snapshot(source: URL, destination: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: destination.path) {
            try validate(destination)
            return
        }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).partial")
        defer { try? manager.removeItem(at: temporary) }
        var sourceDB: OpaquePointer?
        var targetDB: OpaquePointer?
        defer { if let sourceDB { sqlite3_close(sourceDB) }; if let targetDB { sqlite3_close(targetDB) } }
        guard sqlite3_open_v2(source.path, &sourceDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              sqlite3_open_v2(temporary.path, &targetDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let sourceHandle = sourceDB, let targetHandle = targetDB else { throw BackupError.cannotOpen }
        sqlite3_busy_timeout(sourceHandle, 3_000)
        sqlite3_busy_timeout(targetHandle, 3_000)
        guard let backup = sqlite3_backup_init(targetHandle, "main", sourceHandle, "main") else { throw BackupError.cannotCopy }
        let status = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard status == SQLITE_DONE, finish == SQLITE_OK else { throw BackupError.cannotCopy }
        // backup 会继承 WAL 标志；独立副本需切回 DELETE，避免只读恢复依赖不存在的 -wal。
        guard sqlite3_exec(targetHandle, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
            throw BackupError.cannotCopy
        }
        guard sqlite3_close(targetHandle) == SQLITE_OK else { throw BackupError.cannotCopy }
        targetDB = nil
        try validate(temporary)
        // 不替换已有保护副本；并行 extension 先完成时复用它。
        do { try manager.moveItem(at: temporary, to: destination) }
        catch {
            guard manager.fileExists(atPath: destination.path) else { throw error }
            try validate(destination)
        }
        try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        let digest = SHA256.hash(data: try Data(contentsOf: destination)).map { String(format: "%02x", $0) }.joined()
        try digest.write(to: destination.appendingPathExtension("sha256"), atomically: true, encoding: .utf8)
    }

    static func validate(_ file: URL) throws {
        var database: OpaquePointer?
        defer { if let database { sqlite3_close(database) } }
        guard sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { throw BackupError.cannotOpen }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA quick_check", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw BackupError.invalidSnapshot }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0), String(cString: value) == "ok" else {
            throw BackupError.invalidSnapshot
        }
        let checksum = file.appendingPathExtension("sha256")
        if FileManager.default.fileExists(atPath: checksum.path) {
            let expected = try String(contentsOf: checksum, encoding: .utf8)
            let actual = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw BackupError.invalidSnapshot }
        }
    }

    static func factCounts(_ file: URL) throws -> [String: Int] {
        var database: OpaquePointer?
        defer { if let database { sqlite3_close(database) } }
        guard sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { throw BackupError.cannotOpen }
        sqlite3_exec(database, "BEGIN", nil, nil, nil)
        defer { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) }
        var counts: [String: Int] = [:]
        for table in ["ZENTRY", "ZMEDIA", "ZCHILDPROFILE", "ZMILESTONE", "ZHEALTHRECORD", "ZTIMECAPSULE", "ZVOICEMEMO", "ZVOICENOTE", "ZCOMMENT", "ZFAMILYMEMBER", "ZVACCINERECORD", "ZGROWTHMEASUREMENT"] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "SELECT count(*) FROM \(table)", -1, &statement, nil) == SQLITE_OK,
                  let statement else { throw BackupError.invalidSnapshot }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { throw BackupError.invalidSnapshot }
            counts[table] = Int(sqlite3_column_int64(statement, 0))
        }
        return counts
    }
}
