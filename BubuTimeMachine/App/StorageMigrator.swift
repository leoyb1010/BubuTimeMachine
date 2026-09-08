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
/// `nonisolated`：全部是 FileManager/SQLite/UserDefaults 纯 IO，无 UI、无共享可变状态，
/// 既能在 App.init（MainActor）同步调 store 迁移，也能在 Task.detached 后台跑媒体迁移。
nonisolated enum StorageMigrator {
    private static let log = Logger(subsystem: "com.bubu.timemachine", category: "StorageMigrator")
    // store 与媒体拆成两把独立完成标记：store 同步先行（小、必须在建容器前完成），
    // 媒体后台补搬（可能几 GB，绝不卡启动看门狗）。两者各自幂等自愈、互不阻塞。
    private static let storeDoneKey = "bubu.storage.migratedStoreToAppGroup.v3"
    private static let mediaDoneKey = "bubu.storage.migratedMediaToAppGroup.v3"
    private static let storeSuffixes = ["", "-wal", "-shm"]
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

        /// 四张业务表全空。只有「打得开且确实为空」才算数——
        /// 打不开的库压根不会生成 StoreStats（见 inspectStore 返回可选）。
        var isEmpty: Bool {
            childProfiles == 0 && entries == 0 && milestones == 0 && media == 0
        }

        var score: Int64 {
            Int64(childProfiles) * 1_000_000
            + Int64(entries) * 10_000
            + Int64(milestones) * 100
            + Int64(media) * 10
            + fileBytes / 1024
        }
    }

    /// 在 App 启动早期、创建 ModelContainer 之前【同步】调用。
    /// 只搬 SwiftData store 三件套（.store / .store-wal / .store-shm）——文件小、且必须在
    /// ModelConfiguration 指向共享容器前就位，否则容器会指向旧/空 store。
    /// 媒体目录（可能几 GB）不在这里搬，改由 migrateMediaIfNeeded() 后台执行。
    static func migrateStoreIfNeeded() {
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

        var allOK = true
        let destination = makeCandidate(label: "App Group", url: destinationStore, fm: fm)

        // SwiftData store 三件套
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
        let destinationFileExists = fm.fileExists(atPath: destinationStore.path)

        // 一次性迁移的正确语义：**目标不存在才搬**。
        //
        // 以前这里是「谁分高谁赢」的启发式，两条路径都能把正在用的库删掉换成旧库：
        //   A) 活库瞬时打不开（被别的进程持锁 / -shm 建不出）→ 分数塌成文件字节数 →
        //      旧沙盒里一条儿童档案就值一百万分，稳赢。
        //   B) SwiftData 走 WAL，最近写入还在 -wal 里没落主文件 → 活库被系统性低估，
        //      早已 checkpoint 完毕的冻结旧库被系统性高估。
        // 它确实会先备份到 MigrationBackups/，但 App 里没有任何恢复入口，
        // 用户看到的就是「这半年的记录全没了」。
        //
        // 唯一保留的替换场景：目标**打得开、且四张业务表确认全空**（上次迁移中断留下的空壳），
        // 而源确实有数据。这个判断必须建立在一次成功的 open 之上，不能靠猜。
        let destinationIsVerifiedEmpty = destination?.stats.isEmpty ?? false
        let sourceHasData = !(bestSource?.stats.isEmpty ?? true)
        let storeNeedsRepair: Bool = {
            guard bestSource != nil else { return false }
            if !destinationFileExists { return true }
            return destinationIsVerifiedEmpty && sourceHasData
        }()

        if defaults.bool(forKey: storeDoneKey), destinationFileExists, !storeNeedsRepair {
            return
        }

        if let bestSource, storeNeedsRepair {
            if destinationFileExists {
                log.notice("App Group store 确认为空壳，备份后用 \(bestSource.label, privacy: .public) 补齐")
                allOK = copyStoreTrio(from: bestSource.url, to: destinationStore,
                                      replacingExisting: true, fm: fm) && allOK
            } else {
                log.notice("迁移 store 到 App Group：\(bestSource.label, privacy: .public)")
                allOK = copyStoreTrio(from: bestSource.url, to: destinationStore,
                                      replacingExisting: false, fm: fm) && allOK
            }
        }

        if allOK {
            defaults.set(true, forKey: storeDoneKey)
            log.notice("store 迁移到 App Group 完成")
        } else {
            // 不标记完成：下次启动重试。旧文件全部保留，数据不丢。
            log.error("store 迁移失败，下次启动重试（旧数据已保留）")
        }
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
