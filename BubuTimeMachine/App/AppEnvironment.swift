import Foundation
import SwiftData
import Observation
import OSLog

// MARK: - 全局依赖容器（DI）
/// @Observable 持有全部服务与全局状态，通过 .environment() 注入，便于 Mock 与测试。
/// 接口先行：未配置服务器时装配 Mock；已配置则用真实 PocketBaseClient / BubuAIService。
@Observable
@MainActor
final class AppEnvironment {
    let config: ServerConfig
    private(set) var apiClient: APIClient
    private(set) var aiService: AIService
    let mediaStore: MediaStore
    let thumbnails: ThumbnailProvider
    let syncEngine: SyncEngine
    let crypto: CapsuleCrypto
    let vault: CapsuleVault
    let theme: ThemeManager
    let photoAnalyzer: PhotoAnalyzer
    let locationService: LocationService

    /// 当前身份（成员 id）。nil 表示尚未选择/未完成首启引导。
    var currentMemberId: UUID? {
        didSet {
            if let id = currentMemberId {
                UserDefaults.standard.set(id.uuidString, forKey: Self.memberKey)
            }
        }
    }

    /// 首启引导是否完成。存储属性 + didSet 持久化，保证 SwiftUI 能观察切换。
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardedKey) }
    }

    private static let memberKey = "bubu.current.memberId"
    private static let onboardedKey = "bubu.onboarded"

    init() {
        let config = ServerConfig()
        self.config = config

        // 根据配置选择真实/Mock 客户端
        let api = Self.makeAPIClient(config: config)
        let media = MediaStore()
        self.apiClient = api
        self.aiService = Self.makeAIService(config: config)
        self.mediaStore = media
        self.thumbnails = ThumbnailProvider(store: media)
        self.syncEngine = SyncEngine(apiClient: api, config: config, mediaStore: media)
        let crypto = CapsuleCrypto()
        self.crypto = crypto
        self.vault = CapsuleVault(crypto: crypto, mediaStore: media)
        self.theme = ThemeManager()
        self.photoAnalyzer = PhotoAnalyzer()
        self.locationService = LocationService()

        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardedKey)
        self.currentMemberId = UserDefaults.standard.string(forKey: Self.memberKey)
            .flatMap(UUID.init(uuidString:))
    }

    private static func makeAPIClient(config: ServerConfig) -> APIClient {
        guard config.isConfigured, let url = config.baseURL else { return MockAPIClient() }
        return PocketBaseClient(baseURL: url, identity: config.accountEmail,
                                password: config.accountPassword)
    }

    private static func makeAIService(config: ServerConfig) -> AIService {
        guard config.isAIConfigured, let url = config.aiBaseURL else { return MockAIService() }
        return BubuAIService(baseURL: url, apiKey: config.aiAPIKey)
    }

    /// 注册的一次性数据迁移。后续批次往这里追加即可。
    ///
    /// 【刻意不做】胶囊 v2→v3 自动迁移——不要"顺手"加进来。原因：
    /// v2 密钥仅由 unlockAt+salt(=胶囊 id) 派生，这两项都是公开、随记录同步到全家每台设备的字段，
    /// 因此任何家人设备（含不同 Apple ID）零配置即可打开 v2 历史信。
    /// v3 是真 E2E：密钥=24 词恢复码，只在【同一 Apple ID】的 iCloud 钥匙串同步，跨 Apple ID 的家人
    /// 必须手动录入纸条恢复码才能拿到 key。若把存量 v2 无条件迁到 v3，凡是没录入过恢复码的家人设备
    /// 将【再也打不开这些历史信】——30 年档案的可读性回归，不可接受（情形②，锁死风险）。
    /// 且"迁移=获得 E2E"与"无 key 设备仍可开"本质矛盾，无法两全，故不提供无条件迁移。
    /// v2 残留风险（持自托管服务器原始数据者可推导密钥）在本 App 威胁模型（家庭自托管、离线优先）下较低；
    /// 新信已全部走 v3。如未来确要迁移，须是用户显式触发、且已确认全家设备都已分发恢复码的前提下进行。
    static var dataMigrations: [DataMigration] {
        [
            DataMigration(id: "vaccine-legacy-v1") { try VaccineLegacyMigrator.perform(context: $0) },
            DataMigration(id: "growth-backfill-v1") { try GrowthMeasurementBackfill.perform(context: $0) },
            DataMigration(id: "birthday-normalize-v1") { try BirthdayNormalizationMigrator.perform(context: $0) }
        ]
    }

    /// App 启动后调用：注入上下文、启动同步层（离线时无副作用）。
    func bootstrap(context: ModelContext) {
        seedMilestonePresetsIfNeeded(context: context)
        normalizeMilestonePresets(context: context)
        // 一次性动作统一收编进版本化迁移框架：只在未完成时跑一次，成功才落标记。
        DataMigrationRunner(migrations: Self.dataMigrations).runPendingMigrations(context: context)
        syncEngine.attach(context: context)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-bubu-force-upload-ios-to-cloud") {
            Task { @MainActor in
                let result = await syncEngine.debugForceUploadAllLocalDataToCloud()
                DebugCloudReconciler.record(result)
            }
        } else if ProcessInfo.processInfo.arguments.contains("-bubu-repair-cloud-from-ios") {
            Task { @MainActor in
                await DebugCloudReconciler.rebuildRemoteMilestonesFromLocalUniqueTitles(context: context, config: config)
            }
        } else {
            syncEngine.start()
        }
        #else
        syncEngine.start()
        #endif
        ReminderScheduler.shared.refreshIfEnabled(enabled: config.dailyReminderEnabled, context: context)
        Task { await ReminderScheduler.shared.refreshVaccineReminders(context: context) }
        installThumbnailBackfill(context: context)
        refreshWidgetSnapshot(context: context)
        logStoreIntegrity(context: context)
    }

    /// store 建成、启动装配完成后做一次轻量完整性统计：各主要实体 fetchCount 写入日志。
    /// 只做 SQLite COUNT（微秒级），不加载对象、不阻塞后续启动流程；用于尽早发现"打得开但
    /// 数据异常清零/骤减"这类静默故障（配合 BubuStoreHealth 的打不开保护形成双保险）。
    private func logStoreIntegrity(context: ModelContext) {
        func count<T: PersistentModel>(_ type: T.Type) -> Int {
            (try? context.fetchCount(FetchDescriptor<T>())) ?? -1   // -1 = 该实体统计失败
        }
        Self.storeLog.info(
            """
            store 完整性统计 · 打不开保护=\(BubuStoreHealth.loadFailed, privacy: .public) | \
            Entry=\(count(Entry.self), privacy: .public) Media=\(count(Media.self), privacy: .public) \
            Milestone=\(count(Milestone.self), privacy: .public) FirstTime=\(count(FirstTime.self), privacy: .public) \
            TimeCapsule=\(count(TimeCapsule.self), privacy: .public) VoiceMemo=\(count(VoiceMemo.self), privacy: .public) \
            VoiceNote=\(count(VoiceNote.self), privacy: .public) Comment=\(count(Comment.self), privacy: .public) \
            GrowthMovie=\(count(GrowthMovie.self), privacy: .public) FamilyMember=\(count(FamilyMember.self), privacy: .public) \
            ChildProfile=\(count(ChildProfile.self), privacy: .public) HealthRecord=\(count(HealthRecord.self), privacy: .public) \
            VaccineRecord=\(count(VaccineRecord.self), privacy: .public) \
            GrowthMeasurement=\(count(GrowthMeasurement.self), privacy: .public) \
            FeedEvent=\(count(FeedEvent.self), privacy: .public) PendingDeletion=\(count(PendingDeletion.self), privacy: .public)
            """
        )
    }

    private static let storeLog = Logger(subsystem: "com.bubu.timemachine", category: "StoreIntegrity")

    /// 小组件不直接依赖主 App 进程。把它需要的档案/头像/最近照片写入 App Group defaults，
    /// 避免 WidgetKit 进程直接打开 SwiftData store 失败时显示空白。
    func refreshWidgetSnapshot(context: ModelContext) {
        guard let snapshot = SharedWidgetSnapshot.make(context: context) else { return }
        SharedDefaults.saveWidgetSnapshot(snapshot)
    }

    /// 订阅后台缩略图补齐：把生成的缩略图文件名回填进 SwiftData 的 `Media.thumbnailFileName`，
    /// 下次加载直接命中落盘缩略图，不再降采样原图。
    private func installThumbnailBackfill(context: ModelContext) {
        let handler: (UUID, String) -> Void = { mediaId, fileName in
            let descriptor = FetchDescriptor<Media>(predicate: #Predicate { $0.id == mediaId })
            guard let media = try? context.fetch(descriptor).first,
                  media.thumbnailFileName == nil else { return }
            media.thumbnailFileName = fileName
            try? context.save()
        }
        ThumbnailBackfillBus.shared.drain(handler)
        ThumbnailBackfillBus.shared.onRecord = handler
    }

    private func seedMilestonePresetsIfNeeded(context: ModelContext) {
        guard hasCompletedOnboarding else { return }
        let existing = (try? context.fetch(FetchDescriptor<Milestone>())) ?? []
        let titles = Set(existing.map(\.title))
        for tpl in MilestoneTemplate.presets where !titles.contains(tpl.title) {
            let milestone = Milestone(title: tpl.title, category: tpl.category, emoji: tpl.emoji)
            milestone.syncState = .synced
            context.insert(milestone)
        }
        try? context.save()
    }

    private func normalizeMilestonePresets(context: ModelContext) {
        let milestones = (try? context.fetch(FetchDescriptor<Milestone>())) ?? []
        guard !milestones.isEmpty else { return }
        let presetTitles = Set(MilestoneTemplate.presets.map(\.title))
        var bestByTitle: [String: Milestone] = [:]
        var duplicates: [Milestone] = []

        for milestone in milestones {
            let key = milestone.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            if let best = bestByTitle[key] {
                if milestoneRank(milestone) > milestoneRank(best) {
                    duplicates.append(best)
                    bestByTitle[key] = milestone
                } else {
                    duplicates.append(milestone)
                }
            } else {
                bestByTitle[key] = milestone
            }
        }

        for milestone in milestones where presetTitles.contains(milestone.title) && !milestone.isCustom && !milestone.isAchieved && (milestone.detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            milestone.syncState = .synced
        }
        for duplicate in duplicates {
            context.delete(duplicate)
        }
        try? context.save()
    }

    private func milestoneRank(_ milestone: Milestone) -> Int {
        (milestone.isAchieved ? 1_000 : 0)
        + ((milestone.detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 200 : 0)
        + (milestone.isCustom ? 100 : 0)
        + (milestone.remoteId == nil ? 0 : 20)
        + Int(min(19, max(0, Date.now.timeIntervalSince(milestone.createdAt) / 86_400)))
    }

    /// 设置变更后重建客户端（用户改了服务器地址/账户/AI 开关时调用）。
    func reloadServices(context: ModelContext) {
        let api = Self.makeAPIClient(config: config)
        self.apiClient = api
        self.aiService = Self.makeAIService(config: config)
        syncEngine.setClient(api)
        syncEngine.attach(context: context)
        syncEngine.start()
    }
}

#if DEBUG
@MainActor
private enum DebugCloudReconciler {
    private struct Page: Decodable {
        let items: [[String: JSONValue]]
        let totalPages: Int?
    }

    private enum JSONValue: Decodable {
        case string(String)
        case bool(Bool)
        case number(Double)
        case array([JSONValue])
        case object([String: JSONValue])
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([JSONValue].self) {
                self = .array(value)
            } else {
                self = .object(try container.decode([String: JSONValue].self))
            }
        }

        var string: String? {
            if case .string(let value) = self { return value }
            return nil
        }
    }

    static func rebuildRemoteMilestonesFromLocalUniqueTitles(context: ModelContext, config: ServerConfig) async {
        guard config.isConfigured, let baseURL = config.baseURL else {
            print("BUBU_CLOUD_REPAIR_SKIPPED not_configured")
            return
        }
        var stage = "start"
        do {
            record("BUBU_CLOUD_REPAIR_RUNNING stage=start at=\(Date())")
            stage = "login"
            let token = try await login(baseURL: baseURL, identity: config.accountEmail, password: config.accountPassword)
            stage = "local-dedupe"
            let canonical = try dedupeLocalMilestones(context: context)
            stage = "remote-fetch"
            let remote = try await fetchAll(collection: "milestones", baseURL: baseURL, token: token)
            let remoteByTitle = Dictionary(grouping: remote, by: { cleanTitle($0["title"]?.string ?? "") })
            let remoteUnique = remoteByTitle.keys.filter { !$0.isEmpty }.count
            record("BUBU_CLOUD_REPAIR_RUNNING localUnique=\(canonical.count) remoteRaw=\(remote.count) remoteUnique=\(remoteUnique) at=\(Date())")
            var patched = 0
            var created = 0
            stage = "remote-upload"
            for milestone in canonical {
                let title = cleanTitle(milestone.title)
                if let existing = remoteByTitle[title]?.first, let id = existing["id"]?.string {
                    stage = "remote-patch:\(id)"
                    let record = try await patch(collection: "milestones", id: id, body: milestoneBody(milestone, includeLocalId: false), baseURL: baseURL, token: token)
                    milestone.remoteId = record["id"]?.string ?? id
                    patched += 1
                } else {
                    stage = "remote-create:\(title)"
                    let record = try await post(collection: "milestones", body: milestoneBody(milestone, includeLocalId: true), baseURL: baseURL, token: token)
                    milestone.remoteId = record["id"]?.string
                    created += 1
                }
                milestone.syncState = .synced
            }
            try context.save()
            SharedDefaults.saveWidgetSnapshot(SharedWidgetSnapshot.make(context: context) ?? SharedWidgetSnapshot(
                name: "布布", birthday: nil, recentPhotoFileName: nil, avatarFileName: nil,
                photoFileNames: nil, recentEntryTitle: nil, recentEntryNote: nil, recentEntryDate: nil,
                recentMoodEmoji: nil, latestHeightCm: nil, latestWeightKg: nil,
                achievedMilestoneCount: nil, totalMilestoneCount: canonical.count,
                latestMilestoneTitle: nil, latestMilestoneEmoji: nil,
                nextMilestoneTitle: canonical.first?.title, nextMilestoneEmoji: canonical.first?.emoji,
                monthlyPhotoCount: nil, totalEntryCount: nil, totalPhotoCount: nil,
                idNumber: SharedWidgetSnapshot.defaultIDNumber, updatedAt: .now
            ))
            record("BUBU_CLOUD_REPAIR_DONE localUnique=\(canonical.count) remoteBeforeRaw=\(remote.count) remoteBeforeUnique=\(remoteUnique) patched=\(patched) created=\(created) at=\(Date())")
        } catch {
            record("BUBU_CLOUD_REPAIR_FAILED stage=\(stage) \(error) at=\(Date())")
        }
    }

    static func record(_ message: String) {
        print(message)
        let suite = UserDefaults(suiteName: BubuStorage.appGroupID)
        suite?.set(message, forKey: "bubu.debug.cloudRepairResult")
        suite?.synchronize()
    }

    private static func dedupeLocalMilestones(context: ModelContext) throws -> [Milestone] {
        let milestones = try context.fetch(FetchDescriptor<Milestone>())
        var bestByTitle: [String: Milestone] = [:]
        var duplicates: [Milestone] = []
        for milestone in milestones {
            let title = cleanTitle(milestone.title)
            guard !title.isEmpty else {
                duplicates.append(milestone)
                continue
            }
            milestone.title = title
            if let existing = bestByTitle[title] {
                if rank(milestone) > rank(existing) {
                    duplicates.append(existing)
                    bestByTitle[title] = milestone
                } else {
                    duplicates.append(milestone)
                }
            } else {
                bestByTitle[title] = milestone
            }
        }
        for duplicate in duplicates {
            context.delete(duplicate)
        }
        let canonical = bestByTitle.values.sorted { $0.createdAt < $1.createdAt }
        for milestone in canonical {
            milestone.syncState = .synced
        }
        try context.save()
        return canonical
    }

    private static func rank(_ milestone: Milestone) -> Int {
        (milestone.isAchieved ? 1_000 : 0)
        + ((milestone.detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 200 : 0)
        + (milestone.isCustom ? 100 : 0)
        + (milestone.remoteId == nil ? 0 : 20)
    }

    private static func cleanTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func login(baseURL: URL, identity: String, password: String) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/collections/users/auth-with-password"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["identity": identity, "password": password])
        let (data, response) = try await URLSession.shared.data(for: req)
        try check(response, data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["token"] as? String else {
            throw APIError.server(500, "鉴权响应异常")
        }
        return token
    }

    private static func fetchAll(collection: String, baseURL: URL, token: String) async throws -> [[String: JSONValue]] {
        var page = 1
        var all: [[String: JSONValue]] = []
        while true {
            var comps = URLComponents(url: baseURL.appendingPathComponent("api/collections/\(collection)/records"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [
                URLQueryItem(name: "perPage", value: "200"),
                URLQueryItem(name: "page", value: "\(page)")
            ]
            var req = URLRequest(url: comps.url!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: req)
            try check(response, data)
            let parsed = try JSONDecoder().decode(Page.self, from: data)
            all.append(contentsOf: parsed.items)
            if page >= (parsed.totalPages ?? 1) || parsed.items.isEmpty { break }
            page += 1
        }
        return all
    }

    private static func post(collection: String, body: [String: Any], baseURL: URL, token: String) async throws -> [String: JSONValue] {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/collections/\(collection)/records"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try check(response, data)
        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    }

    private static func patch(collection: String, id: String, body: [String: Any], baseURL: URL, token: String) async throws -> [String: JSONValue] {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/collections/\(collection)/records/\(id)"))
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try check(response, data)
        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    }

    private static func milestoneBody(_ milestone: Milestone, includeLocalId: Bool) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = [
            "title": milestone.title,
            "category": milestone.category,
            "emoji": milestone.emoji,
            "isCustom": milestone.isCustom,
            "clientUpdatedAt": iso.string(from: Date())
        ]
        if includeLocalId {
            body["localId"] = milestone.id.uuidString
        }
        if let detail = milestone.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
            body["detail"] = detail
        }
        if let happenedAt = milestone.happenedAt {
            body["happenedAt"] = iso.string(from: happenedAt)
        }
        if let ageDescription = milestone.ageDescription {
            body["ageDescription"] = ageDescription
        }
        return body
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw APIError.server(http.statusCode, message)
        }
    }
}
#endif
