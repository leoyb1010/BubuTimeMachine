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
    var photoFileNames: [String]
    var recentEntryTitle: String
    var recentEntryNote: String
    var recentEntryDate: Date?
    var recentMoodEmoji: String?
    var latestHeightText: String
    var latestWeightText: String
    var achievedMilestoneCount: Int
    var totalMilestoneCount: Int
    var latestMilestoneTitle: String?
    var latestMilestoneEmoji: String?
    var nextMilestoneTitle: String
    var nextMilestoneEmoji: String
    var monthlyPhotoCount: Int
    var totalEntryCount: Int
    var totalPhotoCount: Int
    var idNumber: String
    /// 小组件渲染用头像数据。只从 App Group 文件读取，读不到时 UI 会自动兜底。
    var avatarImageData: Data?
    /// 最近照片数据，用于大尺寸小组件增加内容密度。读不到不影响主内容。
    var recentPhotoImageData: Data?
    var photoImageData: [Data]

    var milestoneProgress: Double {
        guard totalMilestoneCount > 0 else { return 0 }
        return min(1, Double(achievedMilestoneCount) / Double(totalMilestoneCount))
    }

    var milestoneProgressText: String {
        totalMilestoneCount > 0 ? "\(achievedMilestoneCount)/\(totalMilestoneCount)" : "0/0"
    }

    /// 无档案时的占位。
    static let placeholder = BubuSnapshot(
        name: "布布", birthday: nil, ageText: "等你记录",
        daysSinceBirth: 0, daysUntilBirthday: 0, hasProfile: false,
        recentPhotoFileName: nil, avatarFileName: nil,
        photoFileNames: [],
        recentEntryTitle: "今日时光",
        recentEntryNote: "打开 App 记录一句话，桌面也会慢慢变丰富",
        recentEntryDate: nil,
        recentMoodEmoji: nil,
        latestHeightText: "-- cm",
        latestWeightText: "-- kg",
        achievedMilestoneCount: 0,
        totalMilestoneCount: 0,
        latestMilestoneTitle: nil,
        latestMilestoneEmoji: nil,
        nextMilestoneTitle: "记录新的第一次",
        nextMilestoneEmoji: "✨",
        monthlyPhotoCount: 0,
        totalEntryCount: 0,
        totalPhotoCount: 0,
        idNumber: SharedWidgetSnapshot.defaultIDNumber,
        avatarImageData: nil, recentPhotoImageData: nil, photoImageData: []
    )

    /// 预览/骨架用的样例。
    static let sample = BubuSnapshot(
        name: "布布", birthday: Calendar.current.date(byAdding: .month, value: -23, to: .now),
        ageText: "1岁11个月", daysSinceBirth: 709, daysUntilBirthday: 23,
        hasProfile: true, recentPhotoFileName: nil, avatarFileName: nil,
        photoFileNames: [],
        recentEntryTitle: "今天会拍手啦",
        recentEntryNote: "午睡醒来冲大家笑，还跟着音乐轻轻拍手",
        recentEntryDate: .now,
        recentMoodEmoji: "😄",
        latestHeightText: "82.4 cm",
        latestWeightText: "11.2 kg",
        achievedMilestoneCount: 28,
        totalMilestoneCount: 88,
        latestMilestoneTitle: "第一次拍手",
        latestMilestoneEmoji: "👏",
        nextMilestoneTitle: "第一次说完整句子",
        nextMilestoneEmoji: "💬",
        monthlyPhotoCount: 12,
        totalEntryCount: 186,
        totalPhotoCount: 342,
        idNumber: SharedWidgetSnapshot.defaultIDNumber,
        avatarImageData: nil, recentPhotoImageData: nil, photoImageData: []
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
            photoFileNames: shared.photoFileNames ?? shared.recentPhotoFileName.map { [$0] } ?? [],
            recentEntryTitle: fallback(shared.recentEntryTitle, "今日时光"),
            recentEntryNote: fallback(shared.recentEntryNote, "记录一句话，桌面也会慢慢变丰富"),
            recentEntryDate: shared.recentEntryDate,
            recentMoodEmoji: shared.recentMoodEmoji,
            latestHeightText: measurementText(shared.latestHeightCm, unit: "cm"),
            latestWeightText: measurementText(shared.latestWeightKg, unit: "kg"),
            achievedMilestoneCount: max(0, shared.achievedMilestoneCount ?? 0),
            totalMilestoneCount: max(0, shared.totalMilestoneCount ?? 0),
            latestMilestoneTitle: shared.latestMilestoneTitle,
            latestMilestoneEmoji: shared.latestMilestoneEmoji,
            nextMilestoneTitle: fallback(shared.nextMilestoneTitle ?? shared.latestMilestoneTitle, "记录新的第一次"),
            nextMilestoneEmoji: shared.nextMilestoneEmoji ?? shared.latestMilestoneEmoji ?? "✨",
            monthlyPhotoCount: max(0, shared.monthlyPhotoCount ?? 0),
            totalEntryCount: max(0, shared.totalEntryCount ?? 0),
            totalPhotoCount: max(0, shared.totalPhotoCount ?? 0),
            idNumber: fallback(shared.idNumber, SharedWidgetSnapshot.defaultIDNumber),
            avatarImageData: imageData(fileName: shared.avatarFileName, allowOriginalFallback: true),
            recentPhotoImageData: imageData(fileName: shared.recentPhotoFileName),
            photoImageData: (shared.photoFileNames ?? shared.recentPhotoFileName.map { [$0] } ?? [])
                .prefix(Self.maxPhotoDataCount)
                .compactMap { imageData(fileName: $0) }
        )
    }

    private static func fallback(_ value: String?, _ fallback: String) -> String {
        guard let value else { return fallback }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func measurementText(_ value: Double?, unit: String) -> String {
        guard let value else { return "-- \(unit)" }
        let rounded = (value * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded)) \(unit)"
        }
        return String(format: "%.1f %@", rounded, unit)
    }

    /// 单张图片进内存的上限：WidgetKit 渲染进程约 30MB 总预算，大尺寸时光款会同时读 3 张，
    /// 必须把每张压到很小才不会撞红线导致小组件空白。缩略图本就 <1MB，2MB 已宽裕。
    private static let maxImageBytes = 2 * 1_048_576
    /// 大尺寸最多同时读的照片张数。
    static let maxPhotoDataCount = 3

    /// 读一张图片给小组件用。
    /// - 照片默认只认缩略图目录（原图动辄十几 MB，回退读原图正是撞内存红线、小组件空白的根因）。
    /// - 仅头像允许回退原图（头像文件很小，且需要清晰）。
    private static func imageData(fileName: String?, allowOriginalFallback: Bool = false) -> Data? {
        guard let fileName,
              !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let thumbnailURL = BubuStorage.thumbnailDirectory.appendingPathComponent(fileName)
        if let data = boundedData(from: thumbnailURL) {
            return data
        }

        guard allowOriginalFallback else { return nil }
        let mediaURL = BubuStorage.mediaDirectory.appendingPathComponent(fileName)
        return boundedData(from: mediaURL)
    }

    private static func boundedData(from url: URL) -> Data? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let byteCount = values.fileSize,
           byteCount > maxImageBytes {
            return nil
        }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }
}
