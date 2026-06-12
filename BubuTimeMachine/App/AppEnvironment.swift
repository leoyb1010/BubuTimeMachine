import Foundation
import SwiftData
import Observation

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
    let uploadQueue: UploadQueue
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
        self.uploadQueue = UploadQueue(apiClient: api)
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

    /// App 启动后调用：注入上下文、启动同步层（离线时无副作用）。
    func bootstrap(context: ModelContext) {
        seedMilestonePresetsIfNeeded(context: context)
        migrateVaccineDoneIfNeeded(context: context)
        syncEngine.attach(context: context)
        syncEngine.start()
        ReminderScheduler.shared.refreshIfEnabled(enabled: config.dailyReminderEnabled, context: context)
        installThumbnailBackfill(context: context)
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
            milestone.syncState = .local
            context.insert(milestone)
        }
        try? context.save()
    }

    /// 旧版疫苗打卡（@AppStorage("bubu.vaccine.done") JSON 数组）一次性迁移为结构化 VaccineRecord。
    /// 幂等：migrated 标记防重入；保留旧键以便回滚。接种日取排期 dueDate（不晚于今天），并在 note 注明待确认。
    private func migrateVaccineDoneIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "bubu.vaccine.migrated") else { return }
        defer { defaults.set(true, forKey: "bubu.vaccine.migrated") }

        guard let raw = defaults.string(forKey: "bubu.vaccine.done"),
              let data = raw.data(using: .utf8),
              let doseIds = try? JSONDecoder().decode([String].self, from: data),
              !doseIds.isEmpty else { return }

        let existing = (try? context.fetch(FetchDescriptor<VaccineRecord>())) ?? []
        let existingDoseIds = Set(existing.compactMap(\.doseId))
        let birthday = ((try? context.fetch(FetchDescriptor<ChildProfile>())) ?? []).first?.birthday

        for doseId in doseIds where !existingDoseIds.contains(doseId) {
            guard let dose = VaccineDose.schedule.first(where: { $0.id == doseId }) else { continue }
            let due = birthday.map { dose.dueDate(birthday: $0) } ?? .now
            let record = VaccineRecord(vaccineName: dose.vaccine,
                                       injectedAt: min(due, .now),
                                       source: "migration")
            record.doseId = dose.id
            record.doseLabel = dose.doseLabel
            record.note = "从旧版打卡迁移，具体接种日期请家长确认"
            context.insert(record)
        }
        try? context.save()
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
