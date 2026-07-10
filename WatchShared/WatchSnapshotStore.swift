import Foundation

// MARK: - 手表本地快照存储（手表 App 与手表复杂功能扩展共用）
/// iPhone 的 App Group 不会同步到手表，所以手表侧另建一个本地 App Group，
/// 手表 App 收到快照后写这里，复杂功能扩展读这里。两者是同一台手表上的两个进程。
public nonisolated enum WatchSnapshotStore {
    public static let appGroup = "group.com.bubu.timemachine.watch"
    private static let key = "bubu.watch.snapshot.local"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    public static func save(_ snapshot: WatchSnapshot) {
        guard let data = WatchLink.encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    public static func load() -> WatchSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return WatchLink.decode(WatchSnapshot.self, from: data)
    }
}
