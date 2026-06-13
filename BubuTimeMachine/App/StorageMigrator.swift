import Foundation
import OSLog

// MARK: - 私有沙盒 → App Group 共享容器 迁移
/// 老用户的 SwiftData store 与媒体文件原本在私有 Documents；引入 App Group 后必须搬到共享容器，
/// 否则 Widget / Live Activity 读不到、且老用户数据「消失」。
///
/// 安全纪律（数据是用户 30 年的记忆，绝不能丢）：
/// - **幂等**：用 UserDefaults 标记完成，重复调用直接返回；目标已存在则跳过。
/// - **不删源**：迁移成功也保留旧文件（仅标记完成），万一新容器出问题可手动回退。
/// - **失败不致命**：任一步失败只记日志、不抛错、不删任何东西；下次启动重试。
/// - **store 三件套**：SQLite 的 `.store` / `.store-wal` / `.store-shm` 一并搬。
enum StorageMigrator {
    private static let log = Logger(subsystem: "com.bubu.timemachine", category: "StorageMigrator")
    private static let doneKey = "bubu.storage.migratedToAppGroup.v1"

    /// 在 App 启动早期、创建 ModelContainer 之前调用。
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard

        // 已迁移过：直接返回。
        if defaults.bool(forKey: doneKey) { return }

        // App Group 还没配好（拿不到共享容器）：本次跳过，等签名就绪后下次启动再迁。
        guard BubuStorage.isUsingAppGroup else {
            log.notice("App Group 容器不可用，跳过迁移（等 entitlements 配好后重试）")
            return
        }

        let fm = FileManager.default
        let legacyRoot = BubuStorage.legacyDocumentsURL
        let container = BubuStorage.containerURL

        // 源与目标相同（回退模式下二者都是 Documents）：无需迁移，直接标记完成。
        if legacyRoot.standardizedFileURL == container.standardizedFileURL {
            defaults.set(true, forKey: doneKey)
            return
        }

        var allOK = true

        // 1) SwiftData store 三件套
        let legacyStore = legacyRoot.appendingPathComponent(BubuStorage.storeFileName)
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: legacyStore.path + suffix)
            let dst = URL(fileURLWithPath: BubuStorage.storeURL.path + suffix)
            allOK = moveIfPossible(src: src, dst: dst, fm: fm) && allOK
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

    /// 移动单个文件：源不存在视为成功（没什么可搬）；目标已存在则跳过（幂等）。
    private static func moveIfPossible(src: URL, dst: URL, fm: FileManager) -> Bool {
        guard fm.fileExists(atPath: src.path) else { return true }
        if fm.fileExists(atPath: dst.path) { return true }
        do {
            try fm.createDirectory(at: dst.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            // 用 copy 而非 move：先确保目标写成功，再不删源（安全优先）。
            try fm.copyItem(at: src, to: dst)
            return true
        } catch {
            log.error("迁移文件失败 \(src.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
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
                ok = moveIfPossible(src: src, dst: dst, fm: fm) && ok
            }
            return ok
        } catch {
            log.error("迁移目录失败 \(srcDir.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
