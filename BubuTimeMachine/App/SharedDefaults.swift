import Foundation
import OSLog
import SwiftData

nonisolated struct SharedWidgetSnapshot: Codable, Sendable {
    var name: String
    var birthday: Date?
    var recentPhotoFileName: String?
    var avatarFileName: String?
    var photoFileNames: [String]?
    var recentEntryTitle: String?
    var recentEntryNote: String?
    var recentEntryDate: Date?
    var recentMoodEmoji: String?
    var latestHeightCm: Double?
    var latestWeightKg: Double?
    var achievedMilestoneCount: Int?
    var totalMilestoneCount: Int?
    var latestMilestoneTitle: String?
    var latestMilestoneEmoji: String?
    var nextMilestoneTitle: String?
    var nextMilestoneEmoji: String?
    var monthlyPhotoCount: Int?
    var totalEntryCount: Int?
    var totalPhotoCount: Int?
    var idNumber: String?
    var updatedAt: Date

    var hasRenderableContent: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || birthday != nil
        || recentPhotoFileName != nil
        || avatarFileName != nil
    }
}

extension SharedWidgetSnapshot {
    static let defaultIDNumber = "BUBU20240522"

    @MainActor
    static func make(context: ModelContext) -> SharedWidgetSnapshot? {
        guard let profile = try? context.fetch(FetchDescriptor<ChildProfile>()).first else {
            return nil
        }

        let entries = recentEntries(context: context)
        let photoFileNames = recentPhotoFileNames(from: entries, limit: 4)
        let recentEntry = entries.first
        let measurements = recentMeasurements(context: context)
        let healthRecords = recentHealthRecords(context: context)
        let milestones = allMilestones(context: context)
        let achieved = milestones.filter(\.isAchieved)
        let latestMilestone = achieved.sorted {
            ($0.happenedAt ?? .distantPast) > ($1.happenedAt ?? .distantPast)
        }.first
        let nextMilestone = milestones
            .filter { !$0.isAchieved }
            .sorted { $0.createdAt < $1.createdAt }
            .first

        return SharedWidgetSnapshot(
            name: profile.name,
            birthday: profile.birthday,
            recentPhotoFileName: photoFileNames.first,
            avatarFileName: profile.avatarMediaFileName,
            photoFileNames: photoFileNames.isEmpty ? nil : photoFileNames,
            recentEntryTitle: clean(recentEntry?.title, maxLength: 18),
            recentEntryNote: clean(recentEntry?.firstPersonNote, maxLength: 46) ?? clean(recentEntry?.note, maxLength: 46),
            recentEntryDate: recentEntry?.happenedAt,
            recentMoodEmoji: recentEntry?.mood?.emoji,
            latestHeightCm: latestHeight(from: measurements, healthRecords: healthRecords),
            latestWeightKg: latestWeight(from: measurements, healthRecords: healthRecords),
            achievedMilestoneCount: achieved.count,
            totalMilestoneCount: milestones.count,
            latestMilestoneTitle: clean(latestMilestone?.title, maxLength: 18),
            latestMilestoneEmoji: latestMilestone?.emoji,
            nextMilestoneTitle: clean(nextMilestone?.title, maxLength: 18),
            nextMilestoneEmoji: nextMilestone?.emoji,
            monthlyPhotoCount: monthlyPhotoCount(from: entries),
            totalEntryCount: totalEntryCount(context: context),
            totalPhotoCount: totalPhotoCount(context: context),
            idNumber: defaultIDNumber,
            updatedAt: .now
        )
    }

    @MainActor
    private static func recentEntries(context: ModelContext) -> [Entry] {
        var descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.happenedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    private static func recentMeasurements(context: ModelContext) -> [GrowthMeasurement] {
        var descriptor = FetchDescriptor<GrowthMeasurement>(
            sortBy: [SortDescriptor(\.measuredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 12
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    private static func recentHealthRecords(context: ModelContext) -> [HealthRecord] {
        var descriptor = FetchDescriptor<HealthRecord>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 80
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    private static func allMilestones(context: ModelContext) -> [Milestone] {
        (try? context.fetch(FetchDescriptor<Milestone>())) ?? []
    }

    @MainActor
    private static func totalEntryCount(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { !$0.isArchived })
        return ((try? context.fetch(descriptor)) ?? []).count
    }

    @MainActor
    private static func totalPhotoCount(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { !$0.isArchived })
        return ((try? context.fetch(descriptor)) ?? [])
            .reduce(0) { $0 + $1.media.filter { $0.type == .photo && ($0.thumbnailFileName != nil || $0.localFileName != nil) }.count }
    }

    private static func recentPhotoFileNames(from entries: [Entry], limit: Int) -> [String] {
        var names: [String] = []
        var seen = Set<String>()
        for entry in entries {
            for media in entry.media where media.type == .photo {
                guard let name = media.thumbnailFileName ?? media.localFileName,
                      !seen.contains(name) else { continue }
                seen.insert(name)
                names.append(name)
                if names.count >= limit { return names }
            }
        }
        return names
    }

    private static func monthlyPhotoCount(from entries: [Entry]) -> Int {
        let cal = Calendar.current
        guard let start = cal.dateInterval(of: .month, for: .now)?.start else { return 0 }
        return entries
            .filter { $0.happenedAt >= start }
            .reduce(0) { $0 + $1.media.filter { $0.type == .photo }.count }
    }

    private static func clean(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }

    private static func latestNonNil(_ values: [Double]) -> Double? {
        values.first
    }

    private static func latestHeight(from measurements: [GrowthMeasurement], healthRecords: [HealthRecord]) -> Double? {
        latestNonNil(measurements.compactMap(\.heightCm))
        ?? healthRecords.compactMap { GrowthMeasurementExtractor.value(.height, from: $0) }.first
    }

    private static func latestWeight(from measurements: [GrowthMeasurement], healthRecords: [HealthRecord]) -> Double? {
        latestNonNil(measurements.compactMap(\.weightKg))
        ?? healthRecords.compactMap { GrowthMeasurementExtractor.value(.weight, from: $0) }.first
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
