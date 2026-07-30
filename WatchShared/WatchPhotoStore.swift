import Foundation

// MARK: - 手表侧回忆照片缓存
/// 手表 App 收到照片包后落这里，手表 App 与表盘复杂功能扩展共读（同一台手表的两个进程，
/// 靠手表本地 App Group 共享，跟 iPhone 的 App Group 无关）。
///
/// 为什么要 LRU 上限：手表存储很小，而回忆池会随着记录变多不断换新。
/// 不设上限的话，几个月下来这个目录会堆几百张再也不会被引用的旧图。
/// 上限 40 张（当前一次下发 20 段，留一倍余量给「刚换过一轮、旧的还没被引用完」的窗口）。
public nonisolated enum WatchPhotoStore {

    /// 缓存张数上限。淘汰按最后访问时间（读到就 touch），真正 LRU 而非先进先出——
    /// 时光机会反复拧回同几段回忆，那几张不该因为存得早就被删。
    public static let maxCachedPhotos = 40

    private static var directory: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WatchSnapshotStore.appGroup) else { return nil }
        let dir = container.appendingPathComponent("MemoryPhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: 读

    /// 取一张照片。命中即 touch 修改时间，供 LRU 判断「最近用过」。
    public static func data(for fileName: String?) -> Data? {
        guard let fileName, !fileName.isEmpty, let dir = directory else { return nil }
        let url = dir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    public static var count: Int {
        guard let dir = directory else { return 0 }
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).count
    }

    // MARK: 写

    /// 落一整包照片，然后按 LRU 修剪到上限。
    /// 返回真正落盘成功的文件名，调用方可据此判断哪些回忆有图。
    @discardableResult
    public static func save(_ items: [(name: String, data: Data)]) -> [String] {
        guard let dir = directory else { return [] }
        var saved: [String] = []
        for item in items {
            // 文件名来自另一台设备，必须挡掉路径穿越：只允许最后一段，且不能是 . / ..
            let safe = (item.name as NSString).lastPathComponent
            guard !safe.isEmpty, safe != ".", safe != ".." else { continue }
            let url = dir.appendingPathComponent(safe)
            guard (try? item.data.write(to: url, options: .atomic)) != nil else { continue }
            saved.append(safe)
        }
        prune()
        return saved
    }

    /// 修剪到 `maxCachedPhotos`：按修改时间升序删最旧的。
    public static func prune(keeping keep: Set<String> = []) {
        guard let dir = directory else { return }
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dir,
                                                    includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        guard urls.count > maxCachedPhotos else { return }
        let sorted = urls.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
        var overflow = urls.count - maxCachedPhotos
        for url in sorted where overflow > 0 {
            // keep 里的是当前回忆序列还在引用的，宁可暂时超一点也不删正在用的图。
            if keep.contains(url.lastPathComponent) { continue }
            try? fm.removeItem(at: url)
            overflow -= 1
        }
    }

    public static func clear() {
        guard let dir = directory else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}
