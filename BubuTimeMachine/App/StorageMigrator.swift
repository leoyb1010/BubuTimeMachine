import Foundation
import OSLog
import SQLite3

// MARK: - 私有沙盒 → App Group 共享容器 迁移
/// 老用户的 SwiftData store 与媒体文件可能在 SwiftData 默认 Application Support，
/// 也可能在早期迁移后的私有 Documents；引入 App Group 后必须搬到共享容器，
/// 否则 Widget / Live Activity 读不到、且老用户数据「消失」。
///
/// 安全纪律（数据是用户 30 年的记忆，绝不能丢）：
/// - **幂等**：已有目标库永不替换；仅目标缺失时迁移。
/// - **不删源**：迁移成功也保留旧文件（仅标记完成），万一新容器出问题可手动回退。
/// - **失败保护**：store 迁移失败抛给启动保护模式；媒体失败下次启动重试。
/// - **WAL 一致快照**：SQLite backup 合并已提交日志，完成后才原子发布独立库。
/// `nonisolated`：全部是 FileManager/SQLite/UserDefaults 纯 IO，无 UI、无共享可变状态，
/// 既能在 App.init（MainActor）同步调 store 迁移，也能在 Task.detached 后台跑媒体迁移。
nonisolated enum StorageMigrator {
    private static let log = Logger(subsystem: "com.bubu.timemachine", category: "StorageMigrator")
    // store 与媒体拆成两把独立完成标记：store 同步先行（小、必须在建容器前完成），
    // 媒体后台补搬（可能几 GB，绝不卡启动看门狗）。两者各自幂等自愈、互不阻塞。
    private static let storeDoneKey = "bubu.storage.migratedStoreToAppGroup.v3"
    private static let mediaDoneKey = "bubu.storage.migratedMediaToAppGroup.v3"
    private static let mediaDirNames = ["Media", "Thumbnails"]

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

    /// 在 App 启动早期、创建 ModelContainer 之前【同步】调用。
    /// 在 BubuStoreLoader 的跨进程锁内发布独立 SQLite 快照；
    /// ModelConfiguration 指向共享容器前必须完成，失败则进入保护模式。
    /// 媒体目录（可能几 GB）不在这里搬，改由 migrateMediaIfNeeded() 后台执行。
    static func migrateStoreIfNeeded() throws {
        let defaults = UserDefaults.standard

        // App Group 还没配好（拿不到共享容器）：本次跳过，等签名就绪后下次启动再迁。
        guard BubuStorage.isUsingAppGroup else {
            log.notice("App Group 容器不可用，跳过 store 迁移（等 entitlements 配好后重试）")
            return
        }

        let fm = FileManager.default
        let legacyRoot = BubuStorage.legacyDocumentsURL
        let legacyAppSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let container = BubuStorage.containerURL
        let destinationStore = BubuStorage.storeURL

        // 源与目标相同（回退模式下二者都是 Documents）：无需迁移，直接标记完成。
        if legacyRoot.standardizedFileURL == container.standardizedFileURL {
            defaults.set(true, forKey: storeDoneKey)
            return
        }

        // Even a store containing only health, voice or capsule facts belongs to the user.
        // Never guess that an existing database is safe to replace from four selected tables.
        if fm.fileExists(atPath: destinationStore.path) {
            defaults.set(true, forKey: storeDoneKey)
            return
        }

        let legacyURLs = [
            legacyAppSupport.appendingPathComponent("default.store"),
            legacyRoot.appendingPathComponent(BubuStorage.storeFileName)
        ]
        let legacyStores = legacyURLs.compactMap {
            makeCandidate(label: $0.lastPathComponent, url: $0, fm: fm)
        }
        guard let bestSource = legacyStores.max(by: { $0.stats.score < $1.stats.score }) else {
            // A present but unreadable legacy store is not a fresh installation.
            guard !legacyURLs.contains(where: { fm.fileExists(atPath: $0.path) }) else {
                throw StoreUpgradeBackup.BackupError.cannotOpen
            }
            defaults.set(true, forKey: storeDoneKey)
            return
        }

        _ = try copyStoreIfAbsent(from: bestSource.url, to: destinationStore, fm: fm)
        defaults.set(true, forKey: storeDoneKey)
        log.notice("store 迁移到 App Group 完成，旧库保留")
    }

    /// 媒体目录（Media / Thumbnails，可能几 GB）迁移，改在【后台】执行（App .task 里
    /// Task.detached 调用），绝不阻塞首帧、绝不触发启动看门狗强杀。
    /// 分文件拷贝、拷贝不删源：迁移窗口内新容器还没搬到的文件，MediaStore 读取会自动回退
    /// 旧沙盒目录（见 legacyMediaDirectory / legacyThumbnailDirectory），绝不白图。
    /// 幂等、失败不致命：任一文件失败只记日志、不标记完成，下次启动再补。
    static func migrateMediaIfNeeded() {
        let defaults = UserDefaults.standard

        guard BubuStorage.isUsingAppGroup else {
            log.notice("App Group 容器不可用，跳过媒体迁移（等 entitlements 配好后重试）")
            return
        }

        let fm = FileManager.default
        let legacyRoot = BubuStorage.legacyDocumentsURL
        let container = BubuStorage.containerURL

        // 源与目标相同（回退模式）：无需迁移，直接标记完成。
        if legacyRoot.standardizedFileURL == container.standardizedFileURL {
            defaults.set(true, forKey: mediaDoneKey)
            return
        }

        let mediaNeedsRepair = mediaDirNames.contains { dirName in
            directoryNeedsCopy(
                srcDir: legacyRoot.appendingPathComponent(dirName, isDirectory: true),
                dstDir: container.appendingPathComponent(dirName, isDirectory: true),
                fm: fm
            )
        }

        if defaults.bool(forKey: mediaDoneKey), !mediaNeedsRepair {
            return
        }

        var allOK = true
        // Media / Thumbnails 下逐文件搬（保留已存在的，避免覆盖）
        for dirName in mediaDirNames {
            let srcDir = legacyRoot.appendingPathComponent(dirName, isDirectory: true)
            let dstDir = container.appendingPathComponent(dirName, isDirectory: true)
            allOK = moveDirectoryContents(srcDir: srcDir, dstDir: dstDir, fm: fm) && allOK
        }

        if allOK {
            defaults.set(true, forKey: mediaDoneKey)
            log.notice("媒体迁移到 App Group 完成")
        } else {
            // 不标记完成：下次启动重试。旧文件全部保留，数据不丢。
            log.error("媒体迁移部分失败，下次启动重试（旧数据已保留）")
        }
    }

    private static func makeCandidate(label: String, url: URL, fm: FileManager) -> StoreCandidate? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        guard let stats = inspectStore(at: url, fm: fm) else {
            // 打得开才算「一个可比较的候选」。以前这里在打不开时返回全 0 统计，
            // 结果活库被瞬时锁住/‑shm 建不出时会被低估成空库，让几个月前的旧库赢了打分，
            // 进而把正在用的库整个替换掉。宁可不比较，也不能拿假数据比。
            log.error("store 打不开，本轮不参与迁移比较：\(label, privacy: .public)")
            return nil
        }
        return StoreCandidate(label: label, url: url, stats: stats)
    }

    /// 打不开返回 nil（而不是全 0 统计）——见 makeCandidate 的说明。
    private static func inspectStore(at url: URL, fm: FileManager) -> StoreStats? {
        let fileBytes = ((try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value) ?? 0
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }

        guard let childProfiles = tableCount("ZCHILDPROFILE", db: db),
              let entries = tableCount("ZENTRY", db: db),
              let milestones = tableCount("ZMILESTONE", db: db),
              let media = tableCount("ZMEDIA", db: db) else { return nil }
        return StoreStats(childProfiles: childProfiles, entries: entries, milestones: milestones,
                          media: media, fileBytes: fileBytes)
    }

    private static func tableCount(_ table: String, db: OpaquePointer) -> Int? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT count(*) FROM \(table);", -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// Publish only a complete, WAL-consistent snapshot. Interruption can leave a staging
    /// file, but never a partially copied active store. Call inside BubuStoreLoader's lock.
    @discardableResult
    static func copyStoreIfAbsent(from source: URL, to destination: URL,
                                  fm: FileManager = .default) throws -> Bool {
        guard !fm.fileExists(atPath: destination.path) else { return false }
        // A lone journal may contain recoverable facts. Do not attach it to a different base.
        guard !["-wal", "-shm"].contains(where: {
            fm.fileExists(atPath: destination.path + $0)
        }) else { throw StoreUpgradeBackup.BackupError.invalidSnapshot }
        let staged = destination.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString).migration-partial")
        defer {
            try? fm.removeItem(at: staged)
            try? fm.removeItem(at: staged.appendingPathExtension("sha256"))
        }
        try StoreUpgradeBackup.snapshot(source: source, destination: staged)
        // Recheck after snapshotting; an existing target always wins.
        guard !fm.fileExists(atPath: destination.path) else { return false }
        try fm.moveItem(at: staged, to: destination)
        return true
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
            log.error("迁移文件失败 \(src.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .public)")
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
