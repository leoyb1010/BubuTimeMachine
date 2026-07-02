import Foundation
import SwiftData
import Observation
import UIKit

// MARK: - 同步引擎
/// 双向收敛：本地未同步的 Entry/Media 推送到 PocketBase；远端变更拉回本地。
/// 离线优先：未配置或断网时静默保持离线，本地全功能可用；联网后自动补传。
@Observable
@MainActor
final class SyncEngine {
    enum ConnectionState: Sendable {
        case offline, connecting, online
    }

    private(set) var connectionState: ConnectionState = .offline
    private(set) var lastSyncedAt: Date?
    private(set) var pendingCount: Int = 0
    private(set) var totalPendingAtStart: Int = 0
    private(set) var processedThisRun: Int = 0
    private(set) var currentSyncLabel: String?
    private(set) var currentUploadProgress: Double?
    private(set) var lastFailureReason: String?
    private(set) var lastLargeFileNotice: String?
    /// 可自愈的瞬时波动提示（平和措辞、非报红）。仅当连续多轮仍失败才显示。
    private(set) var softNotice: String?

    // 瞬时失败的轮内标记与跨轮连发计数（避免偶发抖动立刻报红）。
    private var softFailureThisRun = false
    private var softFailureStreak = 0

    var syncProgress: Double? {
        guard totalPendingAtStart > 0 else { return nil }
        let uploadFraction = currentUploadProgress ?? 0
        return min(1, (Double(processedThisRun) + uploadFraction) / Double(totalPendingAtStart))
    }

    private var apiClient: APIClient
    private let config: ServerConfig
    private let mediaStore: MediaStore
    private var modelContext: ModelContext?
    private var syncTask: Task<Void, Never>?
    private var activeSyncID: UUID?
    private var needsAnotherSync = false
    private var pollTimer: Timer?

    // MARK: - 增量游标（按集合持久化）
    /// 任一集合拉取失败则该集合游标不推进，下次补拉；游标回退 60 秒容忍时钟偏差（合并幂等）。
    private static let cursorOverlap: TimeInterval = 60

    private func cursor(for collection: String) -> Date? {
        UserDefaults.standard.object(forKey: "bubu.sync.cursor.\(collection)") as? Date
    }

    private func setCursor(_ date: Date, for collection: String) {
        UserDefaults.standard.set(date.addingTimeInterval(-Self.cursorOverlap),
                                  forKey: "bubu.sync.cursor.\(collection)")
    }

    init(apiClient: APIClient, config: ServerConfig, mediaStore: MediaStore) {
        self.apiClient = apiClient
        self.config = config
        self.mediaStore = mediaStore
    }

    /// 设置变更后替换底层客户端并重连。
    func setClient(_ client: APIClient) {
        activeSyncID = nil
        syncTask?.cancel()
        syncTask = nil
        pollTimer?.invalidate()
        pollTimer = nil
        self.apiClient = client
    }

    /// 进后台时调用：停掉轮询，省电；回前台 start() 会重启。
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    /// 由 App 注入主上下文（同步需要读写 SwiftData）。
    func attach(context: ModelContext) {
        self.modelContext = context
        refreshPendingCount()
    }

    /// 启动同步层：已配置则连接 + 首次全量推拉 + 起轮询；否则保持离线。
    func start() {
        guard config.isConfigured else {
            connectionState = .offline
            pollTimer?.invalidate()
            pollTimer = nil
            refreshPendingCount()
            return
        }
        startPolling()
        scheduleSync()
    }

    /// 手动触发一次同步（设置页/下拉刷新可调）。
    func syncNow() {
        guard config.isConfigured else {
            connectionState = .offline
            refreshPendingCount()
            return
        }
        scheduleSync()
    }

    #if DEBUG
    /// 一次性修复用：本机 iPhone 作为真相源，把除里程碑外的业务数据全部重新标为待上传。
    /// 里程碑已用标题唯一策略单独修复，避免再次按 localId POST 造成重复。
    func debugForceUploadAllLocalDataToCloud() async -> String {
        guard let context = modelContext else { return "BUBU_FORCE_UPLOAD_FAILED no_context at=\(Date())" }
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        let media = (try? context.fetch(FetchDescriptor<Media>())) ?? []
        let firstTimes = (try? context.fetch(FetchDescriptor<FirstTime>())) ?? []
        let members = (try? context.fetch(FetchDescriptor<FamilyMember>())) ?? []
        let profiles = (try? context.fetch(FetchDescriptor<ChildProfile>())) ?? []
        let health = (try? context.fetch(FetchDescriptor<HealthRecord>())) ?? []
        let vaccines = (try? context.fetch(FetchDescriptor<VaccineRecord>())) ?? []
        let growth = (try? context.fetch(FetchDescriptor<GrowthMeasurement>())) ?? []
        let comments = (try? context.fetch(FetchDescriptor<Comment>())) ?? []
        let notes = (try? context.fetch(FetchDescriptor<VoiceNote>())) ?? []
        let memos = (try? context.fetch(FetchDescriptor<VoiceMemo>())) ?? []
        let capsules = (try? context.fetch(FetchDescriptor<TimeCapsule>())) ?? []

        entries.forEach { $0.syncState = .local }
        media.forEach { $0.syncState = .local; $0.uploadProgress = 0 }
        firstTimes.forEach { $0.syncState = .local }
        members.forEach { $0.syncState = .local }
        profiles.forEach { $0.syncState = .local }
        health.forEach { $0.syncState = .local }
        vaccines.forEach { $0.syncState = .local }
        growth.forEach { $0.syncState = .local }
        comments.forEach { $0.syncState = .local }
        notes.forEach { $0.syncState = .local }
        memos.forEach { $0.syncState = .local }
        capsules.forEach { $0.syncState = .local }

        saveAndRefresh(context)
        await connectAndSync()
        return "BUBU_FORCE_UPLOAD_DONE entries=\(entries.count) media=\(media.count) firstTimes=\(firstTimes.count) members=\(members.count) profiles=\(profiles.count) health=\(health.count) vaccines=\(vaccines.count) growth=\(growth.count) comments=\(comments.count) voiceNotes=\(notes.count) voiceMemos=\(memos.count) capsules=\(capsules.count) failure=\(lastFailureReason ?? "none") at=\(Date())"
    }
    #endif

