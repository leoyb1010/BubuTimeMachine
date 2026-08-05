import Foundation
import OSLog
import SwiftData
import WidgetKit

/// 桌面「时光机」小组件的一条片段：一张照片 + 当时的一句话。
/// 小组件轮播这一组，让桌面每半小时换一段回忆，而不是永远钉着最新那一条。
nonisolated struct SharedMoment: Codable, Sendable, Hashable {
    var photoFileName: String
    var title: String?
    var note: String?
    var date: Date
    var moodEmoji: String?
    /// 「那年今日」标记：同月同日的旧记录，轮到它时小组件会打上徽章。
    var isOnThisDay: Bool = false
}

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
    /// 时光机照片池（最多 30 段）：近期 + 那年今日 + 历史随机，各占一部分。
    /// 桌面照片墙一屏就要 9 张，还要能整墙轮换，池子必须够大。
    var moments: [SharedMoment]?
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
            monthlyPhotoCount: monthlyPhotoCount(context: context),
            totalEntryCount: totalEntryCount(context: context),
            totalPhotoCount: totalPhotoCount(context: context),
            idNumber: defaultIDNumber,
            moments: buildMoments(context: context, entries: entries),
            updatedAt: .now
        )
    }

    /// 组装时光机轮播池：**近期 4 段 + 那年今日 + 更早的随机若干**，去重后最多 12 段。
    /// 只取近期会让桌面永远是同一批照片；掺进历史与「那年今日」，
    /// 桌面才真的像一台时光机——每隔半小时翻出一段可能已经忘了的回忆。
    @MainActor
    private static func buildMoments(context: ModelContext, entries: [Entry]) -> [SharedMoment]? {
        var pool: [SharedMoment] = []
        var seenPhotos = Set<String>()

        /// 每条记录最多取 2 张：只取首图的话，多图记录的其余照片永远上不了墙，
        /// 照片墙会显得内容很少。
        func append(_ entry: Entry, isOnThisDay: Bool, maxPerEntry: Int = 2) {
            var taken = 0
            // 先把要用的字段全部取成局部量再拼装：`??` 的右侧是 autoclosure，
            // 直接写 `media.thumbnailFileName ?? media.localFileName` 会让闭包捕获模型对象，
            // Release（whole-module）下被判成「main actor 闭包捕获 task-isolated 值」而编译失败。
            let entryTitle = clean(entry.title, maxLength: 18)
            let entryFirstPerson = clean(entry.firstPersonNote, maxLength: 40)
            let entryNote = clean(entry.note, maxLength: 40)
            let entryDate = entry.happenedAt
            let entryMood = entry.mood?.emoji
            let caption = entryFirstPerson ?? entryNote
            for media in entry.media where media.type == .photo {
                guard taken < maxPerEntry else { break }
                let thumbName = media.thumbnailFileName
                let fileName = media.localFileName
                guard let name = thumbName ?? fileName,
                      !seenPhotos.contains(name) else { continue }
                seenPhotos.insert(name)
                taken += 1
                pool.append(SharedMoment(
                    photoFileName: name,
                    title: entryTitle,
                    note: caption,
                    date: entryDate,
                    moodEmoji: entryMood,
                    isOnThisDay: isOnThisDay))
            }
        }

        // ① 近期：桌面要能反映「刚发生的事」
        for entry in entries.prefix(10) { append(entry, isOnThisDay: false) }

        // ② 那年今日：同月同日的旧记录，最有回忆价值，优先掺进来
        let cal = Calendar.current
        let todayMonth = cal.component(.month, from: .now)
        let todayDay = cal.component(.day, from: .now)
        let all = allEntriesWithPhotos(context: context)
        for entry in all where cal.component(.month, from: entry.happenedAt) == todayMonth
            && cal.component(.day, from: entry.happenedAt) == todayDay
            && !cal.isDateInToday(entry.happenedAt) {
            append(entry, isOnThisDay: true)
            if pool.count >= 18 { break }
        }

        // ③ 历史随机：按天数分散取样，避免全挤在某一段时间
        if pool.count < 30, all.count > pool.count {
            let stride = max(1, all.count / 30)
            for i in Swift.stride(from: 0, to: all.count, by: stride) {
                append(all[i], isOnThisDay: false)
                if pool.count >= 30 { break }
            }
        }
        return pool.isEmpty ? nil : Array(pool.prefix(30))
    }

    /// 带照片的全部未归档记录（按时间倒序）。取样用，上限 400 条防大库开销。
    @MainActor
    private static func allEntriesWithPhotos(context: ModelContext) -> [Entry] {
        var descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.happenedAt, order: .reverse)])
        descriptor.fetchLimit = 400
        let entries = (try? context.fetch(descriptor)) ?? []
        return entries.filter { entry in entry.media.contains { $0.type == .photo } }
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

    /// 总记录数：用 SQLite COUNT（fetchCount）而非全表取回内存 count，进前台不再随数据量变卡。
    @MainActor
    private static func totalEntryCount(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { !$0.isArchived })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// 总照片数：直接对 Media 做谓词 COUNT（不加载对象、不遍历每条 Entry 的关系）。
    /// 只用 Media 自有字段（typeRaw / 缩略图 / 本地文件名）作条件，避免不稳的关系穿透谓词。
    /// 说明：软删除（isArchived）记录里的照片会被计入，与旧实现（仅统计未归档）略有出入；
    /// 归档是罕见的软删操作，桌面「总照片」是概览数字，为换取单条 COUNT 的性能与稳定，接受此微小口径差异。
    @MainActor
    private static func totalPhotoCount(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Media>(predicate: #Predicate {
            $0.typeRaw == "photo" && ($0.thumbnailFileName != nil || $0.localFileName != nil)
        })
        return (try? context.fetchCount(descriptor)) ?? 0
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

    /// 本月照片数：按「本月」直接取当月未归档记录（谓词按 happenedAt 圈定，集合很小），再累加其照片。
    /// 旧实现从「最近 40 条记录」里数，多人家庭一个月轻松超过 40 条 → 偏小失真；这里不再受 40 条截断。
    @MainActor
    private static func monthlyPhotoCount(context: ModelContext) -> Int {
        let cal = Calendar.current
        guard let start = cal.dateInterval(of: .month, for: .now)?.start else { return 0 }
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { !$0.isArchived && $0.happenedAt >= start }
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        return entries.reduce(0) { $0 + $1.media.filter { $0.type == .photo }.count }
    }

    private static func clean(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }

    private static func latestHeight(from measurements: [GrowthMeasurement], healthRecords: [HealthRecord]) -> Double? {
        GrowthMeasurementResolver.latestValue(.height, from: measurements)
        ?? healthRecords.compactMap { GrowthMeasurementExtractor.value(GrowthMeasurementExtractor.Metric.height, from: $0) }.first
    }

    private static func latestWeight(from measurements: [GrowthMeasurement], healthRecords: [HealthRecord]) -> Double? {
        GrowthMeasurementResolver.latestValue(.weight, from: measurements)
        ?? healthRecords.compactMap { GrowthMeasurementExtractor.value(GrowthMeasurementExtractor.Metric.weight, from: $0) }.first
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
    private static let sleepStartKey = "bubu.shared.sleepStartedAt"
    private static let widgetSnapshotKey = "bubu.shared.widgetSnapshot.v1"
    private static let pendingRecordKey = "bubu.shared.pendingRecord"

    /// 控制中心/Action Button 的「记录」控件按下时置 true，主 App 启动/前台消费后拉起快速记录。
    static var pendingRecord: Bool {
        get { suite?.bool(forKey: pendingRecordKey) ?? false }
        set { suite?.set(newValue, forKey: pendingRecordKey) }
    }

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

    /// 进行中的哄睡开始时刻（nil = 没在哄）。持久化：杀掉 App 重开也能收尾。
    static var sleepStartedAt: Date? {
        get { suite?.object(forKey: sleepStartKey) as? Date }
        set {
            if let newValue { suite?.set(newValue, forKey: sleepStartKey) }
            else { suite?.removeObject(forKey: sleepStartKey) }
        }
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
        // 孩子姓名不进系统日志：unified log 会随 sysdiagnose/诊断分享外带。只记存在性。
        log.notice("widget 快照已写入 hasName=\(!snapshot.name.isEmpty) birthday=\(snapshot.birthday != nil) avatar=\(snapshot.avatarFileName != nil) photo=\(snapshot.recentPhotoFileName != nil)")
    }

    /// 无 UI 写入路径（App Intents / 小组件交互按钮 / Siri）的「写后钩子」：
    /// 落库后重建并存盘 widget 快照，再请求 WidgetKit 重载。
    /// 否则：交互按钮所在的 widget 虽被系统自动 reload，却读到旧 JSON 快照；其它 widget 要等下次开 App 才更新。
    /// 主 App 前台的写入走 AppEnvironment.refreshWidgetSnapshot + WidgetRefresher（带合并节流），无需再调此钩子。
    @MainActor
    static func refreshWidgetsAfterWrite(context: ModelContext) {
        if let snapshot = SharedWidgetSnapshot.make(context: context) {
            saveWidgetSnapshot(snapshot)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
