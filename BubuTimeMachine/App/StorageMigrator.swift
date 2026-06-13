import Foundation
import OSLog
import SQLite3

// MARK: - 私有沙盒 → App Group 共享容器 迁移
/// 老用户的 SwiftData store 与媒体文件可能在 SwiftData 默认 Application Support，
/// 也可能在早期迁移后的私有 Documents；引入 App Group 后必须搬到共享容器，
/// 否则 Widget / Live Activity 读不到、且老用户数据「消失」。
///
/// 安全纪律（数据是用户 30 年的记忆，绝不能丢）：
/// - **幂等**：用 UserDefaults 标记完成；若目标缺失或更旧，仍会自愈。
/// - **不删源**：迁移成功也保留旧文件（仅标记完成），万一新容器出问题可手动回退。
/// - **失败不致命**：任一步失败只记日志、不抛错、不删任何东西；下次启动重试。
/// - **store 三件套**：SQLite 的 `.store` / `.store-wal` / `.store-shm` 一并搬。
enum StorageMigrator {
    private static let log = Logger(subsystem: "com.bubu.timemachine", category: "StorageMigrator")
    private static let doneKey = "bubu.storage.migratedToAppGroup.v3"
    private static let storeSuffixes = ["", "-wal", "-shm"]

    private struct StoreCandidate {
        let label: String
        let url: URL
        let stats: StoreStats
    }

    private struct StoreStats {
        let childProfiles: Int
        let entries: Int
        let milestones: Int
        let media: Int
        let fileBytes: Int64

        var score: Int64 {
            Int64(childProfiles) * 1_000_000
            + Int64(entries) * 10_000
            + Int64(milestones) * 100
            + Int64(media) * 10
            + fileBytes / 1024
        }
    }

    /// 在 App 启动早期、创建 ModelContainer 之前调用。
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard

        // App Group 还没配好（拿不到共享容器）：本次跳过，等签名就绪后下次启动再迁。
        guard BubuStorage.isUsingAppGroup else {
            log.notice("App Group 容器不可用，跳过迁移（等 entitlements 配好后重试）")
            return
        }

        let fm = FileManager.default
        let legacyRoot = BubuStorage.legacyDocumentsURL
        let legacyAppSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let container = BubuStorage.containerURL
        let destinationStore = BubuStorage.storeURL

        // 源与目标相同（回退模式下二者都是 Documents）：无需迁移，直接标记完成。
        if legacyRoot.standardizedFileURL == container.standardizedFileURL {
            defaults.set(true, forKey: doneKey)
            return
        }

        var allOK = true
        let destination = makeCandidate(label: "App Group", url: destinationStore, fm: fm)

        // 1) SwiftData store 三件套
        // 真实旧库曾经落在 SwiftData 默认路径 default.store；后续 0A 迁移又引入了
        // Documents/BubuTimeMachine.store。这里按业务表数量选“更完整”的库，避免把 300+ 里程碑
        // 回退成早期 100+ 里程碑。
        let legacyStores = [
            makeCandidate(label: "SwiftData default.store",
                          url: legacyAppSupport.appendingPathComponent("default.store"),
                          fm: fm),
            makeCandidate(label: "Documents BubuTimeMachine.store",
                          url: legacyRoot.appendingPathComponent(BubuStorage.storeFileName),
                          fm: fm)
        ].compactMap { $0 }

        let bestSource = legacyStores.max(by: { $0.stats.score < $1.stats.score })
        let storeNeedsRepair: Bool = {
            guard let bestSource else { return false }
            guard let destination else { return true }
            return bestSource.stats.score > destination.stats.score
        }()
        let mediaNeedsRepair = ["Media", "Thumbnails"].contains { dirName in
            directoryNeedsCopy(
                srcDir: legacyRoot.appendingPathComponent(dirName, isDirectory: true),
                dstDir: container.appendingPathComponent(dirName, isDirectory: true),
                fm: fm
            )
        }

        if defaults.bool(forKey: doneKey), destination != nil, !storeNeedsRepair, !mediaNeedsRepair {
            return
        }

        if let bestSource, storeNeedsRepair {
            if let destination {
                if bestSource.stats.score > destination.stats.score {
                    log.notice("App Group store 较旧，备份后用 \(bestSource.label, privacy: .public) 替换")
                    allOK = copyStoreTrio(from: bestSource.url, to: destinationStore,
                                          replacingExisting: true, fm: fm) && allOK
                }
            } else {
                log.notice("迁移 store 到 App Group：\(bestSource.label, privacy: .public)")
                allOK = copyStoreTrio(from: bestSource.url, to: destinationStore,
                                      replacingExisting: false, fm: fm) && allOK
            }
        }

