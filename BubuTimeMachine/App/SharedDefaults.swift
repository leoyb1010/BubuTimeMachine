import Foundation
import OSLog

nonisolated struct SharedWidgetSnapshot: Codable, Sendable {
    var name: String
    var birthday: Date?
    var recentPhotoFileName: String?
    var avatarFileName: String?
    var updatedAt: Date

    var hasRenderableContent: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || birthday != nil
        || recentPhotoFileName != nil
        || avatarFileName != nil
    }
}

// MARK: - 跨进程共享的轻量配置（App Group UserDefaults）
/// 主 App 的 ServerConfig 存在 `UserDefaults.standard`，extension（Intent/Widget）读不到。
/// 这里把 extension 真正需要的少量字段（当前身份、布布名字）镜像到 App Group suite，
/// 让 Intent/Widget 也能拿到。只放「读多写少、非敏感」的小字段，不放账号密码等。
nonisolated enum SharedDefaults {
    private static let log = Logger(subsystem: "com.bubu.timemachine", category: "SharedDefaults")

    // 计算属性而非 static let：UserDefaults 非 Sendable，Swift 6 严格并发下不能作为可变静态存储；
    // 每次取一个实例即可（UserDefaults 内部已线程安全）。
    private static var suite: UserDefaults? { UserDefaults(suiteName: BubuStorage.appGroupID) }

    private static let roleKey = "bubu.shared.role"
    private static let childNameKey = "bubu.shared.childName"
    private static let widgetSnapshotKey = "bubu.shared.widgetSnapshot.v1"

    // MARK: 当前家庭身份

    static var currentRole: FamilyRole {
        get {
            let raw = suite?.string(forKey: roleKey) ?? FamilyRole.mama.rawValue
            return FamilyRole(rawValue: raw) ?? .mama
        }
        set { suite?.set(newValue.rawValue, forKey: roleKey) }
    }

    // MARK: 布布名字

    static var childName: String {
        get { suite?.string(forKey: childNameKey) ?? "布布" }
        set { suite?.set(newValue, forKey: childNameKey) }
    }

    /// 主 App 启动 / 配置变更时调用，把当前值同步进共享 suite。
    static func mirror(role: FamilyRole, childName: String) {
        currentRole = role
        self.childName = childName
    }

    // MARK: Widget 快照

    static var widgetSnapshot: SharedWidgetSnapshot? {
        guard let data = suite?.data(forKey: widgetSnapshotKey) else { return nil }
        return try? JSONDecoder().decode(SharedWidgetSnapshot.self, from: data)
    }

    static func saveWidgetSnapshot(_ snapshot: SharedWidgetSnapshot) {
        guard let suite else {
            log.error("App Group UserDefaults 不可用，widget 快照未写入")
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else {
            log.error("widget 快照编码失败")
            return
        }
        suite.set(data, forKey: widgetSnapshotKey)
        suite.synchronize()
        log.notice("widget 快照已写入 name=\(snapshot.name, privacy: .public) birthday=\(snapshot.birthday != nil) avatar=\(snapshot.avatarFileName != nil) photo=\(snapshot.recentPhotoFileName != nil)")
    }
}
