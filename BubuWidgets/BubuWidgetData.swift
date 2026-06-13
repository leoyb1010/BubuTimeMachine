import Foundation

// MARK: - 小组件数据快照
/// Widget 在自己的进程里跑，需要从 App Group 共享 store 读出当前布布状态，
/// 打包成一个轻量、Sendable 的快照供各 family 渲染。读失败时返回占位快照（绝不崩、绝不空白）。
struct BubuSnapshot: Sendable {
    var name: String
    var birthday: Date?
    var ageText: String
    var daysSinceBirth: Int
    var daysUntilBirthday: Int
    var hasProfile: Bool
    /// 最近一张照片的本地文件名（成长墙/那年今日用），可空。
    var recentPhotoFileName: String?
    /// 布布头像本地文件名（小组件圆形头像），可空。
    var avatarFileName: String?
    /// 小组件渲染用头像数据。只从 App Group 文件读取，读不到时 UI 会自动兜底。
    var avatarImageData: Data?
    /// 最近照片数据，用于大尺寸小组件增加内容密度。读不到不影响主内容。
    var recentPhotoImageData: Data?

    /// 无档案时的占位。
    static let placeholder = BubuSnapshot(
        name: "布布", birthday: nil, ageText: "等你记录",
        daysSinceBirth: 0, daysUntilBirthday: 0, hasProfile: false,
        recentPhotoFileName: nil, avatarFileName: nil,
        avatarImageData: nil, recentPhotoImageData: nil
    )

    /// 预览/骨架用的样例。
    static let sample = BubuSnapshot(
        name: "布布", birthday: Calendar.current.date(byAdding: .month, value: -23, to: .now),
        ageText: "1岁11个月", daysSinceBirth: 709, daysUntilBirthday: 23,
        hasProfile: true, recentPhotoFileName: nil, avatarFileName: nil,
        avatarImageData: nil, recentPhotoImageData: nil
    )
}

// MARK: - 快照读取
enum BubuWidgetData {
    /// 桌面小组件只读 App Group 里的轻量 JSON 快照。不要在 WidgetKit 渲染进程里打开 SwiftData，
    /// 否则共享库锁、schema 迁移或后台权限波动都可能让整张小组件空白。
    static func loadSnapshot() -> BubuSnapshot {
        if let shared = SharedDefaults.widgetSnapshot,
           shared.hasRenderableContent {
            return makeSnapshot(from: shared)
        }
        return .placeholder
    }

    private static func makeSnapshot(from shared: SharedWidgetSnapshot) -> BubuSnapshot {
        let now = Date.now
        let birthday = shared.birthday
        return BubuSnapshot(
            name: shared.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "布布" : shared.name,
            birthday: birthday,
            ageText: birthday.map { AgeCalculator.ageDescription(birthday: $0, at: now) } ?? "等你记录",
            daysSinceBirth: birthday.map { AgeCalculator.daysSinceBirth(birthday: $0, at: now) } ?? 0,
            daysUntilBirthday: birthday.map { AgeCalculator.daysUntilNextBirthday(birthday: $0, from: now) } ?? 0,
            hasProfile: birthday != nil,
            recentPhotoFileName: shared.recentPhotoFileName,
            avatarFileName: shared.avatarFileName,
            avatarImageData: imageData(fileName: shared.avatarFileName),
            recentPhotoImageData: imageData(fileName: shared.recentPhotoFileName)
        )
    }

    private static func imageData(fileName: String?) -> Data? {
        guard let fileName,
              !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let thumbnailURL = BubuStorage.thumbnailDirectory.appendingPathComponent(fileName)
        if let data = boundedData(from: thumbnailURL) {
            return data
        }

        let mediaURL = BubuStorage.mediaDirectory.appendingPathComponent(fileName)
        return boundedData(from: mediaURL)
    }

    private static func boundedData(from url: URL) -> Data? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let byteCount = values.fileSize,
           byteCount > 18 * 1_048_576 {
            return nil
        }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }
}
