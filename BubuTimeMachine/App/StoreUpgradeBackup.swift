import Foundation
import CoreData
import CryptoKit
import SQLite3
import OSLog

/// V1→V2 之前保留包含 WAL 最新内容的独立 SQLite 快照。备份失败则不开始迁移。
nonisolated enum StoreUpgradeBackup {
    enum BackupError: Error { case cannotOpen, cannotCopy, invalidSnapshot }
    private static let log = Logger(subsystem: "com.bubu.timemachine", category: "StoreTransferRecovery")
    private static let factTables = [
        "ZENTRY", "ZMEDIA", "ZCHILDPROFILE", "ZMILESTONE", "ZHEALTHRECORD", "ZTIMECAPSULE",
        "ZVOICEMEMO", "ZVOICENOTE", "ZCOMMENT", "ZFAMILYMEMBER", "ZVACCINERECORD", "ZGROWTHMEASUREMENT"
    ]
    private static let storeSuffixes = ["", "-wal", "-shm"]

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

    /// iOS 换机可能只恢复 App Group 的 Documents，而遗漏根目录活动 store。
    /// 仅在活动库缺失或经十二类事实表确认全空时，用升级保护副本自愈；非空库永不覆盖。
    @discardableResult
    static func restoreTransferredBackupIfNeeded(store: URL) throws -> Bool {
        writeRecoveryTrace(store: store, stage: "begin")
        do {
            return try performTransferredBackupRestore(store: store)
        } catch {
            writeRecoveryTrace(store: store, stage: "error", error: String(describing: error))
            throw error
        }
    }

    private static func performTransferredBackupRestore(store: URL) throws -> Bool {
        let manager = FileManager.default
        let backup = destination(for: store)
        guard manager.fileExists(atPath: backup.path) else {
            log.notice("换机恢复跳过：没有升级保护副本")
            writeRecoveryTrace(store: store, stage: "skipped-no-backup")
            return false
        }
        try validateDatabase(backup)
        let backupCounts = try factCounts(backup)
        guard backupCounts.values.contains(where: { $0 > 0 }) else {
            log.notice("换机恢复跳过：保护副本为空")
            writeRecoveryTrace(store: store, stage: "skipped-empty-backup", backup: backupCounts)
            return false
        }

        let originalChecksumMatches = checksumMatches(backup)
        let auditMatches = auditCounts(for: store) == backupCounts
        writeRecoveryTrace(store: store, stage: "backup-validated", backup: backupCounts,
                           checksumMatches: originalChecksumMatches, auditMatches: auditMatches)
        log.notice("换机保护副本通过 SQLite 校验：sha=\(originalChecksumMatches) audit=\(auditMatches) entry=\(backupCounts["ZENTRY"] ?? -1) media=\(backupCounts["ZMEDIA"] ?? -1)")
        guard originalChecksumMatches || auditMatches else {
            log.error("换机恢复拒绝：SHA 与升级审计均不匹配")
            throw BackupError.invalidSnapshot
        }

        let storeExists = manager.fileExists(atPath: store.path)
        if storeExists {
            let currentCounts = try factCounts(store)
            writeRecoveryTrace(store: store, stage: "current-counted", backup: backupCounts,
                               current: currentCounts, checksumMatches: originalChecksumMatches,
                               auditMatches: auditMatches)
            log.notice("换机活动库现状：profile=\(currentCounts["ZCHILDPROFILE"] ?? -1) entry=\(currentCounts["ZENTRY"] ?? -1) media=\(currentCounts["ZMEDIA"] ?? -1) milestone=\(currentCounts["ZMILESTONE"] ?? -1)")
            // 首启空壳会自动写入 130 条未达成的系统里程碑；它们不是用户事实。
            // 只要除此之外十一类事实全空，仍可安全恢复。任何真实记录/档案/健康数据存在都不覆盖。
            guard currentCounts.allSatisfy({ $0.key == "ZMILESTONE" || $0.value == 0 }) else {
                log.notice("换机恢复跳过：活动库已有用户事实")
                writeRecoveryTrace(store: store, stage: "skipped-nonempty-current",
                                   backup: backupCounts, current: currentCounts)
                return false
            }
            let safety = backup.deletingLastPathComponent()
                .appendingPathComponent("empty-store-before-transfer-restore.store")
            try snapshot(source: store, destination: safety)
        }

        let restored = backup.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString).restore-partial")
        defer {
            try? manager.removeItem(at: restored)
            try? manager.removeItem(at: restored.appendingPathExtension("sha256"))
        }
        try snapshot(source: backup, destination: restored)
        guard try factCounts(restored) == backupCounts else { throw BackupError.invalidSnapshot }

        // 换机过程可能改写 SQLite 头部而不改变逻辑内容。旧 hash 留档，再为已由审计数量
        // 与 quick_check 双重确认的副本刷新 sidecar，保证中途崩溃后下一次仍能继续迁移。
        if !originalChecksumMatches {
            let checksum = backup.appendingPathExtension("sha256")
            let transferred = checksum.appendingPathExtension("before-device-transfer")
            if manager.fileExists(atPath: checksum.path), !manager.fileExists(atPath: transferred.path) {
                try manager.copyItem(at: checksum, to: transferred)
            }
            try digest(of: backup).write(to: checksum, atomically: true, encoding: .utf8)
        }
        try validate(backup)

        do {
            for suffix in storeSuffixes {
                let file = URL(fileURLWithPath: store.path + suffix)
                if manager.fileExists(atPath: file.path) { try manager.removeItem(at: file) }
            }
            try manager.copyItem(at: restored, to: store)
            try validateDatabase(store)
            guard try factCounts(store) == backupCounts else { throw BackupError.invalidSnapshot }
            log.notice("换机保护副本已恢复为活动库")
            writeRecoveryTrace(store: store, stage: "restored", backup: backupCounts,
                               current: backupCounts, checksumMatches: true, auditMatches: true)
            return true
        } catch {
            // 空库已有独立快照；有内容的库从未进入此分支。保留所有恢复材料并进入保护模式。
            throw error
        }
    }

    static func validate(_ file: URL) throws {
        try validateDatabase(file)
        let checksum = file.appendingPathExtension("sha256")
        if FileManager.default.fileExists(atPath: checksum.path) {
            guard checksumMatches(file) else { throw BackupError.invalidSnapshot }
        }
    }

    private static func validateDatabase(_ file: URL) throws {
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
    }

    static func factCounts(_ file: URL) throws -> [String: Int] {
        var database: OpaquePointer?
        defer { if let database { sqlite3_close(database) } }
        guard sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { throw BackupError.cannotOpen }
        sqlite3_exec(database, "BEGIN", nil, nil, nil)
        defer { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) }
        var counts: [String: Int] = [:]
        for table in factTables {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "SELECT count(*) FROM \(table)", -1, &statement, nil) == SQLITE_OK,
                  let statement else { throw BackupError.invalidSnapshot }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { throw BackupError.invalidSnapshot }
            counts[table] = Int(sqlite3_column_int64(statement, 0))
        }
        return counts
    }

    private static func checksumMatches(_ file: URL) -> Bool {
        let checksum = file.appendingPathExtension("sha256")
        guard let expected = try? String(contentsOf: checksum, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let actual = try? digest(of: file) else { return false }
        return expected == actual
    }

    private static func digest(of file: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
    }

    private static func auditCounts(for store: URL) -> [String: Int]? {
        let file = store.deletingLastPathComponent()
            .appendingPathComponent("Documents/upgrade-audit-initial.json")
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let before = object["before"] as? [String: Any] else { return nil }
        var counts: [String: Int] = [:]
        for table in factTables {
            guard let value = before[table] as? NSNumber else { return nil }
            counts[table] = value.intValue
        }
        return counts
    }

    private static func writeRecoveryTrace(
        store: URL,
        stage: String,
        backup: [String: Int]? = nil,
        current: [String: Int]? = nil,
        checksumMatches: Bool? = nil,
        auditMatches: Bool? = nil,
        error: String? = nil
    ) {
        var payload: [String: Any] = ["stage": stage, "timestamp": Date().timeIntervalSince1970]
        if let backup { payload["backup"] = backup }
        if let current { payload["current"] = current }
        if let checksumMatches { payload["checksumMatches"] = checksumMatches }
        if let auditMatches { payload["auditMatches"] = auditMatches }
        if let error { payload["error"] = error }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        let file = store.deletingLastPathComponent()
            .appendingPathComponent("Documents/transfer-recovery-trace.json")
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
