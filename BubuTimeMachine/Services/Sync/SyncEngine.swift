import Foundation
import SwiftData
import Observation
import OSLog
import UIKit
import CryptoKit

// MARK: - 同步引擎
/// 双向收敛：本地未同步的 Entry/Media 推送到 PocketBase；远端变更拉回本地。
/// 离线优先：未配置或断网时静默保持离线，本地全功能可用；联网后自动补传。
@Observable
@MainActor
final class SyncEngine {
    enum ConnectionState: Sendable {
        case offline, connecting, online
    }

    nonisolated static let log = Logger(subsystem: "com.bubu.timemachine", category: "Sync")

    private(set) var connectionState: ConnectionState = .offline
    private(set) var lastSyncedAt: Date?
    private(set) var isSyncing = false
    private(set) var pendingCount: Int = 0
    private(set) var totalPendingAtStart: Int = 0
    private(set) var processedThisRun: Int = 0
    private(set) var currentSyncLabel: String?
    private(set) var currentUploadProgress: Double?
    private(set) var lastFailureReason: String?
    private(set) var lastLargeFileNotice: String?
    struct CollectionProgress: Identifiable {
        var id: String
        var received: Int = 0
        var deleted: Int = 0
        var state: String = "核对中"
    }
    private(set) var collectionProgress: [String: CollectionProgress] = [:]
    /// 可自愈的瞬时波动提示（平和措辞、非报红）。仅当连续多轮仍失败才显示。
    private(set) var softNotice: String?
    /// 需要人处理的条目（文件丢了 / 服务器持续拒收）。它们不再排队、不再拖慢退避，列在同步中心。
    private(set) var attentionItems: [SyncLedger.AttentionItem] = []
    /// SSE 长连是否在线：在线时前台轮询退到慢速兜底，断开再回到 30 秒（D4-04）。
    private(set) var realtimeConnected = false

    // 瞬时失败的轮内标记与跨轮连发计数（避免偶发抖动立刻报红）。
    private var softFailureThisRun = false
    private var softFailureStreak = 0

    var syncProgress: Double? {
        guard totalPendingAtStart > 0 else { return nil }
        let uploadFraction = currentUploadProgress ?? 0
        return min(1, (Double(processedThisRun) + uploadFraction) / Double(totalPendingAtStart))
    }

    private var apiClient: APIClient
    private var clientScope: String
    private var runningCheckpointGeneration: String?
    private let config: ServerConfig
    private let mediaStore: MediaStore
    private var modelContext: ModelContext?
    private var syncTask: Task<Void, Never>?
    private var activeSyncID: UUID?
    private let syncRuns = SyncRunGate()
    private let ledger: SyncLedger
    private var willSaveObserver: NSObjectProtocol?
    /// 本轮是否真的改动了本地数据：没变就不重建小组件快照 / Spotlight（D4-05）。
    private var changedThisRun = false
    /// 媒体缺文件全表扫描的脏标记：没有新媒体、上次也没缺文件时跳过每轮 2000+ 次 stat（D4-04）。
    private var downloadScanNeeded = true
    /// 服务端 404 的文件地址：永久缺失，本次进程内不再重试、不算软失败（否则 10 个坏文件堵死所有下载、每轮报失败）。
    /// ponytail: 只存内存，重启后重试一次；重新上传会换文件名 = 新地址，自然解除。
    private var missingRemoteFiles = Set<String>()
    private var lastFullDownloadScanAt = Date.distantPast
    private static let downloadScanSafetyInterval: TimeInterval = 30 * 60
    /// 最近一次排期的时刻：冷启动 bootstrap 和 scene .active 各调一次 start()，不能连跑两轮。
    private var lastScheduledAt = Date.distantPast
    private var needsAnotherSync = false
    private var pollTimer: Timer?
    /// SSE 实时监听任务（R4 F-5）：远端一有写入就触发增量同步，家人的照片秒到。
    private var realtimeTask: Task<Void, Never>?

    // MARK: - 增量游标（按集合持久化）
    /// 任一集合拉取失败则该集合游标不推进，下次补拉；游标回退 60 秒容忍时钟偏差（合并幂等）。
    private static let cursorOverlap: TimeInterval = 60

    private var checkpointGeneration: String {
        UserDefaults.standard.string(forKey: "bubu.sync.checkpointGeneration") ?? "initial"
    }

    private static func scope(for config: ServerConfig) -> String {
        let account = config.accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(config.baseURLString)|\(account)"
    }

    private var isCurrentRun: Bool {
        !Task.isCancelled && clientScope == Self.scope(for: config) &&
        runningCheckpointGeneration == checkpointGeneration
    }

    private func checkRunValidity() throws {
        guard isCurrentRun else { throw CancellationError() }
    }

    private func checkpointKey(for collection: String) -> String {
        let digest = SHA256.hash(data: Data(clientScope.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(digest):\(collection)"
    }

    private func cursor(for collection: String) throws -> Date? {
        guard let context = modelContext else { return nil }
        return try SyncCheckpoint.read(key: checkpointKey(for: collection), generation: checkpointGeneration, in: context)
    }

    init(apiClient: APIClient, config: ServerConfig, mediaStore: MediaStore, ledger: SyncLedger = .shared) {
        self.apiClient = apiClient
        self.clientScope = Self.scope(for: config)
        self.config = config
        self.mediaStore = mediaStore
        self.ledger = ledger
        self.attentionItems = ledger.attentionItems.filter { !$0.skipped }
    }

    /// 设置变更后替换底层客户端并重连。
    func setClient(_ client: APIClient) {
        // 包括未保存在 syncTask 中的 BGTask 和强制补传；旧任务仍持许可直到协作退出。
        syncRuns.invalidate()
        activeSyncID = nil
        syncTask?.cancel()
        syncTask = nil
        pollTimer?.invalidate()
        pollTimer = nil
        // 取消旧服务器的 SSE 长连：否则 startRealtime 的 guard realtimeTask==nil 会挡住重建，
        // 改了服务器地址后仍连着旧服务器（S-P2）。置 nil 让 start() 能对新客户端重开长连。
        realtimeTask?.cancel()
        realtimeTask = nil
        self.apiClient = client
        self.clientScope = Self.scope(for: config)
    }

    /// 进后台时调用：停掉轮询，省电；回前台 start() 会重启。
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        realtimeTask?.cancel()
        realtimeTask = nil
        realtimeConnected = false
    }
    /// 由 App 注入主上下文（同步需要读写 SwiftData）。
    func attach(context: ModelContext) {
        self.modelContext = context
        installEditStamping()
        refreshAttention()
        refreshPendingCount()
    }

    /// 监听主线程上所有 ModelContext 的保存：凡是被标成 `.local` 的可同步对象，记下真实编辑时间，
    /// 推送时作为 LWW 版本号（D9-02）。后台 context 的写入（手表/Intent）不在主线程，退化为推送时刻。
    private func installEditStamping() {
        guard willSaveObserver == nil else { return }
        let ledger = self.ledger
        willSaveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.willSave, object: nil, queue: nil) { note in
            guard Thread.isMainThread else { return }
            // 已确认在主线程同步回调：context 不会跨线程，这里只是让编译器接受这次交接。
            nonisolated(unsafe) let object = note.object
            MainActor.assumeIsolated {
                guard let context = object as? ModelContext else { return }
                ledger.recordEdits(in: context)
            }
        }
    }

    // MARK: 需要处理的条目

    /// 从账本刷新「需要处理」列表，并清掉本地已不存在的条目。
    func refreshAttention() {
        if let context = modelContext {
            ledger.pruneAttention { item in Self.localObjectExists(collection: item.collection, id: item.localId, in: context) }
        }
        attentionItems = ledger.attentionItems.filter { !$0.skipped }
    }

    /// 同步中心「重试」：移出名单，立即排一轮。
    func retryAttention(_ item: SyncLedger.AttentionItem) {
        ledger.resolveAttention(item.key)
        refreshAttention()
        refreshPendingCount()
        syncNow()
    }

    /// 同步中心「放弃上传」：内容留在本机，不再排队也不再报错。
    func skipAttention(_ item: SyncLedger.AttentionItem) {
        ledger.skipAttention(item.key)
        refreshAttention()
        refreshPendingCount()
    }