    // MARK: - 连接

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.config.isConfigured else { return }
                self.scheduleSync()
            }
        }
    }

    private func scheduleSync() {
        guard syncTask == nil else {
            needsAnotherSync = true
            return
        }
        connectionState = .connecting
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
        beginSyncRun()
        let ok = (try? await apiClient.ping()) ?? false
        guard !Task.isCancelled else { finalizeRun(); return }
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
        } catch {
            connectionState = .offline
            currentSyncLabel = nil
            currentUploadProgress = nil
            recordFailure(error, item: "账号")
            refreshPendingCount()
            finalizeRun()
            return
        }
        guard !Task.isCancelled else { finalizeRun(); return }
        connectionState = .online

        await pushLocal()
        guard !Task.isCancelled else { finalizeRun(); return }
        await pullRemote()
        guard !Task.isCancelled else { finalizeRun(); return }
        if let context = modelContext {
            await downloadMissingFiles(context)
        }
        currentSyncLabel = nil
        currentUploadProgress = nil
        finalizeRun()
        // 注：不再叠加 subscribeRealtime 的 8 秒轮询——与 30 秒同步循环重复，纯耗电。
        // 后续接 SSE 长连时在这里恢复订阅。
    }

    /// 一轮结束后评估瞬时失败：单轮抖动静默自愈，连续两轮（≈60s）仍失败才平和提示。
    private func finalizeRun() {
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
        normalizeMilestonesByTitle(context)
        // 先消费删除队列：删除意图优先于数据推送，避免「先推后删」竞态
        await processPendingDeletions(context)
        // 取所有未同步（local/failed）的 Entry
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate {
                $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading"
            })
        guard let locals = try? context.fetch(descriptor) else { return }
        refreshPendingCount()

        for entry in locals {
            guard !Task.isCancelled else { return }
            beginItem("同步记录")
            entry.syncState = .uploading
            saveAndRefresh(context)
            let dto = Self.makeDTO(entry)
            do {
                let saved = try await apiClient.createEntry(dto)
                entry.remoteId = saved.id
                entry.syncState = .synced
            } catch {
                entry.syncState = .failed
                recordFailure(error, item: "记录")
            }
            finishItem()
            saveAndRefresh(context)
        }
        await pushUnsyncedMedia(context)
        await pushLocalJSONObjects(context)
        await pushTimeCapsules(context)
        saveAndRefresh(context)
    }

    private func saveAndRefresh(_ context: ModelContext) {
        try? context.save()
        refreshPendingCount()
    }

    private func refreshWidgetSnapshot(_ context: ModelContext) {
        guard let snapshot = SharedWidgetSnapshot.make(context: context) else { return }
        SharedDefaults.saveWidgetSnapshot(snapshot)
        WidgetRefresher.reload()
    }

    // MARK: - 删除队列消费

    private func processPendingDeletions(_ context: ModelContext) async {
        let deletions = (try? context.fetch(FetchDescriptor<PendingDeletion>(
            sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        for deletion in deletions {
            guard !Task.isCancelled else { return }
            beginItem("同步删除")
            do {
                try await performRemoteDeletion(deletion)
                context.delete(deletion)
            } catch {
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

    private func isPendingDeletion(collection: String, remoteId: String?, context: ModelContext) -> Bool {
        guard let remoteId, !remoteId.isEmpty else { return false }
        let pendings = (try? context.fetch(FetchDescriptor<PendingDeletion>(
            predicate: #Predicate { $0.collection == collection }))) ?? []
        return pendings.contains { $0.remoteId == remoteId }
    }

    private func beginSyncRun() {
        refreshPendingCount()
        totalPendingAtStart = pendingCount
        processedThisRun = 0
        currentUploadProgress = nil
        lastFailureReason = nil
        lastLargeFileNotice = nil
        softFailureThisRun = false
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
            let hardLocalKeywords = ["本地文件", "文件名为空", "找不到这条媒体", "文件不见了"]
            return !hardLocalKeywords.contains { message.contains($0) }
        }

        return false
    }

    private static func safeUserMessage(for error: Error) -> String {
        switch error {
        case APIError.fileTooLarge(_, let limit):
            return "文件太大，建议压缩到 \(max(1, limit / 1_048_576))MB 以内后再传。"
        case APIError.unauthorized:
            return "账号状态需要重新确认，请到设置里重新连接服务器。"
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
    }

    private func count<T: PersistentModel>(_ context: ModelContext, _ predicate: Predicate<T>) -> Int {
        (try? context.fetchCount(FetchDescriptor<T>(predicate: predicate))) ?? 0
    }

    private func pushLocalJSONObjects(_ context: ModelContext) async {
        let localMilestones = (try? context.fetch(FetchDescriptor<Milestone>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        // 预设占位符不上云：批量标记为已同步，循环外统一保存一次，避免 N 次 save + widget 刷新。
        let placeholders = localMilestones.filter { Self.isLocalPresetPlaceholder($0) }
        if !placeholders.isEmpty {
            placeholders.forEach { $0.syncState = .synced }
            saveAndRefresh(context)
        }
        for item in localMilestones where !Self.isLocalPresetPlaceholder(item) {
            guard !Task.isCancelled else { return }
            beginItem("同步里程碑")
            do { item.syncState = .uploading; saveAndRefresh(context); let saved = try await apiClient.upsertMilestone(Self.makeDTO(item)); item.remoteId = saved.id; item.syncState = .synced }
            catch { item.syncState = .failed; recordFailure(error, item: "里程碑") }
            finishItem()
            saveAndRefresh(context)
        }
        let localFirstTimes = (try? context.fetch(FetchDescriptor<FirstTime>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        for item in localFirstTimes {
            guard !Task.isCancelled else { return }
            beginItem("同步第一次")
            do { item.syncState = .uploading; saveAndRefresh(context); let saved = try await apiClient.upsertFirstTime(Self.makeDTO(item)); item.remoteId = saved.id; item.syncState = .synced }
            catch { item.syncState = .failed; recordFailure(error, item: "第一次") }
            finishItem()
            saveAndRefresh(context)
        }
        let localMembers = (try? context.fetch(FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        for item in localMembers {
            guard !Task.isCancelled else { return }
            beginItem("同步家庭成员")
            do { item.syncState = .uploading; saveAndRefresh(context); let saved = try await apiClient.upsertFamilyMember(Self.makeDTO(item)); item.remoteId = saved.id; item.syncState = .synced }
            catch { item.syncState = .failed; recordFailure(error, item: "家庭成员") }
            finishItem()
            saveAndRefresh(context)
        }
        let localProfiles = (try? context.fetch(FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        for item in localProfiles {
            guard !Task.isCancelled else { return }
            beginItem("同步布布档案")
            do {
                item.syncState = .uploading
                saveAndRefresh(context)
                let saved = try await apiClient.upsertChildProfile(Self.makeDTO(item))
                // 头像变更后 avatarRemoteURL 被置空 → 补传到 childprofile.avatar
                if let fileName = item.avatarMediaFileName, item.avatarRemoteURL == nil {
                    let url = mediaStore.mediaURL(for: fileName)
                    if FileManager.default.fileExists(atPath: url.path) {
                        for try await event in apiClient.uploadChildAvatar(profileLocalId: item.id, fileURL: url, fileName: fileName) {
                            switch event {
                            case .progress(let p): currentUploadProgress = p
                            case .completed(_, let remoteURL): item.avatarRemoteURL = remoteURL
                            }
                        }
                    }
                }
                item.remoteId = saved.id
                item.syncState = .synced
            }
            catch { item.syncState = .failed; recordFailure(error, item: "布布档案") }
            finishItem()
            saveAndRefresh(context)
            refreshWidgetSnapshot(context)
        }
        let localHealth = (try? context.fetch(FetchDescriptor<HealthRecord>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        for item in localHealth {
            guard !Task.isCancelled else { return }
            beginItem("同步健康记录")
            do { item.syncState = .uploading; saveAndRefresh(context); let saved = try await apiClient.upsertHealthRecord(Self.makeDTO(item)); item.remoteId = saved.id; item.syncState = .synced }
            catch { item.syncState = .failed; recordFailure(error, item: "健康记录") }
            finishItem()
            saveAndRefresh(context)
        }
        let localVaccines = (try? context.fetch(FetchDescriptor<VaccineRecord>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        for item in localVaccines {
            guard !Task.isCancelled else { return }
            beginItem("同步疫苗记录")
            do {
                item.syncState = .uploading
                saveAndRefresh(context)
                let saved = try await apiClient.upsertVaccineRecord(Self.makeDTO(item))
                item.remoteId = saved.id
                item.syncState = .synced
            } catch {
                if Self.isMissingOptionalServerCollection(error, item: "疫苗记录") {
                    do {
                        let saved = try await apiClient.upsertHealthRecord(Self.makeHealthFallbackDTO(item))
                        item.remoteId = saved.id
                        item.sourceRaw = "health-fallback"
                        item.syncState = .synced
                    } catch {
                        item.syncState = .failed
                        recordFailure(error, item: "疫苗记录")
                    }
                } else {
                    item.syncState = .failed
                    recordFailure(error, item: "疫苗记录")
                }
            }
            finishItem()
            saveAndRefresh(context)
        }
        let localGrowth = (try? context.fetch(FetchDescriptor<GrowthMeasurement>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        for item in localGrowth {
            guard !Task.isCancelled else { return }
            beginItem("同步成长测量")
            do {
                item.syncState = .uploading
                saveAndRefresh(context)
                let saved = try await apiClient.upsertGrowthMeasurement(Self.makeDTO(item))
                item.remoteId = saved.id
                item.syncState = .synced
            } catch {
                if Self.isMissingOptionalServerCollection(error, item: "成长测量") {
                    do {
                        let saved = try await apiClient.upsertHealthRecord(Self.makeHealthFallbackDTO(item))
                        item.remoteId = saved.id
                        item.sourceRaw = "health-fallback"
                        item.syncState = .synced
                    } catch {
                        item.syncState = .failed
                        recordFailure(error, item: "成长测量")
                    }
                } else {
                    item.syncState = .failed
                    recordFailure(error, item: "成长测量")
                }
            }
            finishItem()
            saveAndRefresh(context)
            refreshWidgetSnapshot(context)
        }
        await pushLocalFileObjects(context)
    }

    private func pushLocalFileObjects(_ context: ModelContext) async {
        let comments = (try? context.fetch(FetchDescriptor<Comment>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        for comment in comments {
            guard !Task.isCancelled else { return }
            beginItem("同步家人补充")
            do {
                comment.syncState = .uploading
                saveAndRefresh(context)
                var saved = try await apiClient.upsertComment(Self.makeDTO(comment))
                if let fileName = comment.voiceFileName, let entryId = comment.entry?.id {
                    let url = mediaStore.mediaURL(for: fileName)
                    if FileManager.default.fileExists(atPath: url.path) {
                        for try await event in apiClient.uploadCommentVoice(commentId: comment.id, entryLocalId: entryId, fileURL: url, fileName: fileName) {
                            switch event {
                            case .progress(let p): currentUploadProgress = p
                            case .completed(let remoteId, let remoteURL): saved.id = remoteId; comment.remoteURL = remoteURL
                            }
                        }
                    }
                }
                comment.remoteId = saved.id; comment.syncState = .synced
            } catch { comment.syncState = .failed; recordFailure(error, item: "家人补充") }
            finishItem()
            saveAndRefresh(context)
        }
        let notes = (try? context.fetch(FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        for note in notes {
            guard !Task.isCancelled else { return }
            beginItem("同步记录语音")
            do {
                note.syncState = .uploading
                saveAndRefresh(context)
                var saved = try await apiClient.upsertVoiceNote(Self.makeDTO(note))
                if let fileName = note.localFileName, let entryId = note.entry?.id {
                    let url = mediaStore.mediaURL(for: fileName)
                    if FileManager.default.fileExists(atPath: url.path) {
                        for try await event in apiClient.uploadVoiceNote(voiceId: note.id, entryLocalId: entryId, fileURL: url, fileName: fileName) {
                            switch event {
                            case .progress(let p): currentUploadProgress = p
                            case .completed(let remoteId, let remoteURL): saved.id = remoteId; note.remoteURL = remoteURL
                            }
                        }
                    }
                }
                note.remoteId = saved.id; note.syncState = .synced
            } catch { note.syncState = .failed; recordFailure(error, item: "记录语音") }
            finishItem()
            saveAndRefresh(context)
        }
        let memos = (try? context.fetch(FetchDescriptor<VoiceMemo>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        for memo in memos {
            guard !Task.isCancelled else { return }
            beginItem("同步成长之声")
            do {
                memo.syncState = .uploading
                saveAndRefresh(context)
                var saved = try await apiClient.upsertVoiceMemo(Self.makeDTO(memo))
                if let fileName = memo.localFileName {
                    let url = mediaStore.mediaURL(for: fileName)
                    if FileManager.default.fileExists(atPath: url.path) {
                        for try await event in apiClient.uploadVoiceMemo(memoId: memo.id, fileURL: url, fileName: fileName) {
                            switch event {
                            case .progress(let p): currentUploadProgress = p
                            case .completed(let remoteId, let remoteURL): saved.id = remoteId; memo.remoteURL = remoteURL
                            }
                        }
                    }
                }
                memo.remoteId = saved.id; memo.syncState = .synced
            } catch { memo.syncState = .failed; recordFailure(error, item: "成长之声") }
            finishItem()
            saveAndRefresh(context)
        }
    }

    private func pushUnsyncedMedia(_ context: ModelContext) async {
        let descriptor = FetchDescriptor<Media>(
            predicate: #Predicate {
                $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading"
            })
        let mediaItems = (try? context.fetch(descriptor)) ?? []
        for media in mediaItems {
            guard !Task.isCancelled else { return }
            beginItem(media.type == .video ? "同步视频" : "同步媒体")
            guard let entry = media.entry else {
                media.syncState = .failed
                recordFailure(APIError.network("找不到这条媒体对应的记录"), item: "媒体")
                finishItem()
                saveAndRefresh(context)
                continue
            }
            await pushMediaItem(media, entryLocalId: entry.id)
            finishItem()
            saveAndRefresh(context)
        }
    }

    private func pushMediaItem(_ media: Media, entryLocalId: UUID) async {
        guard let fileName = media.localFileName else {
            media.syncState = .failed
            recordFailure(APIError.network("本地文件名为空"), item: "媒体")
            return
        }
        let url = mediaStore.mediaURL(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            media.syncState = .failed
            recordFailure(APIError.network("本地文件不见了"), item: "媒体")
            return
        }
        if let bytes = mediaStore.fileSize(forMedia: fileName),
           bytes > MediaStore.publicUploadSoftLimitBytes {
            lastLargeFileNotice = "这个\(media.type == .video ? "视频" : "文件")约 \(max(1, bytes / 1_048_576))MB，公网会继续尝试上传，失败后可稍后重试。"
        }
        media.syncState = .uploading
        let request = MediaUploadRequest(
            mediaId: media.id, entryLocalId: entryLocalId,
            fileURL: url, type: media.type, fileName: fileName)
        do {
            for try await event in apiClient.uploadMedia(request) {
                switch event {
                case .progress(let p):
                    media.uploadProgress = p
                    currentUploadProgress = p
                case .completed(let remoteId, let remoteURL):
                    media.remoteId = remoteId
                    media.remoteURL = remoteURL
                    media.uploadProgress = 1
                    media.syncState = .synced
                }
            }
        } catch {
            media.syncState = .failed
            recordFailure(error, item: media.type == .video ? "视频" : "媒体")
        }
    }

    private func pushTimeCapsules(_ context: ModelContext) async {
        let descriptor = FetchDescriptor<TimeCapsule>(
            predicate: #Predicate {
                $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading"
            })
        let capsules = (try? context.fetch(descriptor)) ?? []
        for capsule in capsules {
            guard !Task.isCancelled else { return }
            beginItem("同步时间胶囊")
            do {
                capsule.syncState = .uploading
                saveAndRefresh(context)
                var saved = try await apiClient.upsertTimeCapsule(Self.makeDTO(capsule))
                if let fileName = capsule.encryptedBlobFileName {
                    let url = mediaStore.mediaURL(for: fileName)
                    if FileManager.default.fileExists(atPath: url.path) {
                        for try await event in apiClient.uploadTimeCapsuleBlob(
                            capsuleId: capsule.id,
                            dto: Self.makeDTO(capsule),
                            fileURL: url,
                            fileName: fileName
                        ) {
                            switch event {
                            case .progress(let p):
                                currentUploadProgress = p
                            case .completed(let remoteId, let remoteURL):
                                saved.id = remoteId
                                saved.encryptedBlobRemoteURL = remoteURL
                            }
                        }
                    }
                }
                capsule.remoteId = saved.id
                capsule.syncState = .synced
            } catch {
                capsule.syncState = .failed
                recordFailure(error, item: "时间胶囊")
            }
            finishItem()
            saveAndRefresh(context)
        }
    }

    // MARK: - 拉：远端 → 本地

    /// 每个集合独立游标：成功才推进，失败下次补拉，互不影响。
    private func pullRemote() async {
        await pull("entries") { try await self.apiClient.fetchEntries(since: $0) }
            merge: { await self.mergeRemoteEntry($0) }
        await pull("media") { try await self.apiClient.fetchMedia(since: $0) }
            merge: { await self.mergeRemoteMedia($0) }
        await pull("milestones") { try await self.apiClient.fetchMilestones(since: $0) }
            merge: { await self.mergeRemoteMilestone($0) }
        if let context = modelContext {
            normalizeMilestonesByTitle(context)
            refreshWidgetSnapshot(context)
        }
        await pull("firsttimes") { try await self.apiClient.fetchFirstTimes(since: $0) }
            merge: { await self.mergeRemoteFirstTime($0) }
        await pull("members") { try await self.apiClient.fetchFamilyMembers(since: $0) }
            merge: { await self.mergeRemoteMember($0) }
        await pull("childprofile") { try await self.apiClient.fetchChildProfiles(since: $0) }
            merge: { await self.mergeRemoteChildProfile($0) }
        await pull("healthrecords") { try await self.apiClient.fetchHealthRecords(since: $0) }
            merge: { await self.mergeRemoteHealth($0) }
        await pull("vaccinerecords") { try await self.apiClient.fetchVaccineRecords(since: $0) }
            merge: { await self.mergeRemoteVaccine($0) }
        await pull("growthmeasurements") { try await self.apiClient.fetchGrowthMeasurements(since: $0) }
            merge: { await self.mergeRemoteGrowth($0) }
        await pull("comments") { try await self.apiClient.fetchComments(since: $0) }
            merge: { await self.mergeRemoteComment($0) }
        await pull("voicenotes") { try await self.apiClient.fetchVoiceNotes(since: $0) }
            merge: { await self.mergeRemoteVoiceNote($0) }
        await pull("voicememos") { try await self.apiClient.fetchVoiceMemos(since: $0) }
            merge: { await self.mergeRemoteVoiceMemo($0) }
        await pull("timecapsules") { try await self.apiClient.fetchTimeCapsules(since: $0) }
            merge: { await self.mergeRemoteTimeCapsule($0) }
    }

    private func pull<DTO>(_ collection: String,
                           fetch: (Date?) async throws -> [DTO],
                           merge: (DTO) async -> Bool) async {
        let started = Date.now
        do {
            let items = try await fetch(cursor(for: collection))
            var fullyMerged = true
            for dto in items {
                guard !Task.isCancelled else { return }
                if !(await merge(dto)) {
                    fullyMerged = false
                }
            }
            if fullyMerged {
                setCursor(started, for: collection)
                lastSyncedAt = started
            } else {
                softFailureThisRun = true
            }
        } catch {
            if Self.isMissingOptionalServerCollection(error, collection: collection) {
                setCursor(started, for: collection)
                return
            }
            // 瞬时拉取失败不立刻报红：标记本轮软失败，游标不推进，下轮自动补拉。
            softFailureThisRun = true
        }
    }

    private static func isMissingOptionalServerCollection(_ error: Error, collection: String) -> Bool {
        guard case APIError.server(let code, _) = error, code == 404 else { return false }
        return collection == "vaccinerecords" || collection == "growthmeasurements"
    }

    // MARK: - 下载：把远端媒体/语音落到本地（离线优先对多设备同样成立）

    /// 每轮同步最多下载若干个缺失文件，避免长时间占用；下一轮继续。
    private func downloadMissingFiles(_ context: ModelContext) async {
        let media = (try? context.fetch(FetchDescriptor<Media>(
            predicate: #Predicate { $0.localFileName == nil && $0.remoteURL != nil }))) ?? []
        for item in media.prefix(8) {
            guard !Task.isCancelled else { return }
            guard let remoteURL = item.remoteURL else { continue }
            currentSyncLabel = item.type == .video ? "下载视频" : "下载照片"
            do {
                let fileName = try await downloadRemoteFile(
                    remoteURL,
                    preferredExtension: item.type == .video ? "mp4" : "jpg",
                    sniffImage: item.type == .photo
                )
                item.localFileName = fileName
                if item.type == .photo,
                   let image = ThumbnailProvider.downsample(url: mediaStore.mediaURL(for: fileName), maxPixel: 600) {
                    item.thumbnailFileName = mediaStore.makePhotoThumbnail(fromImage: image)
                } else if item.type == .video {
                    item.thumbnailFileName = await mediaStore.makeVideoThumbnail(fromVideo: fileName)
                }
            } catch {
                // 缺失文件下载失败属瞬时、可自愈：标记软失败，下轮继续补拉，不立刻报红。
                softFailureThisRun = true
            }
            try? context.save()
        }

        let notes = (try? context.fetch(FetchDescriptor<VoiceNote>(
            predicate: #Predicate { $0.localFileName == nil && $0.remoteURL != nil }))) ?? []
        for note in notes.prefix(10) {
            guard !Task.isCancelled else { return }
            guard let remoteURL = note.remoteURL else { continue }
            currentSyncLabel = "下载语音"
            do {
                note.localFileName = try await downloadRemoteFile(remoteURL, preferredExtension: "m4a")
            } catch {
                softFailureThisRun = true
            }
            try? context.save()
        }

        let comments = (try? context.fetch(FetchDescriptor<Comment>(
            predicate: #Predicate { $0.voiceFileName == nil && $0.remoteURL != nil }))) ?? []
        for comment in comments.prefix(10) {
            guard !Task.isCancelled else { return }
            guard let remoteURL = comment.remoteURL else { continue }
            currentSyncLabel = "下载家人语音"
            do {
                comment.voiceFileName = try await downloadRemoteFile(remoteURL, preferredExtension: "m4a")
            } catch {
                softFailureThisRun = true
            }
            try? context.save()
        }

        let memos = (try? context.fetch(FetchDescriptor<VoiceMemo>(
            predicate: #Predicate { $0.localFileName == nil && $0.remoteURL != nil }))) ?? []
        for memo in memos.prefix(10) {
            guard !Task.isCancelled else { return }
            guard let remoteURL = memo.remoteURL else { continue }
            currentSyncLabel = "下载成长之声"
            do {
                memo.localFileName = try await downloadRemoteFile(remoteURL, preferredExtension: "m4a")
            } catch {
                softFailureThisRun = true
            }
            try? context.save()
        }

        let profiles = (try? context.fetch(FetchDescriptor<ChildProfile>(
            predicate: #Predicate { $0.avatarMediaFileName == nil && $0.avatarRemoteURL != nil }))) ?? []
        for profile in profiles.prefix(2) {
            guard !Task.isCancelled else { return }
            guard let remoteURL = profile.avatarRemoteURL else { continue }
            currentSyncLabel = "下载布布头像"
            do {
                profile.avatarMediaFileName = try await downloadRemoteFile(remoteURL, preferredExtension: "jpg", sniffImage: true)
            } catch {
                softFailureThisRun = true
            }
            try? context.save()
            refreshWidgetSnapshot(context)
        }
    }

    private func downloadRemoteFile(_ remoteURL: String,
                                    preferredExtension: String,
                                    sniffImage: Bool = false) async throws -> String {
        let tempURL = try await apiClient.downloadFileToTemporaryURL(from: remoteURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let ext = Self.pathExtension(from: remoteURL, fallback: preferredExtension)
        return try mediaStore.importFile(from: tempURL, preferredExtension: ext, sniffImage: sniffImage)
    }

    private static func pathExtension(from remoteURL: String, fallback: String) -> String {
        guard let url = URL(string: remoteURL) else { return fallback }
        let ext = url.pathExtension
        return ext.isEmpty ? fallback : ext
    }

    /// 把远端 Entry 合并进本地（按 localId 去重；远端较新则更新）。
    private func mergeRemoteEntry(_ dto: EntryDTO) async -> Bool {
        guard let context = modelContext,
              let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        if isPendingDeletion(collection: "entries", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == localId })
        let existing = try? context.fetch(descriptor).first

        if let entry = existing {
            // 已有：仅当本地已同步（无本地未推改动）时用远端覆盖，避免踩掉本地草稿
            if entry.syncState == .synced {
                Self.apply(dto, to: entry)
                entry.remoteId = dto.id
            } else if Self.remoteEntryWins(dto, over: entry) {
                Self.apply(dto, to: entry)
                entry.remoteId = dto.id
                entry.syncState = .synced
            } else {
                return false
            }
        } else {
            let entry = Entry(happenedAt: dto.happenedAt, authorRole: dto.authorRole, note: dto.note)
            entry.id = localId
            Self.apply(dto, to: entry)
            entry.remoteId = dto.id
            entry.syncState = .synced
            context.insert(entry)
        }
        try? context.save()
        refreshWidgetSnapshot(context)
        return true
    }

    private func mergeRemoteMedia(_ dto: MediaDTO) async -> Bool {
        guard let context = modelContext,
              let mediaId = UUID(uuidString: dto.localId),
              let entryId = UUID(uuidString: dto.entryLocalId) else { return modelContext != nil }
        if isPendingDeletion(collection: "media", remoteId: dto.id, context: context) { return true }
        let mediaDescriptor = FetchDescriptor<Media>(predicate: #Predicate { $0.id == mediaId })
        if let existing = try? context.fetch(mediaDescriptor).first {
            if existing.syncState == .synced {
                Self.apply(dto, to: existing)
            } else {
                return false
            }
            return true
        }
        let entryDescriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryId })
        guard let entry = try? context.fetch(entryDescriptor).first else { return false }
        let media = Media(type: MediaType(rawValue: dto.mediaType) ?? .photo, localFileName: nil)
        media.id = mediaId
        Self.apply(dto, to: media)
        media.entry = entry
        media.syncState = .synced
        context.insert(media)
        try? context.save()
        return true
    }

    private func mergeRemoteMilestone(_ dto: MilestoneDTO) async -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        guard !Self.isRemotePresetPlaceholder(dto) else { return true }
        if isPendingDeletion(collection: "milestones", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<Milestone>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else if let existingByTitle = findMilestone(title: dto.title, context: context) {
            if existingByTitle.syncState == .synced {
                Self.apply(dto, to: existingByTitle)
                existingByTitle.remoteId = dto.id
            } else { return false }
        } else {
            let item = Milestone(title: dto.title, category: dto.category, emoji: dto.emoji, happenedAt: dto.happenedAt, isCustom: dto.isCustom)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
        refreshWidgetSnapshot(context)
        return true
    }

    private func findMilestone(title: String, context: ModelContext) -> Milestone? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        let descriptor = FetchDescriptor<Milestone>(predicate: #Predicate { $0.title == cleanTitle })
        return try? context.fetch(descriptor).first
    }

    private func normalizeMilestonesByTitle(_ context: ModelContext) {
        let milestones = (try? context.fetch(FetchDescriptor<Milestone>())) ?? []
        guard milestones.count > 1 else { return }
        var bestByTitle: [String: Milestone] = [:]
        var duplicates: [Milestone] = []
        for milestone in milestones {
            let title = milestone.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                duplicates.append(milestone)
                continue
            }
            milestone.title = title
            if let current = bestByTitle[title] {
                if Self.milestoneRank(milestone) > Self.milestoneRank(current) {
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
            if Self.isLocalPresetPlaceholder(milestone) {
                milestone.syncState = .synced
            }
        }
        for duplicate in duplicates {
            context.delete(duplicate)
        }
        try? context.save()
    }

    private static func milestoneRank(_ milestone: Milestone) -> Int {
        (milestone.isAchieved ? 1_000 : 0)
        + ((milestone.detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 200 : 0)
        + (milestone.isCustom ? 100 : 0)
        + (milestone.remoteId == nil ? 0 : 20)
        + Int(min(19, max(0, Date.now.timeIntervalSince(milestone.createdAt) / 86_400)))
    }

    private func mergeRemoteFirstTime(_ dto: FirstTimeDTO) async -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        if isPendingDeletion(collection: "firsttimes", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<FirstTime>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let item = FirstTime(what: dto.what, happenedAt: dto.happenedAt)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            if let entryLocalId = dto.entryLocalId, let entryId = UUID(uuidString: entryLocalId) {
                let entryDescriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryId })
                item.entry = try? context.fetch(entryDescriptor).first
            }
            context.insert(item)
        }
        try? context.save()
        return true
    }

    private func mergeRemoteMember(_ dto: FamilyMemberDTO) async -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        if isPendingDeletion(collection: "members", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let item = FamilyMember(name: dto.name, relation: dto.relation, avatarEmoji: dto.avatarEmoji, themeColorHex: dto.themeColorHex)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
        return true
    }

    private func mergeRemoteChildProfile(_ dto: ChildProfileDTO) async -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        if isPendingDeletion(collection: "childprofile", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let item = ChildProfile(name: dto.name, birthday: dto.birthday)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
        refreshWidgetSnapshot(context)
        return true
    }

    private func mergeRemoteHealth(_ dto: HealthRecordDTO) async -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        if isPendingDeletion(collection: "healthrecords", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<HealthRecord>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let item = HealthRecord(kind: HealthRecordKind(rawValue: dto.kind) ?? .meal, title: dto.title, recordedAt: dto.recordedAt)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
        backfillVaccineIfNeeded(from: dto, context: context)
        GrowthMeasurementBackfill.run(context: context, insertedSyncState: .synced, source: "health-fallback")
        refreshWidgetSnapshot(context)
        return true
    }

    private func mergeRemoteVaccine(_ dto: VaccineRecordDTO) async -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        // 防复活：该远端记录已在本地删除队列中（删除尚未推到服务器）时，不重新合并
        if isPendingDeletion(collection: "vaccinerecords", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<VaccineRecord>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let item = VaccineRecord(vaccineName: dto.vaccineName, injectedAt: dto.injectedAt, source: dto.source)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
        return true
    }

    private func mergeRemoteGrowth(_ dto: GrowthMeasurementDTO) async -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        if isPendingDeletion(collection: "growthmeasurements", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<GrowthMeasurement>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let item = GrowthMeasurement(measuredAt: dto.measuredAt, source: dto.source)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
        return true
    }

    private func mergeRemoteComment(_ dto: CommentDTO) async -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId), let entryId = UUID(uuidString: dto.entryLocalId) else { return modelContext != nil }
        if isPendingDeletion(collection: "comments", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<Comment>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let entryDescriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryId })
            guard let entry = try? context.fetch(entryDescriptor).first else { return false }
            let item = Comment(authorRole: dto.authorRole, text: dto.text)
            item.id = localId; Self.apply(dto, to: item); item.entry = entry; item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
        return true
    }

    private func mergeRemoteVoiceNote(_ dto: VoiceNoteDTO) async -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId), let entryId = UUID(uuidString: dto.entryLocalId) else { return modelContext != nil }
        if isPendingDeletion(collection: "voicenotes", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let entryDescriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryId })
            guard let entry = try? context.fetch(entryDescriptor).first else { return false }
            let item = VoiceNote(localFileName: nil, durationSeconds: dto.durationSeconds, authorRole: dto.authorRole, waveformSamples: dto.waveform)
            item.id = localId; Self.apply(dto, to: item); item.entry = entry; item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
        return true
    }

    private func mergeRemoteVoiceMemo(_ dto: VoiceMemoDTO) async -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        if isPendingDeletion(collection: "voicememos", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<VoiceMemo>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
            else { return false }
        } else {
            let item = VoiceMemo(kind: VoiceMemo.Kind(rawValue: dto.kind) ?? .childVoice, recordedAt: dto.recordedAt)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
        return true
    }

    private func mergeRemoteTimeCapsule(_ dto: TimeCapsuleDTO) async -> Bool {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return modelContext != nil }
        if isPendingDeletion(collection: "timecapsules", remoteId: dto.id, context: context) { return true }
        let descriptor = FetchDescriptor<TimeCapsule>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced {
                Self.apply(dto, to: existing)
                existing.remoteId = dto.id
                await ensureLocalCapsuleBlob(for: existing, dto: dto)
            } else { return false }
        } else {
            let item = TimeCapsule(title: dto.title, fromRole: dto.fromRole, unlockAt: dto.unlockAt)
            item.id = localId
            Self.apply(dto, to: item)
            item.remoteId = dto.id
            item.syncState = .synced
            context.insert(item)
            await ensureLocalCapsuleBlob(for: item, dto: dto)
        }
        try? context.save()
        return true
    }

    private func ensureLocalCapsuleBlob(for capsule: TimeCapsule, dto: TimeCapsuleDTO) async {
        if let fileName = capsule.encryptedBlobFileName,
           mediaStore.fileExists(forMedia: fileName) {
            return
        }
        guard let remoteURL = dto.encryptedBlobRemoteURL else { return }
        do {
            capsule.encryptedBlobFileName = try await downloadRemoteFile(remoteURL, preferredExtension: "capsule")
        } catch {
            recordFailure(error, item: "下载时间胶囊")
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

    private static func remoteEntryWins(_ dto: EntryDTO, over entry: Entry) -> Bool {
        guard let remoteEditedAt = dto.editedAt else { return false }
        return remoteEditedAt > (entry.editedAt ?? entry.createdAt)
    }

    private static func apply(_ dto: MediaDTO, to media: Media) {
        media.remoteId = dto.id
        media.typeRaw = dto.mediaType
        media.remoteURL = dto.remoteURL
        media.durationSeconds = dto.durationSeconds
        media.width = dto.width
        media.height = dto.height
        media.aiTags = dto.aiTags
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
                        avatarRemoteURL: item.avatarRemoteURL, createdAt: item.createdAt)
    }

    private static func apply(_ dto: ChildProfileDTO, to item: ChildProfile) {
        item.name = dto.name; item.birthday = dto.birthday; item.gender = dto.gender
        item.bloodType = dto.bloodType; item.birthPlace = dto.birthPlace
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
                         note: item.note, source: item.sourceRaw, createdAt: item.createdAt)
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
                             source: item.sourceRaw, createdAt: item.createdAt)
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

    private func backfillVaccineIfNeeded(from dto: HealthRecordDTO, context: ModelContext) {
        guard let localId = UUID(uuidString: dto.localId) else { return }
        let isVaccine = dto.tags.contains("疫苗") || dto.title.contains("疫苗")
        guard isVaccine else { return }
        let descriptor = FetchDescriptor<VaccineRecord>(predicate: #Predicate { $0.id == localId })
        guard (try? context.fetch(descriptor).first) == nil else { return }

        let name = Self.vaccineName(from: dto)
        let item = VaccineRecord(vaccineName: name, injectedAt: dto.recordedAt, source: "health-fallback")
        item.id = localId
        item.doseLabel = dto.amountText
        item.reaction = dto.reaction
        item.note = dto.detail
        item.syncState = .synced
        context.insert(item)
        try? context.save()
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
                       encryptedBlobRemoteURL: nil, coverEmoji: item.coverEmoji, createdAt: item.createdAt)
    }

    private static func apply(_ dto: TimeCapsuleDTO, to item: TimeCapsule) {
        item.title = dto.title
        item.fromRole = dto.fromRole
        // 不覆盖 unlockAt：封存后不可变，密钥派生依赖它；
        // 远端 ISO 序列化会截断亚秒，覆盖会让旧版(v1)胶囊永久解不开。
        // 新建路径由 TimeCapsule(init:) 直接用远端值，不经过这里。
        item.isLocked = dto.isLocked
        item.coverEmoji = dto.coverEmoji
        item.createdAt = dto.createdAt
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