        // 2) 媒体目录：Media / Thumbnails 下逐文件搬（保留已存在的，避免覆盖）
        for dirName in ["Media", "Thumbnails"] {
            let srcDir = legacyRoot.appendingPathComponent(dirName, isDirectory: true)
            let dstDir = container.appendingPathComponent(dirName, isDirectory: true)
            allOK = moveDirectoryContents(srcDir: srcDir, dstDir: dstDir, fm: fm) && allOK
        }

        if allOK {
            defaults.set(true, forKey: doneKey)
            log.notice("存储迁移到 App Group 完成")
        } else {
            // 不标记完成：下次启动重试。旧文件全部保留，数据不丢。
            log.error("存储迁移部分失败，下次启动重试（旧数据已保留）")
        }
    }

    private static func makeCandidate(label: String, url: URL, fm: FileManager) -> StoreCandidate? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        return StoreCandidate(label: label, url: url, stats: inspectStore(at: url, fm: fm))
    }

    private static func inspectStore(at url: URL, fm: FileManager) -> StoreStats {
        let fileBytes = ((try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value) ?? 0
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return StoreStats(childProfiles: 0, entries: 0, milestones: 0, media: 0, fileBytes: fileBytes)
        }
        defer { sqlite3_close(db) }

        return StoreStats(
            childProfiles: tableCount("ZCHILDPROFILE", db: db),
            entries: tableCount("ZENTRY", db: db),
            milestones: tableCount("ZMILESTONE", db: db),
            media: tableCount("ZMEDIA", db: db),
            fileBytes: fileBytes
        )
    }

    private static func tableCount(_ table: String, db: OpaquePointer) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT count(*) FROM \(table);", -1, &statement, nil) == SQLITE_OK,
              let statement else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func copyStoreTrio(from srcBase: URL, to dstBase: URL,
                                      replacingExisting: Bool, fm: FileManager) -> Bool {
        do {
            try fm.createDirectory(at: dstBase.deletingLastPathComponent(), withIntermediateDirectories: true)
            if replacingExisting {
                guard backupStoreTrio(at: dstBase, fm: fm) else { return false }
                for suffix in storeSuffixes {
                    let dst = URL(fileURLWithPath: dstBase.path + suffix)
                    if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                }
            }

            var copied = false
            for suffix in storeSuffixes {
                let src = URL(fileURLWithPath: srcBase.path + suffix)
                let dst = URL(fileURLWithPath: dstBase.path + suffix)
                guard fm.fileExists(atPath: src.path) else { continue }
                if fm.fileExists(atPath: dst.path), !replacingExisting { continue }
                try fm.copyItem(at: src, to: dst)
                copied = true
            }
            return copied
        } catch {
            log.error("迁移 store 失败：\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func backupStoreTrio(at storeURL: URL, fm: FileManager) -> Bool {
        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let backupDir = storeURL.deletingLastPathComponent()
            .appendingPathComponent("MigrationBackups", isDirectory: true)
            .appendingPathComponent(stamp, isDirectory: true)
        do {
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
            for suffix in storeSuffixes {
                let src = URL(fileURLWithPath: storeURL.path + suffix)
                guard fm.fileExists(atPath: src.path) else { continue }
                let dst = backupDir.appendingPathComponent(storeURL.lastPathComponent + suffix)
                try fm.copyItem(at: src, to: dst)
            }
            return true
        } catch {
            log.error("备份 App Group store 失败，已停止替换：\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// 复制单个文件：源不存在视为成功（没什么可搬）；目标已存在则跳过（幂等）。
    private static func copyIfPossible(src: URL, dst: URL, fm: FileManager) -> Bool {
        guard fm.fileExists(atPath: src.path) else { return true }
        if fm.fileExists(atPath: dst.path) { return true }
        do {
            try fm.createDirectory(at: dst.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try fm.copyItem(at: src, to: dst)
            return true
        } catch {
            log.error("迁移文件失败 \(src.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func directoryNeedsCopy(srcDir: URL, dstDir: URL, fm: FileManager) -> Bool {
        guard fm.fileExists(atPath: srcDir.path),
              let srcItems = try? fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil),
              !srcItems.isEmpty else { return false }
        let dstItems = (try? fm.contentsOfDirectory(at: dstDir, includingPropertiesForKeys: nil)) ?? []
        if dstItems.count < srcItems.count { return true }
        return srcItems.contains { src in
            !fm.fileExists(atPath: dstDir.appendingPathComponent(src.lastPathComponent).path)
        }
    }

    /// 搬目录内容（非递归即可，媒体目录是扁平的）。
    private static func moveDirectoryContents(srcDir: URL, dstDir: URL, fm: FileManager) -> Bool {
        guard fm.fileExists(atPath: srcDir.path) else { return true }
        do {
            try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
            let items = try fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil)
            var ok = true
            for src in items {
                let dst = dstDir.appendingPathComponent(src.lastPathComponent)
                ok = copyIfPossible(src: src, dst: dst, fm: fm) && ok
            }
            return ok
        } catch {
            log.error("迁移目录失败 \(srcDir.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