    static func localObjectExists(collection: String, id: UUID, in context: ModelContext) -> Bool {
        func exists<T: PersistentModel>(_ type: T.Type, _ predicate: Predicate<T>) -> Bool {
            var descriptor = FetchDescriptor<T>(predicate: predicate)
            descriptor.fetchLimit = 1
            return ((try? context.fetchCount(descriptor)) ?? 1) > 0
        }
        switch collection {
        case "entries": return exists(Entry.self, #Predicate { $0.id == id })
        case "media": return exists(Media.self, #Predicate { $0.id == id })
        case "milestones": return exists(Milestone.self, #Predicate { $0.id == id })
        case "firsttimes": return exists(FirstTime.self, #Predicate { $0.id == id })
        case "members": return exists(FamilyMember.self, #Predicate { $0.id == id })
        case "childprofile": return exists(ChildProfile.self, #Predicate { $0.id == id })
        case "healthrecords": return exists(HealthRecord.self, #Predicate { $0.id == id })
        case "vaccinerecords": return exists(VaccineRecord.self, #Predicate { $0.id == id })
        case "growthmeasurements": return exists(GrowthMeasurement.self, #Predicate { $0.id == id })
        case "comments": return exists(Comment.self, #Predicate { $0.id == id })
        case "voicenotes": return exists(VoiceNote.self, #Predicate { $0.id == id })
        case "voicememos": return exists(VoiceMemo.self, #Predicate { $0.id == id })
        case "timecapsules": return exists(TimeCapsule.self, #Predicate { $0.id == id })
        default: return true
        }
    }

    /// 单条推送失败的统一出口：本地硬错误（文件丢了）立刻进「需要处理」；
    /// 服务器对这一条持续拒收（非网络、非账号问题）连续 3 轮后进；其余照旧记为本轮失败。
    private func notePushFailure(_ error: Error, collection: String, id: UUID, label: String, item: String) {
        let hard = Self.isHardLocalFailure(error)
        if hard || Self.isPermanentItemFailure(error, item: item),
           ledger.noteFailure(collection: collection, id: id, label: label,
                              reason: Self.safeUserMessage(for: error), immediate: hard) {
            refreshAttention()
            return
        }
        recordFailure(error, item: item)
    }

    static func isHardLocalFailure(_ error: Error) -> Bool {
        guard case APIError.network(let message) = error else { return false }
        return hardLocalKeywords.contains { message.contains($0) }
    }

    /// 只属于这一条的永久拒收：4xx（除 401/403/408/429 这类账号/限流问题、除缺可选集合）和超大文件。
    static func isPermanentItemFailure(_ error: Error, item: String) -> Bool {
        if isMissingOptionalServerCollection(error, item: item) { return false }
        switch error {
        case APIError.fileTooLarge: return true
        case APIError.server(let code, _): return (400...499).contains(code) && ![401, 403, 408, 429].contains(code)
        default: return false
        }
    }

    /// 推送一条的版本信息：账本里的真实编辑时间；恢复重传（create-only）时没有编辑点就用创建时间，
    /// 普通推送没有编辑点（升级前就脏了 / 后台 context 写入）退化为推送时刻（旧行为）。
    private func outgoingVersion(_ collection: String, _ id: UUID, createdAt: Date) -> (editedAt: Date, createOnly: Bool) {
        let key = SyncLedger.key(collection, id)
        let createOnly = ledger.isRecovery(key)
        return (ledger.editedAt(key) ?? (createOnly ? createdAt : .now), createOnly)
    }

    /// 服务器带回的不是本次写入的版本，而是它保留的远端版本：
    /// 普通推送 = 远端编辑时间比本次推送新（家人后改的）；恢复模式 = 服务器本来就有。调用方应采用远端内容。
    nonisolated static func remoteVersionWasKept(sent: Date, returned: Date?, createOnly: Bool) -> Bool {
        guard let returned else { return false }
        // clientUpdatedAt 以毫秒精度往返，留 2ms 容差避免把自己刚写的版本误判为「远端更新」。
        if createOnly { return abs(returned.timeIntervalSince(sent)) > 0.002 }
        return returned.timeIntervalSince(sent) > 0.002
    }

    /// 推送确认后：本地已 synced 才清账本，期间又被改过的保留编辑点等下一轮。
    private func finishPushBookkeeping(_ collection: String, _ id: UUID, state: SyncState) {
        guard state == .synced else { return }
        ledger.clearAfterPush(SyncLedger.key(collection, id))
    }

    // MARK: 游标契约迁移（本机时钟 → 服务器 updated）
    /// 所有增量集合，用于升级时一次性清空旧游标。
    private static let cursorCollections = [
        "entries", "media", "milestones", "firsttimes", "members", "childprofile",
        "healthrecords", "vaccinerecords", "growthmeasurements", "comments",
        "voicenotes", "voicememos", "timecapsules",
    ]
    private static let cursorMigrationFlagKey = "bubu.sync.cursor.atomicCheckpoint.v3"

    /// 联合游标升级后全量补拉一次，恢复旧时间戳分页可能遗漏的记录和墓碑。
    /// 一次性清空所有游标，让升级后首轮做一次全量拉取（localId 去重 + merge 见已 synced 幂等，无重复无覆盖），
    /// 从此游标全部以服务器时钟重建，保证「不丢窗口」。
    private func migrateCursorsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.cursorMigrationFlagKey) else { return }
        for collection in Self.cursorCollections {
            defaults.removeObject(forKey: "bubu.sync.cursor.\(collection)")
        }
        defaults.set(true, forKey: Self.cursorMigrationFlagKey)
    }

    /// 清空所有集合的增量游标。换服务器 / 恢复备份后调用：否则旧游标残留会让新服务器的
    /// 历史记录拉不全（游标已越过它们的 updated 时间）。清空后下一轮做一次全量拉取（localId 去重 + merge 幂等）。
    static func resetAllCursors() {
        let defaults = UserDefaults.standard
        defaults.set(UUID().uuidString, forKey: "bubu.sync.checkpointGeneration")
        for collection in cursorCollections {
            defaults.removeObject(forKey: "bubu.sync.cursor.\(collection)")
        }
    }

    /// 启动同步层：已配置则连接 + 首次全量推拉 + 起轮询；否则保持离线。
    /// 冷启动时 bootstrap 与 scene 进入 .active 会各调一次：5 秒内已排过一轮就不再追加（D4-06）。
    func start() {
        guard !BubuStoreHealth.loadFailed else {
            connectionState = .offline
            return
        }
        migrateCursorsIfNeeded()
        guard config.isConfigured else {
            connectionState = .offline
            pollTimer?.invalidate()
            pollTimer = nil
            refreshPendingCount()
            return
        }
        startPolling()
        startRealtime()
        guard syncTask == nil, Date.now.timeIntervalSince(lastScheduledAt) > 5 else { return }
        scheduleSync()
    }

    /// SSE 长连：收到远端写入信号→去抖 2 秒→增量同步。
    /// 长连在线时轮询退到 5 分钟慢速兜底（以前 SSE 连着也每 30 秒全量 14 个请求 + 全表扫媒体）；
    /// 断开立即回到 30 秒并补一轮，避免断线期间漏掉家人的更新。
    private func startRealtime() {
        guard realtimeTask == nil, let stream = apiClient.realtimeStream() else { return }
        realtimeTask = Task { [weak self] in
            var pending = false
            for await signal in stream {
                guard let self, !Task.isCancelled else { return }
                switch signal {
                case .connected:
                    self.setRealtimeConnected(true)
                case .disconnected:
                    self.setRealtimeConnected(false)
                case .change:
                    if pending { continue }   // 去抖：短时间多条事件只跑一轮
                    pending = true
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(2))
                        pending = false
                        self?.syncNow()
                    }
                }
            }
            self?.setRealtimeConnected(false)
        }
    }

    private func setRealtimeConnected(_ connected: Bool) {
        guard realtimeConnected != connected else { return }
        realtimeConnected = connected
        if pollTimer != nil { schedulePollTimer(after: currentPollInterval) }
        // 刚断线：长连期间若有事件丢失，立刻补一轮；刚连上：订阅前的变更也补一轮。
        if config.isConfigured { scheduleSync() }
    }

    /// 手动触发一次同步（设置页/下拉刷新/首页「重试」可调）。
    /// 人主动点了就把退避清零：他很可能刚把 WiFi 连上或刚把家里的服务器插好电，
    /// 这时候还按 8 分钟的退避节奏等下去是说不过去的。
    func syncNow() {
        guard !BubuStoreHealth.loadFailed else {
            connectionState = .offline
            return
        }
        guard config.isConfigured else {
            connectionState = .offline
            refreshPendingCount()
            return
        }
        consecutiveFailures = 0
        if pollTimer != nil { schedulePollTimer(after: currentPollInterval) }
        scheduleSync()
    }

    /// 后台补拉专用：真正 await 跑完「连接 → 推 → 拉 → 下载」一整轮再返回，可被取消。
    /// 与 syncNow()（触发即返回，交给内部 syncTask 异步跑）不同——BGTask 必须等这一轮结束
    /// 才能 setTaskCompleted。复用 connectAndSync 的单轮逻辑，内部各步都有 Task.isCancelled 检查，
    /// 上层（BackgroundRefresher 的 expirationHandler）取消时能协作式提前收尾。
    func syncOnce() async {
        guard !BubuStoreHealth.loadFailed else {
            connectionState = .offline
            return
        }
        migrateCursorsIfNeeded()   // BGTask 冷启动兜底引擎不走 start()，这里补一次游标契约迁移
        guard config.isConfigured else {
            connectionState = .offline
            refreshPendingCount()
            return
        }
        await connectAndSync()
    }

    /// 「全部重传」：服务器缺内容时的正式恢复手段（设置 →「同步与备份」）。
    ///
    /// 语义是**只补缺、不覆盖**（D9-02）：本机已同步的内容以 create-only 方式重推——服务器上没有的
    /// 才新建；服务器已有同一条（可能是家人后来改过的新版本）就原样带回并更新本机，绝不 PATCH 覆盖。
    /// 本机本来就有未上传改动的条目不动，照常按编辑时间比对推送。里程碑除外（标题唯一策略单独修复）。
    @discardableResult
    func forceUploadAllLocalData() async -> String {
        // 重标待上传也属于这一轮：必须等当前推拉退出，不能在前台上传中途改它的状态。
        await syncRuns.withPermit { await self.forceUploadAllLocalDataExclusively() }
            ?? "BUBU_FORCE_UPLOAD_FAILED cancelled"
    }

    private func forceUploadAllLocalDataExclusively() async -> String {
        guard !BubuStoreHealth.loadFailed else { return "BUBU_FORCE_UPLOAD_FAILED store_unavailable at=\(Date())" }
        guard let context = modelContext else { return "BUBU_FORCE_UPLOAD_FAILED no_context at=\(Date())" }
        var recoveryKeys: [String] = []
        var counts: [String: Int] = [:]
        /// 只把「已同步」的行改成 create-only 重推；未同步的脏行保持原样走正常 LWW。
        func markSynced<T: PersistentModel>(_ type: T.Type, collection: String,
                                            id: (T) -> UUID, isSynced: (T) -> Bool,
                                            include: (T) -> Bool = { _ in true },
                                            mark: (T) -> Void) throws {
            let rows = try context.fetch(FetchDescriptor<T>())
            var marked = 0
            for row in rows where isSynced(row) && include(row) {
                mark(row)
                recoveryKeys.append(SyncLedger.key(collection, id(row)))
                marked += 1
            }
            counts[collection] = marked
        }
        do {
            try markSynced(Entry.self, collection: "entries", id: \.id, isSynced: { $0.syncState == .synced }) { $0.syncState = .local }
            // 只重传本机确实持有文件的媒体：家人上传、本机尚未下载的那些没有本地文件，
            // 标成 .local 只会立刻变成永久失败，还会让远端更新/删除被当作"本地有未推改动"而拒收。
            try markSynced(Media.self, collection: "media", id: \.id, isSynced: { $0.syncState == .synced },
                           include: { item in item.localFileName.map { self.mediaStore.fileExists(forMedia: $0) } ?? false }) {
                $0.syncState = .local; $0.uploadProgress = 0
            }
            try markSynced(FirstTime.self, collection: "firsttimes", id: \.id, isSynced: { $0.syncState == .synced }) { $0.syncState = .local }
            try markSynced(FamilyMember.self, collection: "members", id: \.id, isSynced: { $0.syncState == .synced }) { $0.syncState = .local }
            try markSynced(ChildProfile.self, collection: "childprofile", id: \.id, isSynced: { $0.syncState == .synced }) { $0.syncState = .local }
            try markSynced(HealthRecord.self, collection: "healthrecords", id: \.id, isSynced: { $0.syncState == .synced }) { $0.syncState = .local }
            try markSynced(VaccineRecord.self, collection: "vaccinerecords", id: \.id, isSynced: { $0.syncState == .synced }) { $0.syncState = .local }
            try markSynced(GrowthMeasurement.self, collection: "growthmeasurements", id: \.id, isSynced: { $0.syncState == .synced }) { $0.syncState = .local }
            try markSynced(Comment.self, collection: "comments", id: \.id, isSynced: { $0.syncState == .synced }) { $0.syncState = .local }
            try markSynced(VoiceNote.self, collection: "voicenotes", id: \.id, isSynced: { $0.syncState == .synced }) { $0.syncState = .local }
            try markSynced(VoiceMemo.self, collection: "voicememos", id: \.id, isSynced: { $0.syncState == .synced }) { $0.syncState = .local }
            try markSynced(TimeCapsule.self, collection: "timecapsules", id: \.id, isSynced: { $0.syncState == .synced }) { $0.syncState = .local }
        } catch {
            context.rollback()
            recordFailure(error, item: "准备重传")
            return "BUBU_FORCE_UPLOAD_FAILED read"
        }
        // 先落恢复标记再保存：保存这一刻的 willSave 不能把重传误记成「刚编辑」。
        ledger.markRecovery(recoveryKeys)
        ledger.suppressEditStamps = true
        let saved = saveAndRefresh(context)
        ledger.suppressEditStamps = false
        guard saved else { return "BUBU_FORCE_UPLOAD_FAILED save" }
        downloadScanNeeded = true
        await performConnectAndSync()
        let summary = counts.keys.sorted().map { "\($0)=\(counts[$0] ?? 0)" }.joined(separator: " ")
        return "BUBU_FORCE_UPLOAD_DONE createOnly \(summary) failure=\(lastFailureReason ?? "none") at=\(Date())"
    }

    // MARK: - 连接

    // MARK: 轮询与退避

    private static let basePollInterval = SyncBackoff.baseInterval
    /// 连续失败次数，驱动指数退避。任一轮成功即清零。
    private var consecutiveFailures = 0

    private var currentPollInterval: TimeInterval {
        SyncBackoff.interval(failures: consecutiveFailures, realtimeConnected: realtimeConnected)
    }

    private func startPolling() {
        schedulePollTimer(after: currentPollInterval)
    }

    /// 重排轮询定时器。退避档位变化时调用；间隔没变就不重排，避免每轮都推迟下一次触发。
    private func schedulePollTimer(after interval: TimeInterval) {
        if let timer = pollTimer, abs(timer.timeInterval - interval) < 0.5 { return }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.config.isConfigured else { return }
                self.scheduleSync()
            }
        }
    }

    /// 一轮结束后按结果调整退避：成功清零回 30 秒，失败逐级拉长。
    private func updateBackoff(succeeded: Bool) {
        if succeeded {
            guard consecutiveFailures != 0 else { return }
            consecutiveFailures = 0
        } else {
            consecutiveFailures = min(consecutiveFailures + 1, 8)
        }
        guard pollTimer != nil else { return }
        schedulePollTimer(after: currentPollInterval)
    }

    private func scheduleSync() {
        guard syncTask == nil else {
            needsAnotherSync = true
            return
        }
        connectionState = .connecting
        lastScheduledAt = .now
        let runID = UUID()
        activeSyncID = runID
        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.connectAndSync()
            guard self.activeSyncID == runID else { return }
            self.activeSyncID = nil
            self.syncTask = nil
            if self.needsAnotherSync {
                self.needsAnotherSync = false
                self.scheduleSync()
            }
        }
    }

    private func connectAndSync() async {
        await syncRuns.withPermit { await self.performConnectAndSync() }
    }

    private func performConnectAndSync() async {
        runningCheckpointGeneration = checkpointGeneration
        defer { runningCheckpointGeneration = nil }
        guard isCurrentRun else { return }
        guard !BubuStoreHealth.loadFailed else {
            connectionState = .offline
            return
        }
        beginSyncRun()
        let ok = (try? await apiClient.ping()) ?? false
        guard isCurrentRun else { finalizeRun(); return }
        guard ok else {
            connectionState = .offline
            currentSyncLabel = nil
            currentUploadProgress = nil
            recordFailure(APIError.network("连不上家里的服务器"), item: "连接")
            refreshPendingCount()
            finalizeRun()
            return
        }
        do {
            _ = try await apiClient.authenticate(role: config.currentRole.rawValue)
            try checkRunValidity()
        } catch {
            guard isCurrentRun else { finalizeRun(); return }
            connectionState = .offline
            currentSyncLabel = nil
            currentUploadProgress = nil
            recordFailure(error, item: "账号")
            refreshPendingCount()
            finalizeRun()
            return
        }
        guard isCurrentRun else { finalizeRun(); return }
        // ping + auth 成功只说明「连得上」，不说明「同步成功」。
        // 以前这里直接置 .online 并把失败计数清零，于是推拉全线报错时
        // 连接状态仍然是在线、退避仍然是 30 秒，用户看到的是一切正常。
        connectionState = .online
        lastFailureReason = nil          // 新一轮重新判定，不带上一轮的旧结论

        await pushLocal()
        guard isCurrentRun else { finalizeRun(); return }
        await pullRemote()
        guard isCurrentRun else { finalizeRun(); return }
        if let context = modelContext {
            await downloadMissingFiles(context)
            guard isCurrentRun else { finalizeRun(); return }
            // 整轮只刷一次小组件，且只在本轮真的改了本地数据时：
            // SSE/轮询的空轮不再每 30 秒重建快照、reloadAllTimelines、重建 Spotlight（D4-05）。
            if changedThisRun { refreshWidgetSnapshot(context) }
        }
        currentSyncLabel = nil
        currentUploadProgress = nil
        finalizeRun()
        // 注：不再叠加 subscribeRealtime 的 8 秒轮询——与 30 秒同步循环重复，纯耗电。
        // 后续接 SSE 长连时在这里恢复订阅。
    }

    /// 一轮结束后评估瞬时失败：单轮抖动静默自愈，连续两轮（≈60s）仍失败才平和提示。
    private func finalizeRun() {
        isSyncing = false
        let succeeded = connectionState == .online && lastFailureReason == nil && !softFailureThisRun && isCurrentRun
        updateBackoff(succeeded: succeeded)
        if succeeded, modelContext != nil { lastSyncedAt = .now }
        if softFailureThisRun {
            softFailureStreak += 1
            if softFailureStreak >= 2 {
                softNotice = "有几项还在等网络，正在自动补拉…"
            }
        } else {
            softFailureStreak = 0
            softNotice = nil
        }
    }

    // MARK: - 推：本地 → 远端

    private func pushLocal() async {
        guard let context = modelContext else { return }
        do { try normalizeMilestonesByTitle(context) }
        catch { recordFailure(error, item: "核对里程碑"); return }
        // 先消费删除队列：删除意图优先于数据推送，避免「先推后删」竞态
        await processPendingDeletions(context)
        // 取所有未同步（local/failed）的 Entry
        let locals = pendingBatch(context, Entry.self, collection: "entries", order: Self.pendingOrder(\Entry.syncStateRaw, \Entry.createdAt), predicate: #Predicate {
            $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading"
        })
        refreshPendingCount()

        for entry in locals {
            guard isCurrentRun else { return }
            beginItem("同步记录")
            entry.syncState = .uploading
            guard saveAndRefresh(context) else { return }
            var dto = Self.makeDTO(entry)
            let entryId = entry.id
            let recoveryKey = SyncLedger.key("entries", entryId)
            let createOnly = ledger.isRecovery(recoveryKey)
            if createOnly { dto.createOnly = true }
            let requestScope = clientScope
            do {
                let saved = try await apiClient.createEntry(dto)
                if try preserveDeletedUploadReceipt(saved.id, collection: "entries", requestScope: requestScope,
                    descriptor: FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryId }), in: context) {
                    finishItem()
                    continue
                }
                try checkRunValidity()
                if createOnly {
                    try Self.completeRecoveredEntryUpload(saved, sent: dto, localId: entryId, in: context)
                } else {
                    try Self.completeEntryUpload(saved, sent: dto, localId: entryId, in: context)
                }
                ledger.clearAfterPush(recoveryKey)
            } catch {
                guard isCurrentRun else { return }
                if let current = try? context.fetch(FetchDescriptor<Entry>(
                    predicate: #Predicate { $0.id == entryId })).first {
                    if current.syncState == .uploading { current.syncState = .failed }
                }
                notePushFailure(error, collection: "entries", id: entryId, label: "一条记录", item: "记录")
            }
            finishItem()
            saveAndRefresh(context)
        }
        await pushUnsyncedMedia(context)
        await pushLocalJSONObjects(context)
        await pushTimeCapsules(context)
        saveAndRefresh(context)
    }

    /// 上次真正重算待办计数的时刻。
    private var lastPendingCountAt = Date.distantPast
    /// 计数重算的最小间隔。`saveAndRefresh` 在推送循环里每条都会调一次，
    /// 而一次重算是 14 条 SQL COUNT——500 条待推就是 7000 次 COUNT 全在主线程。
    /// 计数只是给进度条看的，节流到 0.4 秒完全够用。
    private static let pendingCountMinInterval: TimeInterval = 0.4

    @discardableResult
    private func saveAndRefresh(_ context: ModelContext, forceCount: Bool = false) -> Bool {
        // save 失败不能再静默吞掉：它意味着这一轮的改动根本没落盘，
        // 而 UI 上仍显示「已同步」。记进 lastFailureReason，首页同步条会直接说出来。
        if context.hasChanges { changedThisRun = true }
        do {
            try context.save()
        } catch {
            holdCursorForCurrentPull = true
            recordFailure(error, item: "本地保存")
            Self.log.error("同步保存失败：\(error.localizedDescription, privacy: .public)")
            return false
        }
        if forceCount || Date.now.timeIntervalSince(lastPendingCountAt) >= Self.pendingCountMinInterval {
            lastPendingCountAt = .now
            refreshPendingCount()
        }
        return true
    }

    /// 只在本轮真有改动时调用；快照内容没变就不写盘、不唤起小组件扩展（D4-05）。
    private func refreshWidgetSnapshot(_ context: ModelContext) {
        guard let snapshot = SharedWidgetSnapshot.make(context: context) else { return }
        if SharedDefaults.saveWidgetSnapshotIfChanged(snapshot) { WidgetRefresher.reload() }
        // 索引器内部按记录指纹判断，记录没变不会重建 2000 条索引。
        BubuMomentSpotlightIndexer.schedule(context: context)
    }

    // MARK: - 删除队列消费

    private func processPendingDeletions(_ context: ModelContext) async {
        let deletions = (try? context.fetch(FetchDescriptor<PendingDeletion>(
            sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        for deletion in deletions {
            guard isCurrentRun else { return }
            beginItem("同步删除")
            do {
                try await performRemoteDeletion(deletion)
                try checkRunValidity()
                context.delete(deletion)
            } catch {
                guard isCurrentRun else { return }
                if case APIError.server(let code, _) = error, code == 404 {
                    context.delete(deletion)   // 远端本就不存在，视作完成
                } else {
                    recordFailure(error, item: "删除")   // 瞬时失败留队，下轮重试
                }
            }
            finishItem()
            saveAndRefresh(context)
        }
    }

    private func performRemoteDeletion(_ deletion: PendingDeletion) async throws {
        try await apiClient.deleteRecord(collection: deletion.collection, remoteId: deletion.remoteId)
    }

    private func isPendingDeletion(collection: String, remoteId: String?, context: ModelContext) throws -> Bool {
        guard let remoteId, !remoteId.isEmpty else { return false }
        var query = FetchDescriptor<PendingDeletion>(predicate: #Predicate { $0.collection == collection && $0.remoteId == remoteId })
        query.fetchLimit = 1
        return try !context.fetch(query).isEmpty
    }

    private func beginSyncRun() {
        isSyncing = true
        lastPendingCountAt = .now
        refreshPendingCount()
        totalPendingAtStart = pendingCount
        processedThisRun = 0
        currentUploadProgress = nil
        lastFailureReason = nil
        lastLargeFileNotice = nil
        softFailureThisRun = false
        changedThisRun = false
        currentSyncLabel = pendingCount > 0 ? "准备同步 \(pendingCount) 项" : "检查服务器"
    }

    private func beginItem(_ label: String) {
        currentSyncLabel = label
        currentUploadProgress = nil
    }

    private func finishItem() {
        processedThisRun += 1
        currentUploadProgress = nil
    }

    private func recordFailure(_ error: Error, item: String) {
        if Self.isMissingOptionalServerCollection(error, item: item) {
            softFailureThisRun = true
            return
        }

        if Self.isUserRecoverableTransient(error) {
            softFailureThisRun = true
            return
        }

        lastFailureReason = "\(item)：\(Self.safeUserMessage(for: error))"
    }

    private static func isMissingOptionalServerCollection(_ error: Error, item: String) -> Bool {
        guard case APIError.server(let code, _) = error, code == 404 else { return false }
        return item == "疫苗记录" || item == "成长测量" || item == "删除"
    }

    private static func isUserRecoverableTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .resourceUnavailable,
                 .badServerResponse,
                 .secureConnectionFailed:
                return true
            default:
                return false
            }
        }

        if case APIError.server(let code, _) = error {
            return code == 408 || code == 429 || (500...599).contains(code)
        }

        if case APIError.network(let message) = error {
            return !hardLocalKeywords.contains { message.contains($0) }
        }

        return false
    }

    static let hardLocalKeywords = ["本地文件", "文件名为空", "找不到这条媒体", "文件不见了"]

    static func safeUserMessage(for error: Error) -> String {
        switch error {
        case APIError.fileTooLarge(_, let limit):
            return "文件太大，建议压缩到 \(max(1, limit / 1_048_576))MB 以内后再传。"
        case APIError.unauthorized:
            return "账号状态需要重新确认，请到设置里重新连接服务器。"
        case APIError.forbidden:
            return "服务器拒绝了这次同步，请到设置里查看连接配置。"
        case APIError.notConfigured:
            return "还没有连接家里的服务器。"
        case APIError.server(let code, _):
            if code == 400 || code == 403 {
                return "服务器拒绝了这次同步，请到设置里查看连接配置。"
            }
            if code == 404 { return "服务器暂时缺少这个同步模块，其他数据会继续同步。" }
            return "服务器暂时没响应，App 会继续自动补传。"
        case APIError.network(let message):
            if message.contains("本地文件") || message.contains("文件不见了") {
                return "本地文件缺失，这一项需要重新选择后再同步。"
            }
            return "网络暂时不稳定，App 会继续自动补传。"
        default:
            return "同步遇到问题，App 会保留本地内容并继续重试。"
        }
    }

    /// 用 fetchCount（SQL COUNT）代替全表取回内存过滤——数据量大也不卡。
    private func refreshPendingCount() {
        guard let context = modelContext else {
            pendingCount = 0
            return
        }
        pendingCount =
            count(context, #Predicate<Entry> { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }) +
            count(context, #Predicate<Media> { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }) +
            count(context, #Predicate<Milestone> { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }) +
            count(context, #Predicate<FirstTime> { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }) +
            count(context, #Predicate<FamilyMember> { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }) +
            count(context, #Predicate<ChildProfile> { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }) +
            count(context, #Predicate<HealthRecord> { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }) +
            count(context, #Predicate<VaccineRecord> { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }) +
            count(context, #Predicate<GrowthMeasurement> { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }) +
            count(context, #Predicate<Comment> { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }) +
            count(context, #Predicate<VoiceNote> { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }) +
            count(context, #Predicate<VoiceMemo> { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }) +
            count(context, #Predicate<TimeCapsule> { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }) +
            count(context, #Predicate<PendingDeletion> { _ in true })
        // 「需要处理」的条目仍是 failed 状态，但不再排队：不计入「还有 N 项在排队」。
        pendingCount = max(0, pendingCount - ledger.excludedCount)
    }

    /// 一轮同步最多处理多少条待推。首次全家上云 / SSD 批量导入之后，
    /// 待推可能是几千条；一次性全部取回内存并逐条推，会把这一轮拖到几分钟且全程占着主线程。
    /// 分批处理：本轮推完这批就收工，剩下的下一轮继续（轮询与回前台都会触发），
    /// 进度条读的是 fetchCount 的真实总数，用户看到的仍是「还剩 N 项」。
    static let pushBatchCap = 200

    /// 待推排序：uploading（上轮中断）→ local（新内容）→ failed（重试），同状态按创建时间先来先推。
    /// 字符串倒序恰好是 uploading > local > failed。
    static func pendingOrder<T: PersistentModel>(_ state: KeyPath<T, String> & Sendable,
                                                 _ createdAt: KeyPath<T, Date> & Sendable) -> [SortDescriptor<T>] {
        [SortDescriptor(state, order: .reverse), SortDescriptor(createdAt)]
    }

    /// 取一批「待推」对象（local / failed / uploading），按 fetchLimit 截断。
    /// 「需要处理」名单里的条目不再排队，也不占名额（D9-03）。
    private func pendingBatch<T: PersistentModel>(_ context: ModelContext,
                                                  _ type: T.Type = T.self,
                                                  collection: String,
                                                  order: [SortDescriptor<T>],
                                                  predicate: Predicate<T>) -> [T] where T.ID == UUID {
        let excluded = ledger.excludedIDs(for: collection)
        var descriptor = FetchDescriptor<T>(predicate: predicate, sortBy: order)
        descriptor.fetchLimit = Self.pushBatchCap + excluded.count
        do {
            let rows = try context.fetch(descriptor)
            guard !excluded.isEmpty else { return rows }
            return Array(rows.lazy.filter { !excluded.contains($0.id) }.prefix(Self.pushBatchCap))
        } catch {
            recordFailure(error, item: "读取待同步内容")
            Self.log.error("读取待同步内容失败：\(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func count<T: PersistentModel>(_ context: ModelContext, _ predicate: Predicate<T>) -> Int {
        do { return try context.fetchCount(FetchDescriptor<T>(predicate: predicate)) }
        catch { recordFailure(error, item: "读取同步状态"); return 0 }
    }

    private func pushLocalJSONObjects(_ context: ModelContext) async {
        let localMilestones = pendingBatch(context, Milestone.self, collection: "milestones", order: Self.pendingOrder(\Milestone.syncStateRaw, \Milestone.createdAt), predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" })
        // 预设占位符不上云：批量标记为已同步，循环外统一保存一次，避免 N 次 save + widget 刷新。
        let placeholders = localMilestones.filter { Self.isLocalPresetPlaceholder($0) }
        if !placeholders.isEmpty {
            placeholders.forEach { $0.syncState = .synced }
            saveAndRefresh(context)
        }
        for item in localMilestones where !Self.isLocalPresetPlaceholder(item) {
            guard isCurrentRun else { return }
            beginItem("同步里程碑")
            let itemId = item.id
            let requestScope = clientScope
            do {
                item.syncState = .uploading; saveAndRefresh(context)
                var dto = Self.makeDTO(item)
                let version = outgoingVersion("milestones", itemId, createdAt: item.createdAt)
                dto.clientEditedAt = version.editedAt; dto.createOnly = version.createOnly
                let saved = try await apiClient.upsertMilestone(dto)
                if try preserveDeletedUploadReceipt(saved.id, collection: "milestones", requestScope: requestScope,
                    descriptor: FetchDescriptor<Milestone>(predicate: #Predicate { $0.id == itemId }), in: context) {
                    finishItem()
                    continue
                }
                try checkRunValidity()
                // 服务器保留了更新的远端版本（家人后改的 / 恢复模式下服务器已有）：采用它，不留旧内容装 synced。
                if item.syncState == .uploading,
                   Self.remoteVersionWasKept(sent: version.editedAt, returned: saved.clientEditedAt, createOnly: version.createOnly) {
                    Self.apply(saved, to: item)
                }
                item.remoteId = saved.id; item.syncState = Self.uploadCompletionState(item.syncState)
                finishPushBookkeeping("milestones", itemId, state: item.syncState)
            }
            catch { guard isCurrentRun else { return }; if let current = try? context.fetch(FetchDescriptor<Milestone>(predicate: #Predicate { $0.id == itemId })).first, current.syncState == .uploading { current.syncState = .failed }; notePushFailure(error, collection: "milestones", id: itemId, label: "里程碑", item: "里程碑") }
            finishItem()
            saveAndRefresh(context)
        }
        let localFirstTimes = pendingBatch(context, FirstTime.self, collection: "firsttimes", order: Self.pendingOrder(\FirstTime.syncStateRaw, \FirstTime.createdAt), predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" })
        for item in localFirstTimes {
            guard isCurrentRun else { return }
            beginItem("同步第一次")
            let itemId = item.id
            let requestScope = clientScope
            do {
                item.syncState = .uploading; saveAndRefresh(context)
                var dto = Self.makeDTO(item)
                let version = outgoingVersion("firsttimes", itemId, createdAt: item.createdAt)
                dto.clientEditedAt = version.editedAt; dto.createOnly = version.createOnly
                let saved = try await apiClient.upsertFirstTime(dto)
                if try preserveDeletedUploadReceipt(saved.id, collection: "firsttimes", requestScope: requestScope,
                    descriptor: FetchDescriptor<FirstTime>(predicate: #Predicate { $0.id == itemId }), in: context) {
                    finishItem()
                    continue
                }
                try checkRunValidity()
                // 服务器保留了更新的远端版本（家人后改的 / 恢复模式下服务器已有）：采用它，不留旧内容装 synced。
                if item.syncState == .uploading,
                   Self.remoteVersionWasKept(sent: version.editedAt, returned: saved.clientEditedAt, createOnly: version.createOnly) {
                    Self.apply(saved, to: item)
                }
                item.remoteId = saved.id; item.syncState = Self.uploadCompletionState(item.syncState)
                finishPushBookkeeping("firsttimes", itemId, state: item.syncState)
            }
            catch { guard isCurrentRun else { return }; if let current = try? context.fetch(FetchDescriptor<FirstTime>(predicate: #Predicate { $0.id == itemId })).first, current.syncState == .uploading { current.syncState = .failed }; notePushFailure(error, collection: "firsttimes", id: itemId, label: "人生第一次", item: "第一次") }
            finishItem()
            saveAndRefresh(context)
        }
        let localMembers = pendingBatch(context, FamilyMember.self, collection: "members", order: Self.pendingOrder(\FamilyMember.syncStateRaw, \FamilyMember.createdAt), predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" })
        for item in localMembers {
            guard isCurrentRun else { return }
            beginItem("同步家庭成员")
            let itemId = item.id
            let requestScope = clientScope
            do {
                item.syncState = .uploading; saveAndRefresh(context)
                var dto = Self.makeDTO(item)
                let version = outgoingVersion("members", itemId, createdAt: item.createdAt)
                dto.clientEditedAt = version.editedAt; dto.createOnly = version.createOnly
                let saved = try await apiClient.upsertFamilyMember(dto)
                if try preserveDeletedUploadReceipt(saved.id, collection: "members", requestScope: requestScope,
                    descriptor: FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.id == itemId }), in: context) {
                    finishItem()
                    continue
                }
                try checkRunValidity()
                // 服务器保留了更新的远端版本（家人后改的 / 恢复模式下服务器已有）：采用它，不留旧内容装 synced。
                if item.syncState == .uploading,
                   Self.remoteVersionWasKept(sent: version.editedAt, returned: saved.clientEditedAt, createOnly: version.createOnly) {
                    Self.apply(saved, to: item)
                }
                item.remoteId = saved.id; item.syncState = Self.uploadCompletionState(item.syncState)
                finishPushBookkeeping("members", itemId, state: item.syncState)
            }
            catch { guard isCurrentRun else { return }; if let current = try? context.fetch(FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.id == itemId })).first, current.syncState == .uploading { current.syncState = .failed }; notePushFailure(error, collection: "members", id: itemId, label: "家庭成员", item: "家庭成员") }
            finishItem()
            saveAndRefresh(context)
        }
        let localProfiles = pendingBatch(context, ChildProfile.self, collection: "childprofile", order: Self.pendingOrder(\ChildProfile.syncStateRaw, \ChildProfile.createdAt), predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" })
        for item in localProfiles {
            guard isCurrentRun else { return }
            beginItem("同步布布档案")
            let profileId = item.id
            let requestScope = clientScope
            do {
                item.syncState = .uploading
                saveAndRefresh(context)
                var dto = Self.makeDTO(item)
                let version = outgoingVersion("childprofile", profileId, createdAt: item.createdAt)
                dto.clientEditedAt = version.editedAt; dto.createOnly = version.createOnly
                let saved = try await apiClient.upsertChildProfile(dto)
                if try preserveDeletedUploadReceipt(saved.id, collection: "childprofile", requestScope: requestScope,
                    descriptor: FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.id == profileId }), in: context) {
                    finishItem()
                    continue
                }
                try checkRunValidity()
                let keptRemote = item.syncState == .uploading &&
                    Self.remoteVersionWasKept(sent: version.editedAt, returned: saved.clientEditedAt, createOnly: version.createOnly)
                if keptRemote { Self.apply(saved, to: item) }
                // 头像变更后 avatarRemoteURL 被置空 → 补传到 childprofile.avatar（服务器版本更新时不覆盖远端头像）
                if !keptRemote, let fileName = item.avatarMediaFileName, item.avatarRemoteURL == nil {
                    let url = mediaStore.mediaURL(for: fileName)
                    if FileManager.default.fileExists(atPath: url.path) {
                        let receipt = try await Self.consumeUpload(
                            apiClient.uploadChildAvatar(profileLocalId: item.id, fileURL: url, fileName: fileName),
                            onProgress: { self.currentUploadProgress = $0 })
                        try checkRunValidity()
                        // 上传期间档案可能被删：重新确认仍在，再碰模型。
                        if try preserveDeletedUploadReceipt(saved.id, collection: "childprofile", requestScope: requestScope,
                            descriptor: FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.id == profileId }), in: context) {
                            finishItem()
                            continue
                        }
                        if item.avatarMediaFileName == fileName { item.avatarRemoteURL = receipt.remoteURL }
                    }
                }
                item.remoteId = saved.id
                item.syncState = Self.uploadCompletionState(item.syncState)
                finishPushBookkeeping("childprofile", profileId, state: item.syncState)
            }
            catch {
                guard isCurrentRun else { return }
                if let current = try? context.fetch(FetchDescriptor<ChildProfile>(
                    predicate: #Predicate { $0.id == profileId })).first,
                   current.syncState == .uploading { current.syncState = .failed }
                notePushFailure(error, collection: "childprofile", id: profileId, label: "布布档案", item: "布布档案")
            }
            finishItem()
            saveAndRefresh(context)
        }
        let localHealth = pendingBatch(context, HealthRecord.self, collection: "healthrecords", order: Self.pendingOrder(\HealthRecord.syncStateRaw, \HealthRecord.createdAt), predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" })
        for item in localHealth {
            guard isCurrentRun else { return }
            beginItem("同步健康记录")
            let itemId = item.id
            let requestScope = clientScope
            do {
                item.syncState = .uploading
                saveAndRefresh(context)
                var dto = Self.makeDTO(item)
                let version = outgoingVersion("healthrecords", itemId, createdAt: item.createdAt)
                dto.clientEditedAt = version.editedAt; dto.createOnly = version.createOnly
                let saved = try await apiClient.upsertHealthRecord(dto)
                if try preserveDeletedUploadReceipt(saved.id, collection: "healthrecords", requestScope: requestScope,
                    descriptor: FetchDescriptor<HealthRecord>(predicate: #Predicate { $0.id == itemId }), in: context) {
                    finishItem()
                    continue
                }
                try checkRunValidity()
                // 妈妈刚改的发烧记录比这台旧副本新：采用远端，不再静默覆盖全家（D9-02）。
                if item.syncState == .uploading,
                   Self.remoteVersionWasKept(sent: version.editedAt, returned: saved.clientEditedAt, createOnly: version.createOnly) {
                    Self.apply(saved, to: item)
                }
                item.remoteId = saved.id
                item.syncState = Self.uploadCompletionState(item.syncState)
                finishPushBookkeeping("healthrecords", itemId, state: item.syncState)
            }
            catch { guard isCurrentRun else { return }; if let current = try? context.fetch(FetchDescriptor<HealthRecord>(predicate: #Predicate { $0.id == itemId })).first, current.syncState == .uploading { current.syncState = .failed }; notePushFailure(error, collection: "healthrecords", id: itemId, label: "健康记录", item: "健康记录") }
            finishItem()
            saveAndRefresh(context)
        }
        let localVaccines = pendingBatch(context, VaccineRecord.self, collection: "vaccinerecords", order: Self.pendingOrder(\VaccineRecord.syncStateRaw, \VaccineRecord.createdAt), predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" })
        for item in localVaccines {
            guard isCurrentRun else { return }
            beginItem("同步疫苗记录")
            let vaccineId = item.id
            let requestScope = clientScope
            do {
                item.syncState = .uploading
                saveAndRefresh(context)
                var dto = Self.makeDTO(item)
                let createOnly = ledger.isRecovery(SyncLedger.key("vaccinerecords", vaccineId))
                dto.createOnly = createOnly
                let saved = try await apiClient.upsertVaccineRecord(dto)
                if try preserveDeletedUploadReceipt(saved.id, collection: "vaccinerecords", requestScope: requestScope,
                    descriptor: FetchDescriptor<VaccineRecord>(predicate: #Predicate { $0.id == vaccineId }), in: context) {
                    finishItem()
                    continue
                }
                try checkRunValidity()
                // LWW：远端这条更新导致本次推送被通用 upsert 跳过（带回的编辑时间比本地新）→ 采用远端版本，
                // 否则本地会停在旧内容却被标成 synced，且游标已越过该记录不会再拉回（与 S-P2 游标解耦并存的收尾）。
                if let remoteEdited = saved.editedAt, remoteEdited > item.updatedAt {
                    Self.apply(saved, to: item)
                } else if createOnly, item.syncState == .uploading,
                          Self.remoteVersionWasKept(sent: dto.editedAt ?? item.updatedAt, returned: saved.editedAt, createOnly: true) {
                    Self.apply(saved, to: item)
                }
                item.remoteId = saved.id
                item.syncState = Self.uploadCompletionState(item.syncState)
                finishPushBookkeeping("vaccinerecords", vaccineId, state: item.syncState)
            } catch {
                guard isCurrentRun else { return }
                // 网络等待期间记录可能被删：只用重新取到的模型。
                let vaccineDescriptor = FetchDescriptor<VaccineRecord>(predicate: #Predicate { $0.id == vaccineId })
                if Self.isMissingOptionalServerCollection(error, item: "疫苗记录"),
                   let item = try? context.fetch(vaccineDescriptor).first {
                    do {
                        let saved = try await apiClient.upsertHealthRecord(Self.makeHealthFallbackDTO(item))
                        if try preserveDeletedUploadReceipt(saved.id, collection: "healthrecords", requestScope: requestScope,
                            descriptor: FetchDescriptor<VaccineRecord>(predicate: #Predicate { $0.id == vaccineId }), in: context) {
                            finishItem()
                            continue
                        }
                        try checkRunValidity()
                        item.remoteId = saved.id
                        item.sourceRaw = "health-fallback"
                        item.syncState = Self.uploadCompletionState(item.syncState)
                    } catch {
                        guard isCurrentRun else { return }
                        if let current = try? context.fetch(vaccineDescriptor).first, current.syncState == .uploading { current.syncState = .failed }
                        notePushFailure(error, collection: "vaccinerecords", id: vaccineId, label: "疫苗记录", item: "疫苗记录")
                    }
                } else {
                    if let current = try? context.fetch(vaccineDescriptor).first, current.syncState == .uploading { current.syncState = .failed }
                    notePushFailure(error, collection: "vaccinerecords", id: vaccineId, label: "疫苗记录", item: "疫苗记录")
                }
            }
            finishItem()
            saveAndRefresh(context)
        }
        let localGrowth = pendingBatch(context, GrowthMeasurement.self, collection: "growthmeasurements", order: Self.pendingOrder(\GrowthMeasurement.syncStateRaw, \GrowthMeasurement.createdAt), predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" })
        for item in localGrowth {
            guard isCurrentRun else { return }
            beginItem("同步成长测量")
            let growthId = item.id
            let requestScope = clientScope
            do {
                item.syncState = .uploading
                saveAndRefresh(context)
                var dto = Self.makeDTO(item)
                let createOnly = ledger.isRecovery(SyncLedger.key("growthmeasurements", growthId))
                dto.createOnly = createOnly
                let saved = try await apiClient.upsertGrowthMeasurement(dto)
                if try preserveDeletedUploadReceipt(saved.id, collection: "growthmeasurements", requestScope: requestScope,
                    descriptor: FetchDescriptor<GrowthMeasurement>(predicate: #Predicate { $0.id == growthId }), in: context) {
                    finishItem()
                    continue
                }
                try checkRunValidity()
                // 见疫苗记录：LWW 跳过时采用远端更新版本，避免本地停留在旧内容却标记 synced。
                if let remoteEdited = saved.editedAt, remoteEdited > item.updatedAt {
                    Self.apply(saved, to: item)
                } else if createOnly, item.syncState == .uploading,
                          Self.remoteVersionWasKept(sent: dto.editedAt ?? item.updatedAt, returned: saved.editedAt, createOnly: true) {
                    Self.apply(saved, to: item)
                }
                item.remoteId = saved.id
                item.syncState = Self.uploadCompletionState(item.syncState)
                finishPushBookkeeping("growthmeasurements", growthId, state: item.syncState)
            } catch {
                guard isCurrentRun else { return }
                // 网络等待期间记录可能被删：只用重新取到的模型。
                let growthDescriptor = FetchDescriptor<GrowthMeasurement>(predicate: #Predicate { $0.id == growthId })
                if Self.isMissingOptionalServerCollection(error, item: "成长测量"),
                   let item = try? context.fetch(growthDescriptor).first {
                    do {
                        let saved = try await apiClient.upsertHealthRecord(Self.makeHealthFallbackDTO(item))
                        if try preserveDeletedUploadReceipt(saved.id, collection: "healthrecords", requestScope: requestScope,
                            descriptor: FetchDescriptor<GrowthMeasurement>(predicate: #Predicate { $0.id == growthId }), in: context) {
                            finishItem()
                            continue
                        }
                        try checkRunValidity()
                        item.remoteId = saved.id
                        item.sourceRaw = "health-fallback"
                        item.syncState = Self.uploadCompletionState(item.syncState)
                    } catch {
                        guard isCurrentRun else { return }
                        if let current = try? context.fetch(growthDescriptor).first, current.syncState == .uploading { current.syncState = .failed }
                        notePushFailure(error, collection: "growthmeasurements", id: growthId, label: "成长测量", item: "成长测量")
                    }
                } else {
                    if let current = try? context.fetch(growthDescriptor).first, current.syncState == .uploading { current.syncState = .failed }
                    notePushFailure(error, collection: "growthmeasurements", id: growthId, label: "成长测量", item: "成长测量")
                }
            }
            finishItem()
            saveAndRefresh(context)
        }
        await pushLocalFileObjects(context)
    }

    private func pushLocalFileObjects(_ context: ModelContext) async {
        let comments = pendingBatch(context, Comment.self, collection: "comments", order: Self.pendingOrder(\Comment.syncStateRaw, \Comment.createdAt), predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" })
        for comment in comments {
            guard isCurrentRun else { return }
            beginItem("同步家人补充")
            let commentId = comment.id
            let requestScope = clientScope
            do {
                comment.syncState = .uploading
                saveAndRefresh(context)
                var dto = Self.makeDTO(comment)
                let version = outgoingVersion("comments", commentId, createdAt: comment.createdAt)
                dto.clientEditedAt = version.editedAt; dto.createOnly = version.createOnly
                var saved = try await apiClient.upsertComment(dto)
                if try preserveDeletedUploadReceipt(saved.id, collection: "comments", requestScope: requestScope,
                    descriptor: FetchDescriptor<Comment>(predicate: #Predicate { $0.id == commentId }), in: context) {
                    finishItem()
                    continue
                }
                try checkRunValidity()
                let keptRemote = comment.syncState == .uploading &&
                    Self.remoteVersionWasKept(sent: version.editedAt, returned: saved.clientEditedAt, createOnly: version.createOnly)
                if keptRemote { Self.apply(saved, to: comment) }
                comment.remoteId = saved.id
                var uploadedRemoteURL = comment.remoteURL
                // 服务器保留了远端版本且已有语音文件：不再用本机文件覆盖。
                if !(keptRemote && saved.remoteURL != nil),
                   let fileName = comment.voiceFileName, let entryId = comment.entry?.id {
                    let url = mediaStore.mediaURL(for: fileName)
                    if FileManager.default.fileExists(atPath: url.path) {
                        let receipt = try await Self.consumeUpload(
                            apiClient.uploadCommentVoice(commentId: comment.id, entryLocalId: entryId, fileURL: url, fileName: fileName),
                            onProgress: { self.currentUploadProgress = $0 })
                        try checkRunValidity()
                        saved.id = receipt.remoteId
                        uploadedRemoteURL = receipt.remoteURL
                    }
                }
                guard try context.fetchCount(FetchDescriptor<Comment>(predicate: #Predicate { $0.id == commentId })) > 0 else {
                    PendingDeletion.enqueue(collection: "comments", remoteId: saved.id, in: context)
                    finishItem()
                    saveAndRefresh(context)
                    continue
                }
                comment.remoteURL = uploadedRemoteURL
                comment.remoteId = saved.id; comment.syncState = Self.uploadCompletionState(comment.syncState)
                finishPushBookkeeping("comments", commentId, state: comment.syncState)
            } catch {
                guard isCurrentRun else { return }
                if let current = try? context.fetch(FetchDescriptor<Comment>(predicate: #Predicate { $0.id == commentId })).first {
                    if current.syncState == .uploading { current.syncState = .failed }
                }
                notePushFailure(error, collection: "comments", id: commentId, label: "家人补充", item: "家人补充")
            }
            finishItem()
            saveAndRefresh(context)
        }
        let notes = pendingBatch(context, VoiceNote.self, collection: "voicenotes", order: Self.pendingOrder(\VoiceNote.syncStateRaw, \VoiceNote.createdAt), predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" })
        for note in notes {
            guard isCurrentRun else { return }
            beginItem("同步记录语音")
            let noteId = note.id
            let requestScope = clientScope
            do {
                note.syncState = .uploading
                saveAndRefresh(context)
                var dto = Self.makeDTO(note)
                let version = outgoingVersion("voicenotes", noteId, createdAt: note.createdAt)
                dto.clientEditedAt = version.editedAt; dto.createOnly = version.createOnly
                var saved = try await apiClient.upsertVoiceNote(dto)
                if try preserveDeletedUploadReceipt(saved.id, collection: "voicenotes", requestScope: requestScope,
                    descriptor: FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.id == noteId }), in: context) {
                    finishItem()
                    continue
                }
                try checkRunValidity()
                let keptRemote = note.syncState == .uploading &&
                    Self.remoteVersionWasKept(sent: version.editedAt, returned: saved.clientEditedAt, createOnly: version.createOnly)
                if keptRemote { Self.apply(saved, to: note) }
                note.remoteId = saved.id
                var uploadedRemoteURL = note.remoteURL
                if !(keptRemote && saved.remoteURL != nil),
                   let fileName = note.localFileName, let entryId = note.entry?.id {
                    let url = mediaStore.mediaURL(for: fileName)
                    if FileManager.default.fileExists(atPath: url.path) {
                        let receipt = try await Self.consumeUpload(
                            apiClient.uploadVoiceNote(voiceId: note.id, entryLocalId: entryId, fileURL: url, fileName: fileName),
                            onProgress: { self.currentUploadProgress = $0 })
                        try checkRunValidity()
                        saved.id = receipt.remoteId
                        uploadedRemoteURL = receipt.remoteURL
                    }
                }
                guard try context.fetchCount(FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.id == noteId })) > 0 else {
                    PendingDeletion.enqueue(collection: "voicenotes", remoteId: saved.id, in: context)
                    finishItem()
                    saveAndRefresh(context)
                    continue
                }
                note.remoteURL = uploadedRemoteURL
                note.remoteId = saved.id; note.syncState = Self.uploadCompletionState(note.syncState)
                finishPushBookkeeping("voicenotes", noteId, state: note.syncState)
            } catch {
                guard isCurrentRun else { return }
                if let current = try? context.fetch(FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.id == noteId })).first {
                    if current.syncState == .uploading { current.syncState = .failed }
                }
                notePushFailure(error, collection: "voicenotes", id: noteId, label: "记录语音", item: "记录语音")
            }
            finishItem()
            saveAndRefresh(context)
        }
        let memos = pendingBatch(context, VoiceMemo.self, collection: "voicememos", order: Self.pendingOrder(\VoiceMemo.syncStateRaw, \VoiceMemo.createdAt), predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" })
        for memo in memos {
            guard isCurrentRun else { return }
            beginItem("同步成长之声")
            let memoId = memo.id
            let requestScope = clientScope
            do {
                memo.syncState = .uploading
                saveAndRefresh(context)
                var dto = Self.makeDTO(memo)
                let version = outgoingVersion("voicememos", memoId, createdAt: memo.createdAt)
                dto.clientEditedAt = version.editedAt; dto.createOnly = version.createOnly
                var saved = try await apiClient.upsertVoiceMemo(dto)
                if try preserveDeletedUploadReceipt(saved.id, collection: "voicememos", requestScope: requestScope,
                    descriptor: FetchDescriptor<VoiceMemo>(predicate: #Predicate { $0.id == memoId }), in: context) {
                    finishItem()
                    continue
                }
                try checkRunValidity()
                let keptRemote = memo.syncState == .uploading &&
                    Self.remoteVersionWasKept(sent: version.editedAt, returned: saved.clientEditedAt, createOnly: version.createOnly)
                if keptRemote { Self.apply(saved, to: memo) }
                memo.remoteId = saved.id
                var uploadedRemoteURL = memo.remoteURL
                if !(keptRemote && saved.remoteURL != nil), let fileName = memo.localFileName {
                    let url = mediaStore.mediaURL(for: fileName)
                    if FileManager.default.fileExists(atPath: url.path) {
                        let receipt = try await Self.consumeUpload(
                            apiClient.uploadVoiceMemo(memoId: memo.id, fileURL: url, fileName: fileName),
                            onProgress: { self.currentUploadProgress = $0 })
                        try checkRunValidity()
                        saved.id = receipt.remoteId
                        uploadedRemoteURL = receipt.remoteURL
                    }
                }
                guard try context.fetchCount(FetchDescriptor<VoiceMemo>(predicate: #Predicate { $0.id == memoId })) > 0 else {
                    PendingDeletion.enqueue(collection: "voicememos", remoteId: saved.id, in: context)
                    finishItem()
                    saveAndRefresh(context)
                    continue
                }
                memo.remoteURL = uploadedRemoteURL
                memo.remoteId = saved.id; memo.syncState = Self.uploadCompletionState(memo.syncState)
                finishPushBookkeeping("voicememos", memoId, state: memo.syncState)
            } catch {
                guard isCurrentRun else { return }
                if let current = try? context.fetch(FetchDescriptor<VoiceMemo>(predicate: #Predicate { $0.id == memoId })).first {
                    if current.syncState == .uploading { current.syncState = .failed }
                }
                notePushFailure(error, collection: "voicememos", id: memoId, label: "成长之声", item: "成长之声")
            }
            finishItem()
            saveAndRefresh(context)
        }
    }

    private var loggedPlaceholderMediaHold = false

    private func pushUnsyncedMedia(_ context: ModelContext) async {
        // 父记录没找到的孤儿媒体：永远传不上去，直接列进「需要处理」，不占批次名额。
        let orphans = (try? context.fetch(FetchDescriptor<Media>(predicate: #Predicate {
            $0.entry == nil && ($0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading")
        }))) ?? []
        let excludedMedia = ledger.excludedIDs(for: "media")
        for media in orphans where !excludedMedia.contains(media.id) {
            media.syncState = .failed
            notePushFailure(APIError.network("找不到这条媒体对应的记录"), collection: "media", id: media.id,
                            label: media.type == .video ? "一段视频" : "一张照片", item: "媒体")
        }
        // 只取父记录已在服务器落地的媒体：等父记录的媒体不再占 200 条名额，后面的照片不会永远排不上（D9-03）。
        let mediaItems = pendingBatch(context, Media.self, collection: "media", order: Self.pendingOrder(\Media.syncStateRaw, \Media.createdAt), predicate: #Predicate {
            ($0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading")
                && $0.entry?.syncStateRaw == "synced" && $0.entry?.remoteId != nil
        })
        for media in mediaItems {
            guard isCurrentRun else { return }
            beginItem(media.type == .video ? "同步视频" : "同步媒体")
            guard let entry = media.entry else {
                media.syncState = .failed
                notePushFailure(APIError.network("找不到这条媒体对应的记录"), collection: "media", id: media.id,
                                label: media.type == .video ? "一段视频" : "一张照片", item: "媒体")
                finishItem()
                saveAndRefresh(context)
                continue
            }
            // 父记录还没在服务器上落地（本轮 POST 失败/尚未轮到）时不先传媒体：
            // 否则家人设备拉到孤儿媒体、补拉父记录得到"不存在"就跳过并推进游标，
            // 等父记录到了媒体的 updated 已落在游标之后，那张照片在那台设备上永远缺失。
            guard entry.remoteId != nil, entry.syncState == .synced else {
                // 保持原状态（.local/.failed 都不改写），只是这一轮先不传；不覆盖已有的失败原因。
                if entry.syncState == .synced, entry.remoteId == nil, !loggedPlaceholderMediaHold {
                    // 占位记录（服务端摄取钩子稍后才创建）暂时没有 remoteId：只记一次日志，避免静默卡住。
                    loggedPlaceholderMediaHold = true
                    recordFailure(APIError.network("这条记录还在等服务器确认，照片稍后自动补传"), item: "媒体")
                }
                finishItem()
                saveAndRefresh(context)
                continue
            }
            await pushMediaItem(media, entryLocalId: entry.id, context: context)
            finishItem()
            saveAndRefresh(context)
        }
    }

    private func pushMediaItem(_ media: Media, entryLocalId: UUID, context: ModelContext) async {
        let label = media.type == .video ? "一段视频" : "一张照片"
        guard let fileName = media.localFileName else {
            media.syncState = .failed
            notePushFailure(APIError.network("本地文件名为空"), collection: "media", id: media.id, label: label, item: "媒体")
            return
        }
        let url = mediaStore.mediaURL(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // 文件丢了（恢复/导入失败）是永久失败：列进同步中心等人处理，不再每轮报红、拖慢整体（D9-03）。
            media.syncState = .failed
            notePushFailure(APIError.network("本地文件不见了"), collection: "media", id: media.id, label: label, item: "媒体")
            return
        }
        if let bytes = mediaStore.fileSize(forMedia: fileName),
           bytes > MediaStore.publicUploadSoftLimitBytes {
            lastLargeFileNotice = "这个\(media.type == .video ? "视频" : "文件")约 \(max(1, bytes / 1_048_576))MB，公网会继续尝试上传，失败后可稍后重试。"
        }
        media.syncState = .uploading
        guard saveAndRefresh(context) else { return }
        let mediaId = media.id
        let mediaType = media.type
        let requestScope = clientScope
        let recoveryKey = SyncLedger.key("media", mediaId)
        var observedRemoteId: String?
        var request = MediaUploadRequest(
            mediaId: media.id, entryLocalId: entryLocalId,
            fileURL: url, type: media.type, fileName: fileName,
            thumbnailURL: media.thumbnailFileName.map { mediaStore.thumbnailURL(for: $0) },
            thumbnailFileName: media.thumbnailFileName,
            contentHash: media.contentHash,
            resourceRole: media.resourceRoleRaw,
            assetGroupId: media.assetGroupID,
            width: media.width,
            height: media.height,
            durationSeconds: media.durationSeconds,
            aiTags: media.aiTags)
        request.createOnly = ledger.isRecovery(recoveryKey)
        do {
            let receipt = try await Self.consumeUpload(apiClient.uploadMedia(request), onProgress: { progress in
                // 删除可能发生在任意一次 await 期间，不再写已经脱离上下文的旧模型。
                if let current = try context.fetch(FetchDescriptor<Media>(
                    predicate: #Predicate { $0.id == mediaId })).first {
                    current.uploadProgress = progress
                    self.currentUploadProgress = progress
                }
            }, onReceipt: { remoteId, _ in observedRemoteId = remoteId })
            if try preserveDeletedUploadReceipt(receipt.remoteId, collection: "media", requestScope: requestScope,
                descriptor: FetchDescriptor<Media>(predicate: #Predicate { $0.id == mediaId }), in: context) {
                return
            }
            try checkRunValidity()
            try Self.completeMediaUpload(localId: mediaId, remoteId: receipt.remoteId,
                                         remoteURL: receipt.remoteURL, in: context)
            ledger.clearAfterPush(recoveryKey)
        } catch {
            // 流已给出完成身份但随后取消/抛错：不确认上传，仍保住已删除记录的补偿意图。
            if let observedRemoteId {
                do {
                    if try preserveDeletedUploadReceipt(observedRemoteId, collection: "media", requestScope: requestScope,
                        descriptor: FetchDescriptor<Media>(predicate: #Predicate { $0.id == mediaId }), in: context) {
                        return
                    }
                } catch {
                    if isCurrentRun { recordFailure(error, item: "保存媒体删除") }
                    return
                }
            }
            guard isCurrentRun else { return }
            if let current = try? context.fetch(FetchDescriptor<Media>(
                predicate: #Predicate { $0.id == mediaId })).first {
                if current.syncState == .uploading { current.syncState = .failed }
            }
            notePushFailure(error, collection: "media", id: mediaId, label: mediaType == .video ? "一段视频" : "一张照片",
                            item: mediaType == .video ? "视频" : "媒体")
        }
    }

    /// 流的正常结束不等于服务器已接收文件；进度到 100% 也不能替代完成回执。
    static func consumeUpload(_ stream: AsyncThrowingStream<UploadEvent, Error>,
                              onProgress: (Double) throws -> Void,
                              onReceipt: (String, String) -> Void = { _, _ in }) async throws -> (remoteId: String, remoteURL: String) {
        try Task.checkCancellation()
        var receipt: (remoteId: String, remoteURL: String)?
        for try await event in stream {
            // 只保留已观察到的服务器身份，供删除补偿；取消后的流依然不能返回成功。
            if case .completed(let remoteId, let remoteURL) = event { onReceipt(remoteId, remoteURL) }
            try Task.checkCancellation()
            switch event {
            case .progress(let progress): try onProgress(progress)
            case .completed(let remoteId, let remoteURL): receipt = (remoteId, remoteURL)
            }
        }
        try Task.checkCancellation()
        guard let receipt else { throw APIError.network("上传未收到完成回执") }
        return receipt
    }

    /// 上传回执只能确认发送时的版本。用户在 await 期间写的新内容仍需补传。
    static func uploadCompletionState(_ current: SyncState) -> SyncState {
        current == .uploading ? .synced : current
    }

    /// 取消不能撤回服务器已经成功的 create。只补已删除本地行的墓碑，不确认内容或写旧模型。
    /// 更换账号 / 服务器 / 上下文后，旧回执绝不能进入新同步目标的删除队列。
    private func preserveDeletedUploadReceipt<Model: PersistentModel>(_ remoteId: String?, collection: String,
        requestScope: String, descriptor: FetchDescriptor<Model>, in context: ModelContext) throws -> Bool {
        guard modelContext === context, clientScope == Self.scope(for: config) else { return false }
        return try Self.persistDeletedUploadReceipt(remoteId, collection: collection, requestScope: requestScope,
            currentScope: clientScope, descriptor: descriptor, in: context)
    }

    @discardableResult
    static func persistDeletedUploadReceipt<Model: PersistentModel>(_ remoteId: String?, collection: String,
        requestScope: String, currentScope: String, descriptor: FetchDescriptor<Model>,
        in context: ModelContext) throws -> Bool {
        guard requestScope == currentScope, try context.fetchCount(descriptor) == 0 else { return false }
        PendingDeletion.enqueue(collection: collection, remoteId: remoteId, in: context)
        // 此处可能已取消；仍需同步保存补偿意图，否则下一轮 pull 会重建已撤销的内容。
        try context.save()
        return true
    }

    /// 回执落库前重新取当前模型；删除意图与补墓碑由调用者在同一次保存中提交。
    static func completeEntryUpload(_ saved: EntryDTO, sent: EntryDTO, localId: UUID, in context: ModelContext) throws {
        guard let entry = try context.fetch(FetchDescriptor<Entry>(
            predicate: #Predicate { $0.id == localId })).first else {
            PendingDeletion.enqueue(collection: "entries", remoteId: saved.id, in: context)
            return
        }
        entry.remoteId = saved.id
        // TextField 等直接绑定可能先改正文，等「完成」才写 .local / editedAt。
        // 因此不能只看状态：回执仅确认发出时的完整载荷，正在输入的内容必须继续留在本机。
        guard entryUploadPayloadMatches(entry, sent: sent) else {
            if entry.editedAt == sent.editedAt { entry.editedAt = .now }
            entry.syncState = .local
            return
        }
        if remoteEntryWins(saved, over: entry) {
            apply(saved, to: entry)
            entry.syncState = .synced
        } else {
            entry.syncState = uploadCompletionState(entry.syncState)
        }
    }

    /// 「全部重传」恢复模式的回执：服务器带回的就是权威版本（服务器原本没有时就是本机内容本身），
    /// 本机采用它并标 synced；等待期间用户又改了，则保留本机改动按正常编辑时间比对再推。
    static func completeRecoveredEntryUpload(_ saved: EntryDTO, sent: EntryDTO, localId: UUID, in context: ModelContext) throws {
        guard let entry = try context.fetch(FetchDescriptor<Entry>(
            predicate: #Predicate { $0.id == localId })).first else {
            PendingDeletion.enqueue(collection: "entries", remoteId: saved.id, in: context)
            return
        }
        entry.remoteId = saved.id
        guard entryUploadPayloadMatches(entry, sent: sent) else {
            if entry.editedAt == sent.editedAt { entry.editedAt = .now }
            entry.syncState = .local
            return
        }
        apply(saved, to: entry)
        entry.syncState = .synced
    }

    private static func entryUploadPayloadMatches(_ entry: Entry, sent: EntryDTO) -> Bool {
        entry.title == sent.title &&
        entry.note == sent.note &&
        entry.firstPersonNote == sent.firstPersonNote &&
        entry.happenedAt == sent.happenedAt &&
        entry.locationName == sent.locationName &&
        entry.latitude == sent.latitude &&
        entry.longitude == sent.longitude &&
        entry.authorRole == sent.authorRole &&
        entry.moodRaw == sent.mood &&
        entry.isArchived == sent.isArchived &&
        entry.inStorybook == sent.inStorybook &&
        entry.editedAt == sent.editedAt &&
        entry.createdAt == sent.createdAt
    }

    static func completeMediaUpload(localId: UUID, remoteId: String, remoteURL: String,
                                    in context: ModelContext) throws {
        guard let media = try context.fetch(FetchDescriptor<Media>(
            predicate: #Predicate { $0.id == localId })).first else {
            PendingDeletion.enqueue(collection: "media", remoteId: remoteId, in: context)
            return
        }
        media.remoteId = remoteId
        media.remoteURL = remoteURL
        media.uploadProgress = 1
        media.syncState = uploadCompletionState(media.syncState)
    }

    private func pushTimeCapsules(_ context: ModelContext) async {
        let capsules = pendingBatch(context, TimeCapsule.self, collection: "timecapsules", order: Self.pendingOrder(\TimeCapsule.syncStateRaw, \TimeCapsule.createdAt), predicate: #Predicate {
            $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading"
        })
        for capsule in capsules {
            guard isCurrentRun else { return }
            beginItem("同步时间胶囊")
            let capsuleId = capsule.id
            let requestScope = clientScope
            do {
                capsule.syncState = .uploading
                saveAndRefresh(context)
                var dto = Self.makeDTO(capsule)
                let version = outgoingVersion("timecapsules", capsuleId, createdAt: capsule.createdAt)
                dto.clientEditedAt = version.editedAt; dto.createOnly = version.createOnly
                var saved = try await apiClient.upsertTimeCapsule(dto)
                if try preserveDeletedUploadReceipt(saved.id, collection: "timecapsules", requestScope: requestScope,
                    descriptor: FetchDescriptor<TimeCapsule>(predicate: #Predicate { $0.id == capsuleId }), in: context) {
                    finishItem()
                    continue
                }
                try checkRunValidity()
                capsule.remoteId = saved.id
                let keptRemote = Self.remoteVersionWasKept(sent: version.editedAt, returned: saved.clientEditedAt,
                                                           createOnly: version.createOnly)
                if !(keptRemote && saved.encryptedBlobRemoteURL != nil), let fileName = capsule.encryptedBlobFileName {
                    let url = mediaStore.mediaURL(for: fileName)
                    // 密文丢了不能标 synced：否则服务端只剩一条没有文件的胶囊记录（永久失败，进同步中心）。
                    guard FileManager.default.fileExists(atPath: url.path) else { throw APIError.network("本地文件不见了") }
                    let receipt = try await Self.consumeUpload(apiClient.uploadTimeCapsuleBlob(
                        capsuleId: capsule.id,
                        dto: dto,
                        fileURL: url,
                        fileName: fileName
                    ), onProgress: { self.currentUploadProgress = $0 })
                    try checkRunValidity()
                    saved.id = receipt.remoteId
                    saved.encryptedBlobRemoteURL = receipt.remoteURL
                }
                guard try context.fetchCount(FetchDescriptor<TimeCapsule>(predicate: #Predicate { $0.id == capsuleId })) > 0 else {
                    PendingDeletion.enqueue(collection: "timecapsules", remoteId: saved.id, in: context)
                    finishItem()
                    saveAndRefresh(context)
                    continue
                }
                capsule.remoteId = saved.id
                capsule.syncState = Self.uploadCompletionState(capsule.syncState)
                finishPushBookkeeping("timecapsules", capsuleId, state: capsule.syncState)
            } catch {
                guard isCurrentRun else { return }
                if let current = try? context.fetch(FetchDescriptor<TimeCapsule>(predicate: #Predicate { $0.id == capsuleId })).first {
                    if current.syncState == .uploading { current.syncState = .failed }
                }
                notePushFailure(error, collection: "timecapsules", id: capsuleId, label: "时间胶囊", item: "时间胶囊")
            }
            finishItem()
            saveAndRefresh(context)
        }
    }

    // MARK: - 拉：远端 → 本地

    /// 每个集合独立游标：成功才推进，失败下次补拉，互不影响。
    /// 一个集合本轮拉回来的原始数据（网络阶段产物，尚未落库）。
    private struct PulledBatch<DTO: SyncCursorProviding>: Sendable {
        var items: [DTO] = []
        var tombstones: [RemoteTombstone] = []
        /// 网络失败：合并阶段据此标软失败并保持游标不动。
        var failed = false
        /// 服务端没有这个集合（老服务器）：静默跳过，不算失败。
        var missingCollection = false
    }

    /// 网络阶段：把一个集合的「列表 + 墓碑」取回来，不碰数据库。
    /// 失败在这里被吸收成标记位，让并发阶段不会因为一个集合抖动而整体抛出。
    private func fetchBatch<DTO: SyncCursorProviding>(
        _ collection: String,
        fetch: @escaping @Sendable (Date?) async throws -> [DTO]
    ) async -> PulledBatch<DTO> {
        collectionProgress[collection] = CollectionProgress(id: collection)
        do {
            try checkRunValidity()
            let since = try cursor(for: collection)
            let api = apiClient
            async let itemsTask = fetch(since)
            async let tombstonesTask = api.fetchDeletedTombstones(collection: collection, since: since)
            let batch = PulledBatch(items: try await itemsTask, tombstones: try await tombstonesTask)
            try checkRunValidity()
            return batch
        } catch {
            guard isCurrentRun else { return PulledBatch(failed: true) }
            collectionProgress[collection]?.state = "稍后重试"
            if Self.isMissingOptionalServerCollection(error, collection: collection) {
                return PulledBatch(missingCollection: true)
            }
            // 以前这里只 return failed 标记位，不记录失败原因：
            // 于是「每个集合的每一次拉取都 400」这种故障（2026-07 的 autodate 事故就是）
            // 在界面上完全不可见，同步中心照样显示绿勾「全部同步好了」，静默了几个月。
            // recordFailure 内部会把网络抖动、缺可选集合这类归成软失败，
            // 真正的服务端错误才会落到 lastFailureReason。
            recordFailure(error, item: "拉取 \(collection)")
            return PulledBatch(failed: true)
        }
    }

    /// 拉取远端：**网络并发、合并顺序**。
    ///
    /// 原来 13 个集合串行 await，每个还各带一次墓碑查询 = 26+ 次串行往返。
    /// 走公网隧道时单次往返实测 0.65 秒，一轮空同步光路由就要 17~30 秒（人在外面尤其明显）。
    /// 现在用 async let 让所有集合的网络请求同时出发，墙上时间压到「最慢的那一次」；
    /// 合并仍按原顺序逐个执行——**顺序不能动**：media 依赖父 entry 已落库，
    /// 里程碑归一化必须在里程碑合并之后。
    private func pullRemote() async {
        guard isCurrentRun else { return }
        let api = apiClient
        async let entriesBatch = fetchBatch("entries") { try await api.fetchEntries(since: $0) }
        async let mediaBatch = fetchBatch("media") { try await api.fetchMedia(since: $0) }
        async let milestonesBatch = fetchBatch("milestones") { try await api.fetchMilestones(since: $0) }
        async let firstTimesBatch = fetchBatch("firsttimes") { try await api.fetchFirstTimes(since: $0) }
        async let membersBatch = fetchBatch("members") { try await api.fetchFamilyMembers(since: $0) }
        async let profilesBatch = fetchBatch("childprofile") { try await api.fetchChildProfiles(since: $0) }
        async let healthBatch = fetchBatch("healthrecords") { try await api.fetchHealthRecords(since: $0) }
        async let vaccinesBatch = fetchBatch("vaccinerecords") { try await api.fetchVaccineRecords(since: $0) }
        async let growthBatch = fetchBatch("growthmeasurements") { try await api.fetchGrowthMeasurements(since: $0) }
        async let commentsBatch = fetchBatch("comments") { try await api.fetchComments(since: $0) }
        async let voiceNotesBatch = fetchBatch("voicenotes") { try await api.fetchVoiceNotes(since: $0) }
        async let voiceMemosBatch = fetchBatch("voicememos") { try await api.fetchVoiceMemos(since: $0) }
        async let capsulesBatch = fetchBatch("timecapsules") { try await api.fetchTimeCapsules(since: $0) }

        await apply(await entriesBatch, collection: "entries") { try await self.mergeRemoteEntry($0) }
        await apply(await mediaBatch, collection: "media") { try await self.mergeRemoteMedia($0) }
        await apply(await milestonesBatch, collection: "milestones") { try await self.mergeRemoteMilestone($0) }
        guard isCurrentRun else { return }
        if let context = modelContext {
            do { try normalizeMilestonesByTitle(context) }
            catch { recordFailure(error, item: "核对里程碑") }
        }
        await apply(await firstTimesBatch, collection: "firsttimes") { try await self.mergeRemoteFirstTime($0) }
        await apply(await membersBatch, collection: "members") { try await self.mergeRemoteMember($0) }
        await apply(await profilesBatch, collection: "childprofile") { try await self.mergeRemoteChildProfile($0) }
        await apply(await healthBatch, collection: "healthrecords") { try await self.mergeRemoteHealth($0) }
        await apply(await vaccinesBatch, collection: "vaccinerecords") { try await self.mergeRemoteVaccine($0) }
        await apply(await growthBatch, collection: "growthmeasurements") { try await self.mergeRemoteGrowth($0) }
        await apply(await commentsBatch, collection: "comments") { try await self.mergeRemoteComment($0) }
        await apply(await voiceNotesBatch, collection: "voicenotes") { try await self.mergeRemoteVoiceNote($0) }
        await apply(await voiceMemosBatch, collection: "voicememos") { try await self.mergeRemoteVoiceMemo($0) }
        await apply(await capsulesBatch, collection: "timecapsules") { try await self.mergeRemoteTimeCapsule($0) }
        guard isCurrentRun else { return }
        reapplyDeferredTombstones()
    }

    /// 本次 pull 是否挂起游标推进：merge 过程中出现「可恢复但本轮没消费成功」的记录
    /// （如孤儿媒体补拉父记录时网络失败）时置位——游标停在原地，下轮从同一窗口幂等重拉，
    /// 杜绝「游标推过去、记录再也拉不到」的永久丢失（存储 P0-1）。
    private var holdCursorForCurrentPull = false

    /// 合并阶段：把一个集合已取回的数据落库并推进游标。全程在 MainActor 上顺序执行。
    private func apply<DTO: SyncCursorProviding>(_ batch: PulledBatch<DTO>,
                                                 collection: String,
                                                 merge: (DTO) async throws -> Bool) async {
        guard isCurrentRun else { return }
        if batch.missingCollection {
            collectionProgress[collection]?.state = "服务端暂未提供"
            return
        }
        if batch.failed {
            // 瞬时拉取失败不立刻报红：标记本轮软失败，游标不推进，下轮自动补拉。
            softFailureThisRun = true
            return
        }
        holdCursorForCurrentPull = false
        // 远端游标与「本地脏记录是否全部消费」解耦（S-P2）：这一轮把远端项全部拉回并逐条尝试合并后，
        // 游标就按「本轮拉到的最大服务器 updated」前进。本地未推的脏记录/永久 .failed 记录合并返回 false
        // 只影响它是否落库，不再卡住整集合游标造成每轮从头全量重拉——那些记录由 pushLocal 负责收敛。
        var maxUpdated: Date? = nil
        for dto in batch.items {
            guard isCurrentRun else { return }
            do {
                _ = try await merge(dto)
                try checkRunValidity()
            }
            catch {
                holdCursorForCurrentPull = true
                collectionProgress[collection]?.state = "本地读取待重试"
                recordFailure(error, item: "合并同步记录")
                return
            }
            maxUpdated = Self.laterDate(maxUpdated, dto.serverUpdatedAt)
        }
        guard isCurrentRun else { return }
        // tombstone 传播：别的设备删掉的，这台也要删（R4 P1-8）。
        // 墓碑的服务器 updated 同样参与游标推进，避免「本轮只有删除」时游标停滞、每轮重复拉同一批墓碑。
        if !batch.tombstones.isEmpty {
            do {
                let skipped = try removeLocals(collection: collection, localIds: batch.tombstones.map(\.localId))
                // 游标会越过这些墓碑：记下来，之后每轮补删。
                ledger.deferTombstones(collection: collection, localIds: skipped)
            }
            catch {
                holdCursorForCurrentPull = true
                collectionProgress[collection]?.state = "删除标记待重试"
                recordFailure(error, item: "保存删除标记")
                return
            }
            for t in batch.tombstones { maxUpdated = Self.laterDate(maxUpdated, t.serverUpdatedAt) }
        }
        // 游标推进用「本轮拉到的最大服务器 updated」（服务器单一权威时钟，与过滤字段 updated 同参照系），
        // 而非本机 Date.now——杜绝读设备时钟偏移把游标推过头、写设备刚写的记录被判旧而永久跳过（S-P1-1）。
        // setCursor 内部回退 60 秒重叠余量，边界不丢记录、自我重拉幂等（localId 去重 + merge 见已 synced 不回退）。
        // 无 context 时不推进（没落库不能推进游标）；本轮无任何新记录/墓碑则游标保持不动（下轮空查询极廉价）。
        // 落盘失败时绝不把增量游标写到 UserDefaults，否则重启后会永久越过未保存记录。
        guard let context = modelContext else { return }
        // 各 mergeRemote* 不再逐条 save（每次 save 都触发时光轴 @Query 重建，首轮 2000 条会卡死主线程）：
        // 同一主上下文里 fetch 默认含未保存改动，整集合在这里随游标一次落盘（失败不推进游标，下轮幂等重拉）。
        if context.hasChanges { changedThisRun = true }
        do {
            if let maxUpdated, !holdCursorForCurrentPull {
                try SyncCheckpoint.commit(key: checkpointKey(for: collection), generation: checkpointGeneration,
                                          updated: maxUpdated.addingTimeInterval(-Self.cursorOverlap), in: context) {
                    try context.save()
                }
            } else {
                guard saveAndRefresh(context) else {
                    collectionProgress[collection]?.state = "本地保存待重试"
                    return
                }
            }
            collectionProgress[collection] = CollectionProgress(id: collection, received: batch.items.count,
                                                                deleted: batch.tombstones.count,
                                                                state: holdCursorForCurrentPull ? "有内容待补拉" : "已核对")
        } catch {
            holdCursorForCurrentPull = true
            collectionProgress[collection]?.state = "本地保存待重试"
            recordFailure(error, item: "保存同步进度")
        }
    }

    /// 取两个可选时间里较晚的一个（nil 视作无约束）。
    private static func laterDate(_ a: Date?, _ b: Date?) -> Date? {
        guard let a else { return b }
        guard let b else { return a }
        return max(a, b)
    }

    /// 远端 tombstone → 删除本地对应记录与文件。
    /// members 不自动删（历史上没有删除入口）。childprofile 只在本机还剩至少一份档案时才删——
    /// 这样服务器端把重复档案软删除后能传播到全家，又绝不会把这台设备的最后一份档案删掉（D9-01）。
    ///
    /// 冲突策略（S-P2）：只删「本地已 synced」的记录。若本地这条有未推送的改动（syncState != .synced，
    /// 用户刚写还没传上去），则「保留本地、跳过删除」——本地编辑优先，绝不静默吞掉用户刚写的东西；
    /// 该记录随后由 pushLocal 继续收敛。删除依然会传播（synced 的记录照删），只是不越过本地未推编辑。
    @discardableResult
    private func removeLocals(collection: String, localIds: [String]) throws -> [String] {
        guard let context = modelContext, !localIds.isEmpty else { return [] }
        var skippedDirty = false
        var skippedIds: [String] = []
        var deletedAny = false
        var files: [(String?, String?)] = []
        /// 有本地未推改动（非 synced）就保留、跳过删除；返回 true 表示「已保留、不要删」。
        var currentId = ""
        func keepIfDirty(_ state: SyncState) -> Bool {
            guard state != .synced else { return false }
            skippedDirty = true
            skippedIds.append(currentId)
            return true
        }
        /// 本地文件已经丢失、永远传不上去的媒体不该挡住家人的删除（否则那条记录永远删不掉）。
        func blocksDeletion(_ media: Media) -> Bool {
            guard media.syncState != .synced else { return false }
            guard let name = media.localFileName else { return false }
            return mediaStore.fileExists(forMedia: name)
        }
        for localId in localIds {
            guard let uuid = UUID(uuidString: localId) else { continue }
            currentId = localId
            let deletedBefore = context.deletedModelsArray.count
            defer { if context.deletedModelsArray.count > deletedBefore { deletedAny = true } }
            switch collection {
            case "entries":
                if let obj = (try context.fetch(FetchDescriptor<Entry>(
                    predicate: #Predicate { $0.id == uuid }))).first {
                    if keepIfDirty(obj.syncState) { continue }
                    if obj.media.contains(where: blocksDeletion) || obj.comments.contains(where: { $0.syncState != .synced }) || obj.voiceNotes.contains(where: { $0.syncState != .synced }) {
                        skippedDirty = true
                        skippedIds.append(localId)
                        continue
                    }
                    for m in obj.media {
                        files.append((m.localFileName, m.thumbnailFileName))
                    }
                    for v in obj.voiceNotes {
                        files.append((v.localFileName, nil))
                    }
                    context.delete(obj)   // 级联删除 media/comments/voiceNotes 行
                }
            case "media":
                if let obj = (try context.fetch(FetchDescriptor<Media>(
                    predicate: #Predicate { $0.id == uuid }))).first {
                    if keepIfDirty(obj.syncState) { continue }
                    files.append((obj.localFileName, obj.thumbnailFileName))
                    context.delete(obj)
                }
            case "milestones":
                if let obj = (try context.fetch(FetchDescriptor<Milestone>(
                    predicate: #Predicate { $0.id == uuid }))).first {
                    if keepIfDirty(obj.syncState) { continue }
                    context.delete(obj)
                }
            case "firsttimes":
                if let obj = (try context.fetch(FetchDescriptor<FirstTime>(
                    predicate: #Predicate { $0.id == uuid }))).first {
                    if keepIfDirty(obj.syncState) { continue }
                    context.delete(obj)
                }
            case "healthrecords":
                if let obj = (try context.fetch(FetchDescriptor<HealthRecord>(
                    predicate: #Predicate { $0.id == uuid }))).first {
                    if keepIfDirty(obj.syncState) { continue }
                    context.delete(obj)
                }
            case "vaccinerecords":
                if let obj = (try context.fetch(FetchDescriptor<VaccineRecord>(
                    predicate: #Predicate { $0.id == uuid }))).first {
                    if keepIfDirty(obj.syncState) { continue }
                    context.delete(obj)
                }
            case "growthmeasurements":
                if let obj = (try context.fetch(FetchDescriptor<GrowthMeasurement>(
                    predicate: #Predicate { $0.id == uuid }))).first {
                    if keepIfDirty(obj.syncState) { continue }
                    context.delete(obj)
                }
            case "comments":
                if let obj = (try context.fetch(FetchDescriptor<Comment>(
                    predicate: #Predicate { $0.id == uuid }))).first {
                    if keepIfDirty(obj.syncState) { continue }
                    context.delete(obj)
                }
            case "voicenotes":
                if let obj = (try context.fetch(FetchDescriptor<VoiceNote>(
                    predicate: #Predicate { $0.id == uuid }))).first {
                    if keepIfDirty(obj.syncState) { continue }
                    files.append((obj.localFileName, nil))
                    context.delete(obj)
                }
            case "voicememos":
                if let obj = (try context.fetch(FetchDescriptor<VoiceMemo>(
                    predicate: #Predicate { $0.id == uuid }))).first {
                    if keepIfDirty(obj.syncState) { continue }
                    files.append((obj.localFileName, nil))
                    context.delete(obj)
                }
            case "timecapsules":
                if let obj = (try context.fetch(FetchDescriptor<TimeCapsule>(
                    predicate: #Predicate { $0.id == uuid }))).first {
                    if keepIfDirty(obj.syncState) { continue }
                    files.append((obj.encryptedBlobFileName, nil))
                    context.delete(obj)
                }
            case "childprofile":
                if let obj = (try context.fetch(FetchDescriptor<ChildProfile>(
                    predicate: #Predicate { $0.id == uuid }))).first {
                    if keepIfDirty(obj.syncState) { continue }
                    // 绝不删最后一份；被删的若是本机固定使用的那份，让选择器回到「最早的一份」。
                    guard try context.fetchCount(FetchDescriptor<ChildProfile>()) > 1 else { continue }
                    if SharedDefaults.canonicalChildProfileID == obj.id { SharedDefaults.canonicalChildProfileID = nil }
                    files.append((obj.avatarMediaFileName, nil))
                    context.delete(obj)
                }
            default:
                break
            }
            // 记录没了，指着它的家庭动态也该走：否则「最近」和手表快照
            // （两者都以 FeedEvent 为源）会永久显示一条已删除的内容。
            // 手表 undo 侧早已这么做（undoRecord），这里补齐墓碑侧。
            if collection == "entries" || collection == "healthrecords" {
                let target = localId
                let events = try context.fetch(FetchDescriptor<FeedEvent>(
                    predicate: #Predicate { $0.targetLocalId == target }))
                for event in events { context.delete(event) }
            }
        }
        // 先提交数据库，再清理文件；落盘失败时原片仍然保留。
        if deletedAny { changedThisRun = true }
        try context.save()
        for (media, thumbnail) in files { mediaStore.deleteLocalFiles(media: media, thumbnail: thumbnail) }
        // 有本地未推编辑因远端删除被保留：给用户一个平和提示，避免「远端删了但这台还在」显得诡异。
        if skippedDirty {
            softNotice = "有几项别处删掉了，但这里还有没传上去的改动，先替你留着。"
        }
        return skippedIds
    }

    /// 补删之前被跳过的远端删除标记：本机改动传完 / 卡住的文件处理掉之后，删除照样生效（D9-03）。
    /// 仍被挡住的继续留账；本地已不存在的自然清掉。
    private func reapplyDeferredTombstones() {
        for (collection, ids) in ledger.deferredTombstones() {
            guard isCurrentRun else { return }
            do {
                let stillBlocked = try removeLocals(collection: collection, localIds: ids)
                ledger.replaceDeferredTombstones(collection: collection, localIds: stillBlocked)
            } catch {
                recordFailure(error, item: "保存删除标记")
                return
            }
        }
    }

    private static func isMissingOptionalServerCollection(_ error: Error, collection: String) -> Bool {
        guard case APIError.server(let code, _) = error, code == 404 else { return false }
        return collection == "vaccinerecords" || collection == "growthmeasurements"
    }

    // MARK: - 下载：把远端媒体/语音落到本地（离线优先对多设备同样成立）

    /// 一轮内连续补拉缺失文件，用时间预算封顶而不是固定条数。
    ///
    /// 旧实现是 `prefix(8)`：每轮只下 8 个，配合 30 秒的同步循环，
    /// 导入历史存量（两千多个媒体）要跑几百轮、两个多小时，且必须一直前台开着。
    /// 改成时间预算后，一轮能连续下完能下的量；所有入口共用 `syncRuns` 许可，
    /// 单轮跑久不会和前台 / 后台 / 手动补传叠加。日常增量只有几个文件，一样是秒回。
    private static let downloadBudget: TimeInterval = 120
    private static let downloadCountCap = 500

    /// 下载发出时的资源身份与目标槽；await 返回后必须重新取模型并核对，不能写旧对象。
    struct MediaDownloadSnapshot: Sendable {
        let id: UUID
        let remoteId: String?
        let remoteURL: String?
        let remoteThumbURL: String?
        let localFileName: String?
        let thumbnailFileName: String?
        let typeRaw: String
        let syncStateRaw: String
        let createdAt: Date

        @MainActor init(_ media: Media) {
            id = media.id
            remoteId = media.remoteId
            remoteURL = media.remoteURL
            remoteThumbURL = media.remoteThumbURL
            localFileName = media.localFileName
            thumbnailFileName = media.thumbnailFileName
            typeRaw = media.typeRaw
            syncStateRaw = media.syncStateRaw
            createdAt = media.createdAt
        }

        @MainActor func matches(_ media: Media) -> Bool {
            media.remoteId == remoteId && media.remoteURL == remoteURL &&
            media.remoteThumbURL == remoteThumbURL && media.localFileName == localFileName &&
            media.thumbnailFileName == thumbnailFileName && media.typeRaw == typeRaw &&
            media.syncStateRaw == syncStateRaw && media.createdAt == createdAt
        }
    }

    /// 单个文件下载任务的输入（只含 Sendable 值，供任务组子任务使用）。
    private struct DownloadSpec: Sendable {
        let snapshot: MediaDownloadSnapshot
        let remoteURL: String
        let thumb: String?          // PocketBase ?thumb= 尺寸串；nil = 原文件
        let ext: String
        let sniff: Bool
        let makePhotoThumb: Bool
        let makeVideoThumb: Bool
        let assignAsThumbnailOnly: Bool  // true：下到的文件写入 thumbnailFileName（预览小图通道）
    }

    struct DownloadOutcome: Sendable {
        let snapshot: MediaDownloadSnapshot
        let fileName: String?
        let thumbName: String?
        let assignAsThumbnailOnly: Bool
        /// 下载失败且服务端 404 时记下地址（永久缺失）。
        var missingURL: String? = nil
    }

    nonisolated static func isMissingRemoteFile(_ error: Error) -> Bool {
        if case APIError.server(404, _) = error { return true }
        return false
    }

    /// 补文件失败：404 记入永久缺失跳过名单，其余算瞬时软失败。
    private func noteDownloadFailure(_ error: Error, remoteURL: String) {
        if Self.isMissingRemoteFile(error) { missingRemoteFiles.insert(remoteURL) } else { softFailureThisRun = true }
    }

    /// 下载 + 落盘 + 缩略图生成，全程在非主执行器上跑（MediaStore 是 Sendable struct）。
    /// @concurrent：approachable-concurrency 下 nonisolated async 默认继承调用方执行器，
    /// 必须显式切到全局并发执行器，图片解码/JPEG 编码才真正离开主线程。
    @concurrent
    private nonisolated static func fetchFileOffMain(api: any APIClient, store: MediaStore,
                                                     spec: DownloadSpec) async -> DownloadOutcome {
        do {
            let tempURL = try await api.downloadFileToTemporaryURL(from: spec.remoteURL, thumb: spec.thumb)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            try Task.checkCancellation()
            // 预览小图通道落 Thumbnails/，原图通道落 Media/。两者目录必须与字段语义一致：
            // 写进 thumbnailFileName 的文件名，只会被 thumbnailURL / 小组件的缩略图目录去解析。
            let name = spec.assignAsThumbnailOnly
                ? try store.importThumbnail(from: tempURL, preferredExtension: spec.ext)
                : try store.importFile(from: tempURL, preferredExtension: spec.ext, sniffImage: spec.sniff)
            var thumbName: String? = nil
            if spec.makePhotoThumb,
               let image = ThumbnailProvider.downsample(url: store.mediaURL(for: name), maxPixel: 600) {
                thumbName = store.makePhotoThumbnail(fromImage: image)
            } else if spec.makeVideoThumb {
                thumbName = await store.makeVideoThumbnail(fromVideo: name)
            }
            return DownloadOutcome(snapshot: spec.snapshot, fileName: name, thumbName: thumbName,
                                   assignAsThumbnailOnly: spec.assignAsThumbnailOnly)
        } catch {
            return DownloadOutcome(snapshot: spec.snapshot, fileName: nil, thumbName: nil,
                                   assignAsThumbnailOnly: spec.assignAsThumbnailOnly,
                                   missingURL: isMissingRemoteFile(error) ? spec.remoteURL : nil)
        }
    }

    /// 丢弃的下载只清理本次新生成的文件，保留用户在等待期间选择的替代文件。
    @discardableResult
    static func completeMediaDownload(_ outcome: DownloadOutcome, in context: ModelContext,
                                      store: MediaStore, isCurrentRun: Bool = true) throws -> Bool {
        var accepted = false
        defer {
            if !accepted {
                store.deleteLocalFiles(media: outcome.assignAsThumbnailOnly ? nil : outcome.fileName,
                                       thumbnail: outcome.assignAsThumbnailOnly ? outcome.fileName : outcome.thumbName)
            }
        }
        let localId = outcome.snapshot.id
        guard isCurrentRun, !Task.isCancelled, let name = outcome.fileName,
              let current = try context.fetch(FetchDescriptor<Media>(
                predicate: #Predicate { $0.id == localId })).first,
              outcome.snapshot.matches(current) else { return false }
        if outcome.assignAsThumbnailOnly {
            current.thumbnailFileName = name
        } else {
            current.localFileName = name
            if let thumb = outcome.thumbName { current.thumbnailFileName = thumb }
        }
        accepted = true
        return true
    }

    /// 并发跑一批下载（固定并发度 + 截止时间），结果回主线程逐条落库。
    private func runDownloadBatch(_ specs: [DownloadSpec],
                                  context: ModelContext, concurrency: Int,
                                  deadline: Date, label: String) async {
        let specs = specs.filter { !missingRemoteFiles.contains($0.remoteURL) }
        guard !specs.isEmpty else { return }
        let api = apiClient
        let store = mediaStore
        let total = specs.count
        var done = 0
        var nextIndex = 0
        await withTaskGroup(of: DownloadOutcome.self) { group in
            func addNext(ifCurrent current: Bool) {
                // 局部函数不会继承 MainActor 隔离；由调用点读取作用域，只传 Sendable 值。
                guard nextIndex < specs.count, Date() < deadline, current, !Task.isCancelled else { return }
                let spec = specs[nextIndex]; nextIndex += 1
                group.addTask { await Self.fetchFileOffMain(api: api, store: store, spec: spec) }
            }
            for _ in 0..<min(concurrency, specs.count) { addNext(ifCurrent: isCurrentRun) }
            for await outcome in group {
                do {
                    if try Self.completeMediaDownload(outcome, in: context, store: store, isCurrentRun: isCurrentRun) {
                        done += 1
                        saveAndRefresh(context)
                    } else if outcome.fileName == nil, isCurrentRun {
                        // 下载失败属瞬时、可自愈（404 除外：记入跳过名单）；过时或已删除记录的成功结果已清理，不重建模型。
                        if let missing = outcome.missingURL { missingRemoteFiles.insert(missing) } else { softFailureThisRun = true }
                    }
                } catch {
                    recordFailure(error, item: "保存下载")
                }
                currentSyncLabel = total > 20 ? "\(label) \(done)/\(total)" : label
                addNext(ifCurrent: isCurrentRun)
            }
        }
    }

    /// Page through remote-backed rows so a full first page of healthy files cannot hide older missing originals.
    /// A filename belonging to an unsynced edit is never replaced by a remote copy.
    static func mediaNeedingDownload(in context: ModelContext, limit: Int,
                                     fileExists: (String) -> Bool) throws -> [Media] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<Media>(
            predicate: #Predicate { $0.remoteURL != nil && ($0.localFileName == nil || $0.syncStateRaw == "synced") },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = downloadCountCap
        var result: [Media] = []
        while !Task.isCancelled {
            let batch = try context.fetch(descriptor)
            // 已删除（归档）记录的原图不再下载到每台设备（D9-14）。
            for media in batch where media.entry?.isArchived != true && MediaFileAvailability.needsDownload(
                fileName: media.localFileName, remoteURL: media.remoteURL,
                isSynced: media.syncState == .synced, exists: fileExists) {
                result.append(media)
                if result.count == limit { return result }
            }
            if batch.count < downloadCountCap { break }
            descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + batch.count
        }
        return result
    }

    private func downloadMissingFiles(_ context: ModelContext) async {
        let deadline = Date().addingTimeInterval(Self.downloadBudget)

        // 每个阶段重新取待补文件（新的在前）；跨 await 不再复用可能已删除的模型引用。
        // 全表扫描（2000+ 行 × stat）只在有新媒体合并进来、上次没下完或 30 分钟兜底时做（D4-04）。
        let scanDue = downloadScanNeeded ||
            Date.now.timeIntervalSince(lastFullDownloadScanAt) > Self.downloadScanSafetyInterval
        // ponytail: 404 跳过名单在取上限之后过滤；坏文件超过 500 个才会挤占，届时再下推到查询里。
        let pendingMedia = scanDue ? ((try? Self.mediaNeedingDownload(in: context, limit: Self.downloadCountCap,
            fileExists: mediaStore.fileExists(forMedia:))) ?? []).filter { !missingRemoteFiles.contains($0.remoteURL ?? "") } : []
        if scanDue {
            lastFullDownloadScanAt = .now
            // 这一轮全部下完会在下一轮复扫确认；扫到 0 个才放下标记。
            downloadScanNeeded = !pendingMedia.isEmpty
        }
        let pendingPhotos = pendingMedia.filter { $0.type == .photo }
        let pendingOthers = pendingMedia.filter { $0.type != .photo }
        let candidateIDs = pendingMedia.map(\.id)
        let refreshedDescriptor = FetchDescriptor<Media>(
            predicate: #Predicate { candidateIDs.contains($0.id) },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])

        // ===== 阶段 0 · 预览秒出 =====
        // 缺图照片先拉 PocketBase 服务端小图（?thumb=600x0，几十 KB/张）：
        // 时光轴几秒内全部出预览，原图之后慢慢补。这是「同步来的照片一直是占位图」的根治。
        // 视频：上传端 1.8+ 会把缩略图传到服务端 thumbnail 字段——有 remoteThumbURL 的
        // 视频同样先拉预览小图，不用等几十 MB 的原片。
        var thumbSpecs: [DownloadSpec] = pendingPhotos
            .filter { $0.thumbnailFileName == nil }
            .compactMap { m in
                guard let url = m.remoteURL else { return nil }
                return DownloadSpec(snapshot: MediaDownloadSnapshot(m), remoteURL: url, thumb: "600x0", ext: "jpg", sniff: true,
                                    makePhotoThumb: false, makeVideoThumb: false, assignAsThumbnailOnly: true)
            }
        thumbSpecs += pendingOthers
            .filter { $0.thumbnailFileName == nil }
            .compactMap { m in
                guard let thumbURL = m.remoteThumbURL else { return nil }
                return DownloadSpec(snapshot: MediaDownloadSnapshot(m), remoteURL: thumbURL, thumb: nil, ext: "jpg", sniff: true,
                                    makePhotoThumb: false, makeVideoThumb: false, assignAsThumbnailOnly: true)
            }
        await runDownloadBatch(thumbSpecs, context: context,
                               concurrency: 4, deadline: deadline, label: "同步预览图")

        // ===== 阶段 1 · 照片原图（新的先下，并发 3） =====
        // 预览 await 期间可能发生删除/替换；下一阶段重新取当前模型，不再读旧数组中的引用。
        guard isCurrentRun else { return }
        let currentPhotos = ((try? context.fetch(refreshedDescriptor)) ?? []).filter {
            $0.type == .photo && MediaFileAvailability.needsDownload(fileName: $0.localFileName,
                remoteURL: $0.remoteURL, isSynced: $0.syncState == .synced, exists: mediaStore.fileExists(forMedia:))
        }
        let photoSpecs: [DownloadSpec] = currentPhotos.compactMap { m in
            guard let url = m.remoteURL else { return nil }
            return DownloadSpec(snapshot: MediaDownloadSnapshot(m), remoteURL: url,
                                thumb: nil, ext: Self.pathExtension(from: url, fallback: "jpg"), sniff: true,
                                makePhotoThumb: m.thumbnailFileName == nil, makeVideoThumb: false,
                                assignAsThumbnailOnly: false)
        }
        await runDownloadBatch(photoSpecs, context: context,
                               concurrency: 3, deadline: deadline, label: "下载照片")

        // ===== 阶段 2 · 视频/其它原文件（并发 2，排最后不堵照片） =====
        guard isCurrentRun else { return }
        let currentOthers = ((try? context.fetch(refreshedDescriptor)) ?? []).filter {
            $0.type != .photo && MediaFileAvailability.needsDownload(fileName: $0.localFileName,
                remoteURL: $0.remoteURL, isSynced: $0.syncState == .synced, exists: mediaStore.fileExists(forMedia:))
        }
        let videoSpecs: [DownloadSpec] = currentOthers.compactMap { m in
            guard let url = m.remoteURL else { return nil }
            return DownloadSpec(snapshot: MediaDownloadSnapshot(m), remoteURL: url,
                                thumb: nil, ext: Self.pathExtension(from: url, fallback: "mp4"), sniff: false,
                                makePhotoThumb: false, makeVideoThumb: m.type == .video,
                                assignAsThumbnailOnly: false)
        }
        await runDownloadBatch(videoSpecs, context: context,
                               concurrency: 2, deadline: deadline, label: "下载视频")

        let notes = (try? context.fetch(FetchDescriptor<VoiceNote>(
            predicate: #Predicate { $0.localFileName == nil && $0.remoteURL != nil }))) ?? []
        for note in notes.filter({ !missingRemoteFiles.contains($0.remoteURL ?? "") }).prefix(10) {
            guard isCurrentRun, Date() < deadline else { return }
            guard let remoteURL = note.remoteURL else { continue }
            currentSyncLabel = "下载语音"
            let localId = note.id
            let remoteId = note.remoteId
            let state = note.syncState
            do {
                let fileName = try await downloadRemoteFile(remoteURL, preferredExtension: "m4a")
                try Self.completeFileDownload(fileName, in: context, store: mediaStore,
                    descriptor: FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.id == localId }),
                    localFile: \.localFileName, isCurrent: {
                        self.isCurrentRun && $0.remoteId == remoteId && $0.remoteURL == remoteURL && $0.syncState == state
                    })
            } catch {
                noteDownloadFailure(error, remoteURL: remoteURL)
            }
            saveAndRefresh(context)
        }

        let comments = (try? context.fetch(FetchDescriptor<Comment>(
            predicate: #Predicate { $0.voiceFileName == nil && $0.remoteURL != nil }))) ?? []
        for comment in comments.filter({ !missingRemoteFiles.contains($0.remoteURL ?? "") }).prefix(10) {
            guard isCurrentRun, Date() < deadline else { return }
            guard let remoteURL = comment.remoteURL else { continue }
            currentSyncLabel = "下载家人语音"
            let localId = comment.id
            let remoteId = comment.remoteId
            let state = comment.syncState
            do {
                let fileName = try await downloadRemoteFile(remoteURL, preferredExtension: "m4a")
                try Self.completeFileDownload(fileName, in: context, store: mediaStore,
                    descriptor: FetchDescriptor<Comment>(predicate: #Predicate { $0.id == localId }),
                    localFile: \.voiceFileName, isCurrent: {
                        self.isCurrentRun && $0.remoteId == remoteId && $0.remoteURL == remoteURL && $0.syncState == state
                    })
            } catch {
                noteDownloadFailure(error, remoteURL: remoteURL)
            }
            saveAndRefresh(context)
        }

        let memos = (try? context.fetch(FetchDescriptor<VoiceMemo>(
            predicate: #Predicate { $0.localFileName == nil && $0.remoteURL != nil }))) ?? []
        for memo in memos.filter({ !missingRemoteFiles.contains($0.remoteURL ?? "") }).prefix(10) {
            guard isCurrentRun, Date() < deadline else { return }
            guard let remoteURL = memo.remoteURL else { continue }
            currentSyncLabel = "下载成长之声"
            let localId = memo.id
            let remoteId = memo.remoteId
            let state = memo.syncState
            do {
                let fileName = try await downloadRemoteFile(remoteURL, preferredExtension: "m4a")
                try Self.completeFileDownload(fileName, in: context, store: mediaStore,
                    descriptor: FetchDescriptor<VoiceMemo>(predicate: #Predicate { $0.id == localId }),
                    localFile: \.localFileName, isCurrent: {
                        self.isCurrentRun && $0.remoteId == remoteId && $0.remoteURL == remoteURL && $0.syncState == state
                    })
            } catch {
                noteDownloadFailure(error, remoteURL: remoteURL)
            }
            saveAndRefresh(context)
        }

        let profiles = (try? context.fetch(FetchDescriptor<ChildProfile>(
            predicate: #Predicate { $0.avatarMediaFileName == nil && $0.avatarRemoteURL != nil }))) ?? []
        for profile in profiles.filter({ !missingRemoteFiles.contains($0.avatarRemoteURL ?? "") }).prefix(2) {
            guard isCurrentRun else { return }
            guard let remoteURL = profile.avatarRemoteURL else { continue }
            currentSyncLabel = "下载布布头像"
            let localId = profile.id
            let remoteId = profile.remoteId
            let state = profile.syncState
            do {
                let fileName = try await downloadRemoteFile(remoteURL, preferredExtension: "jpg", sniffImage: true)
                try Self.completeFileDownload(fileName, in: context, store: mediaStore,
                    descriptor: FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.id == localId }),
                    localFile: \.avatarMediaFileName, isCurrent: {
                        self.isCurrentRun && $0.remoteId == remoteId && $0.avatarRemoteURL == remoteURL && $0.syncState == state
                    })
            } catch {
                noteDownloadFailure(error, remoteURL: remoteURL)
            }
            saveAndRefresh(context)
        }
    }

    /// 语音 / 头像 / 胶囊同样可能在下载期间被删除或替换；调用方只捕获值，不保留可写旧模型。
    @discardableResult
    static func completeFileDownload<Model: PersistentModel>(_ fileName: String, in context: ModelContext,
        store: MediaStore, descriptor: FetchDescriptor<Model>,
        localFile: ReferenceWritableKeyPath<Model, String?>, expectedFileName: String? = nil,
        isCurrent: (Model) -> Bool) throws -> Bool {
        var accepted = false
        defer { if !accepted { store.deleteLocalFiles(media: fileName) } }
        guard !Task.isCancelled, let current = try context.fetch(descriptor).first,
              current[keyPath: localFile] == expectedFileName, isCurrent(current) else { return false }
        current[keyPath: localFile] = fileName
        accepted = true
        return true
    }

    private func downloadRemoteFile(_ remoteURL: String,
                                    preferredExtension: String,
                                    sniffImage: Bool = false) async throws -> String {
        let tempURL = try await apiClient.downloadFileToTemporaryURL(from: remoteURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try checkRunValidity()
        let ext = Self.pathExtension(from: remoteURL, fallback: preferredExtension)
        return try mediaStore.importFile(from: tempURL, preferredExtension: ext, sniffImage: sniffImage)
    }

    private static func pathExtension(from remoteURL: String, fallback: String) -> String {
        guard let url = URL(string: remoteURL) else { return fallback }
        let ext = url.pathExtension
        return ext.isEmpty ? fallback : ext
    }

    /// 把远端 Entry 合并进本地（按 localId 去重；远端较新则更新）。
    private func mergeRemoteEntry(_ dto: EntryDTO) async throws -> Bool {
        guard let context = modelContext,
              let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        if try isPendingDeletion(collection: "entries", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == localId })
        let existing = try context.fetch(descriptor).first

        if let entry = existing {
            // 已有：仅当本地已同步（无本地未推改动）时用远端覆盖，避免踩掉本地草稿
            guard Self.mergeEntryPayload(dto, into: entry) else { return false }
        } else {
            let entry = Entry(happenedAt: dto.happenedAt, authorRole: dto.authorRole, note: dto.note)
            entry.id = localId
            Self.apply(dto, to: entry)
            entry.remoteId = dto.id
            entry.syncState = .synced
            context.insert(entry)
        }
        return true
    }

    private func mergeRemoteMedia(_ dto: MediaDTO) async throws -> Bool {
        guard let context = modelContext,
              let mediaId = UUID(uuidString: dto.localId),
              let entryId = UUID(uuidString: dto.entryLocalId) else { return modelContext != nil }
        if try isPendingDeletion(collection: "media", remoteId: dto.id, context: context) { return true }
        let mediaDescriptor = FetchDescriptor<Media>(predicate: #Predicate { $0.id == mediaId })
        if let existing = try context.fetch(mediaDescriptor).first {
            if existing.syncState == .synced {
                if existing.remoteURL != dto.remoteURL { downloadScanNeeded = true }
                Self.apply(dto, to: existing)
            } else {
                return false
            }
            return true
        }
        let entryDescriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryId })
        var parent = try context.fetch(entryDescriptor).first
        if parent == nil {
            // 孤儿媒体闭环（存储 P0-1）：本轮 entries 拉取抖动失败而 media 成功时，
            // 父记录还没落地。原实现直接丢弃这条媒体、游标照推——照片在这台设备永久消失。
            // 现在当场单条补拉父 Entry：拉到→先合并父记录再挂媒体；
            // 服务器上父记录已删/不存在→孤儿属被删记录，跳过（游标正常推进）；
            // 补拉网络失败→挂起本轮游标，下轮从同一窗口幂等重拉。
            do {
                if let entryDTO = try await apiClient.fetchEntry(localId: dto.entryLocalId) {
                    try checkRunValidity()
                    _ = try await mergeRemoteEntry(entryDTO)
                    parent = try context.fetch(entryDescriptor).first
                } else {
                    return true
                }
            } catch {
                holdCursorForCurrentPull = true
                return false
            }
        }
        guard let entry = parent else {
            holdCursorForCurrentPull = true
            return false
        }
        let media = Media(type: MediaType(rawValue: dto.mediaType) ?? .photo, localFileName: nil)
        media.id = mediaId
        Self.apply(dto, to: media)
        media.entry = entry
        media.syncState = .synced
        context.insert(media)
        downloadScanNeeded = true
        return true
    }

    private func mergeRemoteMilestone(_ dto: MilestoneDTO) async throws -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        guard !Self.isRemotePresetPlaceholder(dto) else { return true }
        if try isPendingDeletion(collection: "milestones", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<Milestone>(predicate: #Predicate { $0.id == localId })
        if let existing = try context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else if let existingByTitle = try findMilestone(title: dto.title, context: context),
                  !dto.isCustom, Self.isLocalPresetPlaceholder(existingByTitle) {
            if existingByTitle.syncState == .synced {
                Self.apply(dto, to: existingByTitle)
                existingByTitle.remoteId = dto.id
            } else { return false }
        } else {
            let item = Milestone(title: dto.title, category: dto.category, emoji: dto.emoji, happenedAt: dto.happenedAt, isCustom: dto.isCustom)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        return true
    }

    private func findMilestone(title: String, context: ModelContext) throws -> Milestone? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        let descriptor = FetchDescriptor<Milestone>(predicate: #Predicate { $0.title == cleanTitle })
        return try context.fetch(descriptor).first
    }

    private func normalizeMilestonesByTitle(_ context: ModelContext) throws {
        let milestones = try context.fetch(FetchDescriptor<Milestone>())
        guard milestones.count > 1 else { return }
        var bestByTitle: [String: Milestone] = [:]
        var duplicates: [Milestone] = []
        for milestone in milestones {
            let title = milestone.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                duplicates.append(milestone)
                continue
            }
            // 只在真的不同才赋值：同值赋值也会把对象标脏，让每轮空同步都「有改动」。
            if milestone.title != title { milestone.title = title }
            if let current = bestByTitle[title] {
                if Milestone.prefersKeeping(milestone, over: current) {
                    duplicates.append(current)
                    bestByTitle[title] = milestone
                } else {
                    duplicates.append(milestone)
                }
            } else {
                bestByTitle[title] = milestone
            }
        }
        for milestone in bestByTitle.values {
            if Self.isLocalPresetPlaceholder(milestone), milestone.syncState != .synced {
                milestone.syncState = .synced
            }
        }
        // 同名不代表同一段经历。只清理没有用户事实的出厂占位，保留已达成/自定义记录。
        for duplicate in duplicates where Self.isLocalPresetPlaceholder(duplicate) {
            context.delete(duplicate)
        }
        saveAndRefresh(context)
    }


    private func mergeRemoteFirstTime(_ dto: FirstTimeDTO) async throws -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        if try isPendingDeletion(collection: "firsttimes", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<FirstTime>(predicate: #Predicate { $0.id == localId })
        if let existing = try context.fetch(descriptor).first {
            if existing.syncState == .synced {
                Self.apply(dto, to: existing); existing.remoteId = dto.id
                // 上一轮父 Entry 还没到时先落了这条"第一次"；现在父记录到了要把关联补上，
                // 否则它永远是孤儿（apply 不负责 entry 关系）。
                if existing.entry == nil, let entryLocalId = dto.entryLocalId,
                   let entryId = UUID(uuidString: entryLocalId) {
                    let entryDescriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryId })
                    existing.entry = try context.fetch(entryDescriptor).first
                    if existing.entry == nil {
                        await holdIfParentEntryStillExists(localId: entryLocalId)
                    }
                }
            }
            else { return false }
        } else {
            let item = FirstTime(what: dto.what, happenedAt: dto.happenedAt)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            if let entryLocalId = dto.entryLocalId, let entryId = UUID(uuidString: entryLocalId) {
                let entryDescriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryId })
                item.entry = try context.fetch(entryDescriptor).first
                // 父 Entry 还没到：先落库保住「第一次」这条事实本身，但扣住游标，
                // 下一轮父记录到了会重新走 merge 把关联补上。不扣游标就永远补不上了。
                if item.entry == nil { await holdIfParentEntryStillExists(localId: entryLocalId) }
            }
            try checkRunValidity()
            context.insert(item)
        }
        try checkRunValidity()
        return true
    }

    /// 父 Entry 本地缺失时决定要不要扣游标：服务器上父记录仍在（只是本轮没到）→ 扣住等下一轮；
    /// 服务器上已删/不存在（Entry→FirstTime 是 nullify，删记录后「第一次」合法地成为孤儿）→ 不扣，
    /// 否则同一窗口会每 30 秒永久重拉；网络失败 → 扣住，下一轮再判。
    private func holdIfParentEntryStillExists(localId: String) async {
        do {
            let exists = try await apiClient.fetchEntry(localId: localId) != nil
            try checkRunValidity()
            if exists { holdCursorForCurrentPull = true }
        } catch {
            guard isCurrentRun else { return }
            holdCursorForCurrentPull = true
        }
    }

    private func mergeRemoteMember(_ dto: FamilyMemberDTO) async throws -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        if try isPendingDeletion(collection: "members", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.id == localId })
        if let existing = try context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let item = FamilyMember(name: dto.name, relation: dto.relation, avatarEmoji: dto.avatarEmoji, themeColorHex: dto.themeColorHex)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        return true
    }

    private func mergeRemoteChildProfile(_ dto: ChildProfileDTO) async throws -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        if try isPendingDeletion(collection: "childprofile", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.id == localId })
        if let existing = try context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let item = ChildProfile(name: dto.name, birthday: dto.birthday)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
            if (try? context.fetchCount(FetchDescriptor<ChildProfile>())) ?? 0 > 1 {
                Self.log.notice("本机现在有多份布布档案；页面统一按 ChildProfile.canonical 选用一份")
            }
        }
        return true
    }

    private func mergeRemoteHealth(_ dto: HealthRecordDTO) async throws -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        if try isPendingDeletion(collection: "healthrecords", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<HealthRecord>(predicate: #Predicate { $0.id == localId })
        if let existing = try context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let item = HealthRecord(kind: HealthRecordKind(rawValue: dto.kind) ?? .meal, title: dto.title, recordedAt: dto.recordedAt)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try backfillVaccineIfNeeded(from: dto, context: context)
        GrowthMeasurementBackfill.run(context: context, insertedSyncState: .synced, source: "health-fallback")
        return true
    }

    private func mergeRemoteVaccine(_ dto: VaccineRecordDTO) async throws -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        // 防复活：该远端记录已在本地删除队列中（删除尚未推到服务器）时，不重新合并
        if try isPendingDeletion(collection: "vaccinerecords", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<VaccineRecord>(predicate: #Predicate { $0.id == localId })
        if let existing = try context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let item = VaccineRecord(vaccineName: dto.vaccineName, injectedAt: dto.injectedAt, source: dto.source)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        return true
    }

    private func mergeRemoteGrowth(_ dto: GrowthMeasurementDTO) async throws -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        if try isPendingDeletion(collection: "growthmeasurements", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<GrowthMeasurement>(predicate: #Predicate { $0.id == localId })
        if let existing = try context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let item = GrowthMeasurement(measuredAt: dto.measuredAt, source: dto.source)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        return true
    }

    private func mergeRemoteComment(_ dto: CommentDTO) async throws -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId), let entryId = UUID(uuidString: dto.entryLocalId) else { return modelContext != nil }
        if try isPendingDeletion(collection: "comments", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<Comment>(predicate: #Predicate { $0.id == localId })
        if let existing = try context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let entryDescriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryId })
            guard let entry = try context.fetch(entryDescriptor).first else {
                // 父 Entry 这轮还没落库（entries 批次失败或排在后面）。必须扣住游标：
                // 否则 comments 游标照样推到本轮最大 updated，下轮父记录到了，
                // 这条家人补充却已落在游标之后——这台设备永远拉不回来。
                // 与 mergeRemoteMedia 的处理保持一致。
                holdCursorForCurrentPull = true
                return false
            }
            let item = Comment(authorRole: dto.authorRole, text: dto.text)
            item.id = localId; Self.apply(dto, to: item); item.entry = entry; item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        return true
    }

    private func mergeRemoteVoiceNote(_ dto: VoiceNoteDTO) async throws -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId), let entryId = UUID(uuidString: dto.entryLocalId) else { return modelContext != nil }
        if try isPendingDeletion(collection: "voicenotes", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.id == localId })
        if let existing = try context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let entryDescriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryId })
            guard let entry = try context.fetch(entryDescriptor).first else {
                // 同 mergeRemoteComment：父 Entry 未落库时扣住游标，否则这条语音留言永久丢失。
                holdCursorForCurrentPull = true
                return false
            }
            let item = VoiceNote(localFileName: nil, durationSeconds: dto.durationSeconds, authorRole: dto.authorRole, waveformSamples: dto.waveform)
            item.id = localId; Self.apply(dto, to: item); item.entry = entry; item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        return true
    }

    private func mergeRemoteVoiceMemo(_ dto: VoiceMemoDTO) async throws -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        if try isPendingDeletion(collection: "voicememos", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<VoiceMemo>(predicate: #Predicate { $0.id == localId })
        if let existing = try context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let item = VoiceMemo(kind: VoiceMemo.Kind(rawValue: dto.kind) ?? .childVoice, recordedAt: dto.recordedAt)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        return true
    }

    private func mergeRemoteTimeCapsule(_ dto: TimeCapsuleDTO) async throws -> Bool {
        guard let context = modelContext else { return false }
        if try isPendingDeletion(collection: "timecapsules", remoteId: dto.id, context: context) { return true }
        return try await CapsuleRemoteMerge.merge(dto, in: context, directory: BubuStorage.mediaDirectory,
            resolveFile: { self.mediaStore.mediaURL(for: $0) }, isCurrent: { self.isCurrentRun }) { remote in
            try await self.apiClient.downloadFileToTemporaryURL(from: remote)
        }
    }

    // MARK: - DTO 映射

    private static func makeDTO(_ entry: Entry) -> EntryDTO {
        EntryDTO(
            id: entry.remoteId, localId: entry.id.uuidString,
            familyId: nil, authorUserId: nil,
            title: entry.title, note: entry.note, firstPersonNote: entry.firstPersonNote,
            happenedAt: entry.happenedAt, locationName: entry.locationName,
            latitude: entry.latitude, longitude: entry.longitude,
            authorRole: entry.authorRole, mood: entry.moodRaw,
            isArchived: entry.isArchived, inStorybook: entry.inStorybook,
            editedAt: entry.editedAt, createdAt: entry.createdAt)
    }

    /// 与上传回执使用相同的 LWW 契约；输入绑定即时标脏后，旧 pull 不得覆盖正在编辑的内容。
    static func mergeEntryPayload(_ dto: EntryDTO, into entry: Entry) -> Bool {
        guard entry.syncState == .synced || remoteEntryWins(dto, over: entry) else { return false }
        apply(dto, to: entry)
        entry.remoteId = dto.id
        entry.syncState = .synced
        return true
    }

    private static func remoteEntryWins(_ dto: EntryDTO, over entry: Entry) -> Bool {
        guard let remoteEditedAt = dto.editedAt else { return false }
        return remoteEditedAt > (entry.editedAt ?? entry.createdAt)
    }

    private static func apply(_ dto: MediaDTO, to media: Media) {
        media.remoteId = dto.id
        media.typeRaw = dto.mediaType
        media.remoteURL = dto.remoteURL
        // 只增不清：老服务端记录没有 thumbnail 时保留本地已知值。
        if let thumb = dto.remoteThumbURL { media.remoteThumbURL = thumb }
        if let hash = dto.contentHash { media.contentHash = hash }
        if let role = dto.resourceRole { media.resourceRoleRaw = role }
        if let group = dto.assetGroupId { media.assetGroupID = group }
        // 只增不清：老客户端/老记录没有这些字段时，不能把本机已知的时长、尺寸和端侧标签抹掉。
        if let duration = dto.durationSeconds { media.durationSeconds = duration }
        if let width = dto.width { media.width = width }
        if let height = dto.height { media.height = height }
        if !dto.aiTags.isEmpty { media.aiTags = dto.aiTags }
    }

    private static func makeDTO(_ item: Milestone) -> MilestoneDTO {
        MilestoneDTO(id: item.remoteId, localId: item.id.uuidString, title: item.title, category: item.category,
                     emoji: item.emoji, detail: item.detail, happenedAt: item.happenedAt,
                     ageDescription: item.ageDescription, isCustom: item.isCustom, createdAt: item.createdAt)
    }

    private static func isPresetTitle(_ title: String) -> Bool {
        MilestoneTemplate.presets.contains { $0.title == title }
    }

    private static func isLocalPresetPlaceholder(_ item: Milestone) -> Bool {
        isPresetTitle(item.title)
        && !item.isCustom
        && item.happenedAt == nil
        && (item.detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private static func isRemotePresetPlaceholder(_ dto: MilestoneDTO) -> Bool {
        isPresetTitle(dto.title)
        && !dto.isCustom
        && dto.happenedAt == nil
        && (dto.detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private static func apply(_ dto: MilestoneDTO, to item: Milestone) {
        item.title = dto.title; item.category = dto.category; item.emoji = dto.emoji; item.detail = dto.detail
        item.happenedAt = dto.happenedAt; item.ageDescription = dto.ageDescription; item.isCustom = dto.isCustom
    }

    private static func makeDTO(_ item: FirstTime) -> FirstTimeDTO {
        FirstTimeDTO(id: item.remoteId, localId: item.id.uuidString, what: item.what, happenedAt: item.happenedAt,
                     detectedByAI: item.detectedByAI, confirmedByParent: item.confirmedByParent,
                     entryLocalId: item.entry?.id.uuidString, createdAt: item.createdAt)
    }

    private static func apply(_ dto: FirstTimeDTO, to item: FirstTime) {
        item.what = dto.what; item.happenedAt = dto.happenedAt; item.detectedByAI = dto.detectedByAI
        item.confirmedByParent = dto.confirmedByParent
    }

    private static func makeDTO(_ item: FamilyMember) -> FamilyMemberDTO {
        FamilyMemberDTO(id: item.remoteId, localId: item.id.uuidString, name: item.name, relation: item.relation,
                        avatarEmoji: item.avatarEmoji, themeColorHex: item.themeColorHex,
                        isPrimary: item.isPrimary, createdAt: item.createdAt)
    }

    private static func apply(_ dto: FamilyMemberDTO, to item: FamilyMember) {
        item.name = dto.name; item.relation = dto.relation; item.avatarEmoji = dto.avatarEmoji
        item.themeColorHex = dto.themeColorHex; item.isPrimary = dto.isPrimary
    }

    private static func makeDTO(_ item: ChildProfile) -> ChildProfileDTO {
        ChildProfileDTO(id: item.remoteId, localId: item.id.uuidString, name: item.name, birthday: item.birthday,
                        gender: item.gender, bloodType: item.bloodType, birthPlace: item.birthPlace,
                        avatarRemoteURL: item.avatarRemoteURL, schoolStartDate: item.schoolStartDate,
                        allergies: item.allergies, medicalNotes: item.medicalNotes,
                        createdAt: item.createdAt)
    }

    private static func apply(_ dto: ChildProfileDTO, to item: ChildProfile) {
        // createdAt 用服务器 created：它决定多份档案时哪份是「最早的那份」，全家设备必须一致（D9-01）。
        if let serverCreated = dto.serverUpdatedAt.flatMap({ _ in dto.createdAt }), serverCreated < item.createdAt {
            item.createdAt = serverCreated
        }
        item.name = dto.name; item.birthday = dto.birthday; item.gender = dto.gender
        item.bloodType = dto.bloodType; item.birthPlace = dto.birthPlace
        // 只在远端确实给了值时才覆盖：老客户端推上来的 DTO 没有这个键，
        // 不能让它把另一台设备刚填的入园日期清空。
        if let schoolStart = dto.schoolStartDate { item.schoolStartDate = schoolStart }
        if let allergies = dto.allergies { item.allergies = allergies }
        if let notes = dto.medicalNotes { item.medicalNotes = notes }
        // 远端头像变更：更新 URL 并清掉本地文件名，下一轮 downloadMissingFiles 重新落地
        if let remote = dto.avatarRemoteURL, remote != item.avatarRemoteURL {
            item.avatarRemoteURL = remote
            item.avatarMediaFileName = nil
        }
    }

    private static func makeDTO(_ item: HealthRecord) -> HealthRecordDTO {
        HealthRecordDTO(id: item.remoteId, localId: item.id.uuidString, kind: item.kindRaw, title: item.title,
                        detail: item.detail, recordedAt: item.recordedAt, amountText: item.amountText,
                        reaction: item.reaction, amountValue: item.amountValue, amountUnit: item.amountUnit,
                        startAt: item.startAt, endAt: item.endAt, severity: item.severityRaw,
                        temperatureCelsius: item.temperatureCelsius, tags: item.tags, createdAt: item.createdAt)
    }

    private static func apply(_ dto: HealthRecordDTO, to item: HealthRecord) {
        item.kindRaw = dto.kind; item.title = dto.title; item.detail = dto.detail; item.recordedAt = dto.recordedAt
        item.amountText = dto.amountText; item.reaction = dto.reaction; item.amountValue = dto.amountValue
        item.amountUnit = dto.amountUnit; item.startAt = dto.startAt; item.endAt = dto.endAt
        item.severityRaw = dto.severity; item.temperatureCelsius = dto.temperatureCelsius; item.tags = dto.tags
    }

    private static func makeDTO(_ item: VaccineRecord) -> VaccineRecordDTO {
        VaccineRecordDTO(id: item.remoteId, localId: item.id.uuidString, doseId: item.doseId,
                         vaccineName: item.vaccineName, doseLabel: item.doseLabel, injectedAt: item.injectedAt,
                         hospital: item.hospital, injectionSite: item.injectionSite, reaction: item.reaction,
                         note: item.note, source: item.sourceRaw, createdAt: item.createdAt,
                         editedAt: item.updatedAt)
    }

    private static func apply(_ dto: VaccineRecordDTO, to item: VaccineRecord) {
        item.doseId = dto.doseId; item.vaccineName = dto.vaccineName; item.doseLabel = dto.doseLabel
        item.injectedAt = dto.injectedAt; item.hospital = dto.hospital; item.injectionSite = dto.injectionSite
        item.reaction = dto.reaction; item.note = dto.note; item.sourceRaw = dto.source
        item.updatedAt = .now
    }

    private static func makeDTO(_ item: GrowthMeasurement) -> GrowthMeasurementDTO {
        GrowthMeasurementDTO(id: item.remoteId, localId: item.id.uuidString, measuredAt: item.measuredAt,
                             heightCm: item.heightCm, weightKg: item.weightKg,
                             headCircumferenceCm: item.headCircumferenceCm, note: item.note,
                             source: item.sourceRaw, createdAt: item.createdAt,
                             editedAt: item.updatedAt)
    }

    private static func makeHealthFallbackDTO(_ item: VaccineRecord) -> HealthRecordDTO {
        let details = compactJoined([
            item.doseLabel,
            item.hospital.map { "医院：\($0)" },
            item.injectionSite.map { "部位：\($0)" },
            item.reaction.map { "反应：\($0)" },
            item.note
        ])
        return HealthRecordDTO(
            id: nil,
            localId: item.id.uuidString,
            kind: HealthRecordKind.checkup.rawValue,
            title: "疫苗：\(item.vaccineName)",
            detail: details,
            recordedAt: item.injectedAt,
            amountText: item.doseLabel,
            reaction: item.reaction,
            amountValue: nil,
            amountUnit: nil,
            startAt: nil,
            endAt: nil,
            severity: nil,
            temperatureCelsius: nil,
            tags: ["疫苗", item.vaccineName],
            createdAt: item.createdAt
        )
    }

    private static func makeHealthFallbackDTO(_ item: GrowthMeasurement) -> HealthRecordDTO {
        let amountText = compactJoined([
            item.heightCm.map { "身高 \(formatMetric($0))cm" },
            item.weightKg.map { "体重 \(formatMetric($0))kg" },
            item.headCircumferenceCm.map { "头围 \(formatMetric($0))cm" }
        ]) ?? "身高体重"
        return HealthRecordDTO(
            id: nil,
            localId: item.id.uuidString,
            kind: HealthRecordKind.checkup.rawValue,
            title: "身高体重",
            detail: item.note,
            recordedAt: item.measuredAt,
            amountText: amountText,
            reaction: nil,
            amountValue: nil,
            amountUnit: nil,
            startAt: nil,
            endAt: nil,
            severity: nil,
            temperatureCelsius: nil,
            tags: ["身高体重", "成长数据"],
            createdAt: item.createdAt
        )
    }

    private static func compactJoined(_ parts: [String?]) -> String? {
        let values = parts.compactMap { part -> String? in
            let trimmed = part?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private static func formatMetric(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    private func backfillVaccineIfNeeded(from dto: HealthRecordDTO, context: ModelContext) throws {
        guard let localId = UUID(uuidString: dto.localId) else { return }
        let isVaccine = dto.tags.contains("疫苗") || dto.title.contains("疫苗")
        guard isVaccine else { return }
        let descriptor = FetchDescriptor<VaccineRecord>(predicate: #Predicate { $0.id == localId })
        guard (try context.fetch(descriptor).first) == nil else { return }

        let name = Self.vaccineName(from: dto)
        let item = VaccineRecord(vaccineName: name, injectedAt: dto.recordedAt, source: "health-fallback")
        item.id = localId
        item.doseLabel = dto.amountText
        item.reaction = dto.reaction
        item.note = dto.detail
        item.syncState = .synced
        context.insert(item)
        saveAndRefresh(context)
    }

    private static func vaccineName(from dto: HealthRecordDTO) -> String {
        let cleanedTitle = dto.title
            .replacingOccurrences(of: "疫苗：", with: "")
            .replacingOccurrences(of: "疫苗:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedTitle.isEmpty, cleanedTitle != "疫苗" {
            return cleanedTitle
        }
        return dto.tags.first { $0 != "疫苗" } ?? "疫苗记录"
    }

    private static func apply(_ dto: GrowthMeasurementDTO, to item: GrowthMeasurement) {
        item.measuredAt = dto.measuredAt; item.heightCm = dto.heightCm; item.weightKg = dto.weightKg
        item.headCircumferenceCm = dto.headCircumferenceCm; item.note = dto.note; item.sourceRaw = dto.source
        item.updatedAt = .now
    }

    private static func makeDTO(_ item: Comment) -> CommentDTO {
        CommentDTO(id: item.remoteId, localId: item.id.uuidString, entryLocalId: item.entry?.id.uuidString ?? "",
                   authorRole: item.authorRole, text: item.text, remoteURL: item.remoteURL,
                   voiceDuration: item.voiceDuration, voiceWaveform: item.voiceWaveform, createdAt: item.createdAt)
    }

    private static func apply(_ dto: CommentDTO, to item: Comment) {
        item.authorRole = dto.authorRole; item.text = dto.text; item.remoteURL = dto.remoteURL
        item.voiceDuration = dto.voiceDuration; item.voiceWaveform = dto.voiceWaveform
    }

    private static func makeDTO(_ item: VoiceNote) -> VoiceNoteDTO {
        VoiceNoteDTO(id: item.remoteId, localId: item.id.uuidString, entryLocalId: item.entry?.id.uuidString ?? "",
                     authorRole: item.authorRole, remoteURL: item.remoteURL, durationSeconds: item.durationSeconds,
                     transcript: item.transcript, waveform: item.waveformSamples, createdAt: item.createdAt)
    }

    private static func apply(_ dto: VoiceNoteDTO, to item: VoiceNote) {
        item.authorRole = dto.authorRole; item.remoteURL = dto.remoteURL; item.durationSeconds = dto.durationSeconds
        item.transcript = dto.transcript; item.waveformSamples = dto.waveform
    }

    private static func makeDTO(_ item: VoiceMemo) -> VoiceMemoDTO {
        VoiceMemoDTO(id: item.remoteId, localId: item.id.uuidString, kind: item.kindRaw, remoteURL: item.remoteURL,
                     transcript: item.transcript, ageYears: item.ageYears, recordedAt: item.recordedAt,
                     durationSeconds: item.durationSeconds, createdAt: item.createdAt)
    }

    private static func apply(_ dto: VoiceMemoDTO, to item: VoiceMemo) {
        item.kindRaw = dto.kind; item.remoteURL = dto.remoteURL; item.transcript = dto.transcript
        item.ageYears = dto.ageYears; item.recordedAt = dto.recordedAt; item.durationSeconds = dto.durationSeconds
    }

    private static func makeDTO(_ item: TimeCapsule) -> TimeCapsuleDTO {
        TimeCapsuleDTO(id: item.remoteId, localId: item.id.uuidString, title: item.title,
                       fromRole: item.fromRole, unlockAt: item.unlockAt, isLocked: item.isLocked,
                       encryptedBlobRemoteURL: nil, coverEmoji: item.coverEmoji,
                       cryptoVersion: item.cryptoVersion, createdAt: item.createdAt)
    }

    private static func apply(_ dto: EntryDTO, to entry: Entry) {
        entry.title = dto.title
        entry.note = dto.note
        entry.firstPersonNote = dto.firstPersonNote
        entry.happenedAt = dto.happenedAt
        entry.locationName = dto.locationName
        entry.latitude = dto.latitude
        entry.longitude = dto.longitude
        entry.authorRole = dto.authorRole
        entry.moodRaw = dto.mood
        entry.isArchived = dto.isArchived
        // 仅当远端明确带了 inStorybook 才覆盖，服务端无此字段时保留本地勾选（不被同步抹掉）。
        if let inStorybook = dto.inStorybook { entry.inStorybook = inStorybook }
        entry.editedAt = dto.editedAt
    }
}

// 同一个 MainActor 可在 await 重入；前台任务句柄本身不能保护 BGTask / 强制补传入口。
// 许可覆盖整轮（强制补传还包括标脏阶段），排队者取消时移除等待，不影响正在运行的轮次。
@MainActor
final class SyncRunGate {
    private var held = false
    private var generation = UUID()
    private var cancelActive: (() -> Void)?
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    @discardableResult
    func withPermit<Result: Sendable>(_ operation: @escaping @MainActor () async -> Result) async -> Result? {
        let requestedGeneration = generation
        guard await acquire() else { return nil }
        defer { cancelActive = nil; release() }
        guard !Task.isCancelled, requestedGeneration == generation else { return nil }
        let task = Task { @MainActor in await operation() }
        cancelActive = { task.cancel() }
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard !task.isCancelled, requestedGeneration == generation else { return nil }
        return result
    }

    func invalidate() {
        generation = UUID()
        cancelActive?()
        let cancelled = waiters
        waiters.removeAll()
        for waiter in cancelled { waiter.continuation.resume(returning: false) }
    }

    private func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        if !held { held = true; return true }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(returning: false) }
                else { waiters.append((id, continuation)) }
            }
        } onCancel: {
            Task { @MainActor in
                guard let index = self.waiters.firstIndex(where: { $0.id == id }) else { return }
                self.waiters.remove(at: index).continuation.resume(returning: false)
            }
        }
    }

    private func release() {
        if waiters.isEmpty { held = false }
        else { waiters.removeFirst().continuation.resume(returning: true) }
    }
}
