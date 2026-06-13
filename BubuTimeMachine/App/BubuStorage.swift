import Foundation

// MARK: - 共享存储根（App Group）
/// 主 App 与各 extension（Widget / Live Activity / Control）共享同一份数据，必须把
/// SwiftData store 与媒体文件放进 App Group 容器，而非各自的私有 Documents 沙盒。
///
/// 设计要点：
/// - **优雅降级**：若 App Group 尚未在 entitlements 配好（开发/签名未就绪），
///   `containerURL` 取不到时回退到 `.documentDirectory`，App 仍能跑、绝不崩。
///   一旦签名配好，自动切到共享容器并触发一次性迁移。
/// - **单一真相**：store 文件名、媒体子目录都集中在此，App 与 extension 引用同一处。
///
/// `nonisolated`：纯 FileManager 计算、无共享可变状态，可从任意隔离域（含 nonisolated 的
/// MediaStore、extension 进程）安全调用。项目默认 actor 隔离是 MainActor，这里显式解除。
nonisolated enum BubuStorage {
    /// App Group 标识。需在主 App + 每个 extension 的 entitlements 中开启同名 group。
    static let appGroupID = "group.com.bubu.timemachine"

    /// SwiftData store 文件名（放在共享容器根）。
    static let storeFileName = "BubuTimeMachine.store"

    /// 共享容器根目录；App Group 未就绪时回退到私有 Documents。
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        // 回退：App Group 未配置时不崩，继续用私有沙盒（与迁移逻辑配合，配好后再搬迁）。
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 是否真正拿到了 App Group 容器（用于判断要不要执行迁移）。
    static var isUsingAppGroup: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    /// SwiftData store 的完整 URL（共享容器根下）。
    static var storeURL: URL {
        containerURL.appendingPathComponent(storeFileName)
    }

    /// 媒体原文件目录（共享容器内）。
    static var mediaDirectory: URL {
        directory(named: "Media")
    }

    /// 缩略图目录（共享容器内）。
    static var thumbnailDirectory: URL {
        directory(named: "Thumbnails")
    }

    /// 旧私有沙盒根（迁移源）。
    static var legacyDocumentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func directory(named name: String) -> URL {
        let fm = FileManager.default
        let dir = containerURL.appendingPathComponent(name, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
