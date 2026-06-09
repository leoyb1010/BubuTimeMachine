import Foundation
import SwiftData
import Observation

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

    var syncProgress: Double? {
        guard totalPendingAtStart > 0 else { return nil }
        let uploadFraction = currentUploadProgress ?? 0
        return min(1, (Double(processedThisRun) + uploadFraction) / Double(totalPendingAtStart))
    }

    private var apiClient: APIClient
    private let config: ServerConfig
    private let mediaStore: MediaStore
    private var modelContext: ModelContext?
    private var realtimeTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var needsAnotherSync = false
    private var pollTimer: Timer?

    init(apiClient: APIClient, config: ServerConfig, mediaStore: MediaStore) {
        self.apiClient = apiClient
        self.config = config
        self.mediaStore = mediaStore
    }

    /// 设置变更后替换底层客户端并重连。
    func setClient(_ client: APIClient) {
        realtimeTask?.cancel()
        realtimeTask = nil
        syncTask?.cancel()
        syncTask = nil
        pollTimer?.invalidate()
        pollTimer = nil
        self.apiClient = client
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

    // MARK: - 连接

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 18, repeats: true) { [weak self] _ in
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
        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.connectAndSync()
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
        guard ok else {
            connectionState = .offline
            currentSyncLabel = nil
            recordFailure(APIError.network("连不上家里的服务器"), item: "连接")
            refreshPendingCount()
            return
        }
        do {
            _ = try await apiClient.authenticate(role: config.currentRole.rawValue)
        } catch {
            connectionState = .offline
            currentSyncLabel = nil
            recordFailure(error, item: "账号")
            refreshPendingCount()
            return
        }
        connectionState = .online

        await pushLocal()
        await pullRemote()
        currentSyncLabel = nil
        currentUploadProgress = nil
        startRealtime()
    }

    private func startRealtime() {
        realtimeTask?.cancel()
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            for await event in apiClient.subscribeRealtime() {
                if Task.isCancelled { break }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: RealtimeEvent) async {
        switch event {
        case .entryChanged(let dto): await mergeRemoteEntry(dto)
        case .entryDeleted: break
        case .connected: connectionState = .online
        case .disconnected: connectionState = .offline
        }
    }

    // MARK: - 推：本地 → 远端

    private func pushLocal() async {
        guard let context = modelContext else { return }
        // 取所有未同步（local/failed）的 Entry
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate {
                $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading"
            })
        guard let locals = try? context.fetch(descriptor) else { return }
        refreshPendingCount()

        for entry in locals {
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

    private func beginSyncRun() {
        refreshPendingCount()
        totalPendingAtStart = pendingCount
        processedThisRun = 0
        currentUploadProgress = nil
        lastFailureReason = nil
        lastLargeFileNotice = nil
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
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastFailureReason = "\(item)：\(message)"
    }

    private func refreshPendingCount() {
        guard let context = modelContext else {
            pendingCount = 0
            return
        }
        pendingCount =
            countPending(Entry.self, in: context) +
            countPending(Media.self, in: context) +
            countPending(Milestone.self, in: context) +
            countPending(FirstTime.self, in: context) +
            countPending(FamilyMember.self, in: context) +
            countPending(ChildProfile.self, in: context) +
            countPending(HealthRecord.self, in: context) +
            countPending(Comment.self, in: context) +
            countPending(VoiceNote.self, in: context) +
            countPending(VoiceMemo.self, in: context) +
            countPending(TimeCapsule.self, in: context)
    }

    private func countPending<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<T>()
        guard let items = try? context.fetch(descriptor) else { return 0 }
        return items.reduce(0) { count, item in
            count + (Self.isPending(item) ? 1 : 0)
        }
    }

    private static func isPending<T: PersistentModel>(_ item: T) -> Bool {
        switch item {
        case let item as Entry:
            return item.syncState == .local || item.syncState == .failed || item.syncState == .uploading
        case let item as Media:
            return item.syncState == .local || item.syncState == .failed || item.syncState == .uploading
        case let item as Milestone:
            return item.syncState == .local || item.syncState == .failed || item.syncState == .uploading
        case let item as FirstTime:
            return item.syncState == .local || item.syncState == .failed || item.syncState == .uploading
        case let item as FamilyMember:
            return item.syncState == .local || item.syncState == .failed || item.syncState == .uploading
        case let item as ChildProfile:
            return item.syncState == .local || item.syncState == .failed || item.syncState == .uploading
        case let item as HealthRecord:
            return item.syncState == .local || item.syncState == .failed || item.syncState == .uploading
        case let item as Comment:
            return item.syncState == .local || item.syncState == .failed || item.syncState == .uploading
        case let item as VoiceNote:
            return item.syncState == .local || item.syncState == .failed || item.syncState == .uploading
        case let item as VoiceMemo:
            return item.syncState == .local || item.syncState == .failed || item.syncState == .uploading
        case let item as TimeCapsule:
            return item.syncState == .local || item.syncState == .failed || item.syncState == .uploading
        default:
            return false
        }
    }

    private func pushLocalJSONObjects(_ context: ModelContext) async {
        let localMilestones = (try? context.fetch(FetchDescriptor<Milestone>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        for item in localMilestones {
            beginItem("同步里程碑")
            do { item.syncState = .uploading; saveAndRefresh(context); let saved = try await apiClient.upsertMilestone(Self.makeDTO(item)); item.remoteId = saved.id; item.syncState = .synced }
            catch { item.syncState = .failed; recordFailure(error, item: "里程碑") }
            finishItem()
            saveAndRefresh(context)
        }
        let localFirstTimes = (try? context.fetch(FetchDescriptor<FirstTime>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        for item in localFirstTimes {
            beginItem("同步第一次")
            do { item.syncState = .uploading; saveAndRefresh(context); let saved = try await apiClient.upsertFirstTime(Self.makeDTO(item)); item.remoteId = saved.id; item.syncState = .synced }
            catch { item.syncState = .failed; recordFailure(error, item: "第一次") }
            finishItem()
            saveAndRefresh(context)
        }
        let localMembers = (try? context.fetch(FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        for item in localMembers {
            beginItem("同步家庭成员")
            do { item.syncState = .uploading; saveAndRefresh(context); let saved = try await apiClient.upsertFamilyMember(Self.makeDTO(item)); item.remoteId = saved.id; item.syncState = .synced }
            catch { item.syncState = .failed; recordFailure(error, item: "家庭成员") }
            finishItem()
            saveAndRefresh(context)
        }
        let localProfiles = (try? context.fetch(FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        for item in localProfiles {
            beginItem("同步布布档案")
            do { item.syncState = .uploading; saveAndRefresh(context); let saved = try await apiClient.upsertChildProfile(Self.makeDTO(item)); item.remoteId = saved.id; item.syncState = .synced }
            catch { item.syncState = .failed; recordFailure(error, item: "布布档案") }
            finishItem()
            saveAndRefresh(context)
        }
        let localHealth = (try? context.fetch(FetchDescriptor<HealthRecord>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        for item in localHealth {
            beginItem("同步健康记录")
            do { item.syncState = .uploading; saveAndRefresh(context); let saved = try await apiClient.upsertHealthRecord(Self.makeDTO(item)); item.remoteId = saved.id; item.syncState = .synced }
            catch { item.syncState = .failed; recordFailure(error, item: "健康记录") }
            finishItem()
            saveAndRefresh(context)
        }
        await pushLocalFileObjects(context)
    }

    private func pushLocalFileObjects(_ context: ModelContext) async {
        let comments = (try? context.fetch(FetchDescriptor<Comment>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" || $0.syncStateRaw == "uploading" }))) ?? []
        for comment in comments {
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

    private func pullRemote() async {
        guard let entries = try? await apiClient.fetchEntries(since: lastSyncedAt) else { return }
        for dto in entries { await mergeRemoteEntry(dto) }
        if let media = try? await apiClient.fetchMedia(since: lastSyncedAt) {
            for dto in media { await mergeRemoteMedia(dto) }
        }
        if let milestones = try? await apiClient.fetchMilestones(since: lastSyncedAt) {
            for dto in milestones { await mergeRemoteMilestone(dto) }
        }
        if let firstTimes = try? await apiClient.fetchFirstTimes(since: lastSyncedAt) {
            for dto in firstTimes { await mergeRemoteFirstTime(dto) }
        }
        if let members = try? await apiClient.fetchFamilyMembers(since: lastSyncedAt) {
            for dto in members { await mergeRemoteMember(dto) }
        }
        if let profiles = try? await apiClient.fetchChildProfiles(since: lastSyncedAt) {
            for dto in profiles { await mergeRemoteChildProfile(dto) }
        }
        if let health = try? await apiClient.fetchHealthRecords(since: lastSyncedAt) {
            for dto in health { await mergeRemoteHealth(dto) }
        }
        if let comments = try? await apiClient.fetchComments(since: lastSyncedAt) {
            for dto in comments { await mergeRemoteComment(dto) }
        }
        if let voiceNotes = try? await apiClient.fetchVoiceNotes(since: lastSyncedAt) {
            for dto in voiceNotes { await mergeRemoteVoiceNote(dto) }
        }
        if let voiceMemos = try? await apiClient.fetchVoiceMemos(since: lastSyncedAt) {
            for dto in voiceMemos { await mergeRemoteVoiceMemo(dto) }
        }
        if let capsules = try? await apiClient.fetchTimeCapsules(since: lastSyncedAt) {
            for dto in capsules { await mergeRemoteTimeCapsule(dto) }
        }
        lastSyncedAt = .now
    }

    /// 把远端 Entry 合并进本地（按 localId 去重；远端较新则更新）。
    private func mergeRemoteEntry(_ dto: EntryDTO) async {
        guard let context = modelContext,
              let localId = UUID(uuidString: dto.localId) else { return }
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == localId })
        let existing = try? context.fetch(descriptor).first

        if let entry = existing {
            // 已有：仅当本地已同步（无本地未推改动）时用远端覆盖，避免踩掉本地草稿
            if entry.syncState == .synced {
                Self.apply(dto, to: entry)
                entry.remoteId = dto.id
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
    }

    private func mergeRemoteMedia(_ dto: MediaDTO) async {
        guard let context = modelContext,
              let mediaId = UUID(uuidString: dto.localId),
              let entryId = UUID(uuidString: dto.entryLocalId) else { return }
        let mediaDescriptor = FetchDescriptor<Media>(predicate: #Predicate { $0.id == mediaId })
        if let existing = try? context.fetch(mediaDescriptor).first {
            if existing.syncState == .synced {
                Self.apply(dto, to: existing)
            }
            return
        }
        let entryDescriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryId })
        guard let entry = try? context.fetch(entryDescriptor).first else { return }
        let media = Media(type: MediaType(rawValue: dto.mediaType) ?? .photo, localFileName: nil)
        media.id = mediaId
        Self.apply(dto, to: media)
        media.entry = entry
        media.syncState = .synced
        context.insert(media)
        try? context.save()
    }

    private func mergeRemoteMilestone(_ dto: MilestoneDTO) async {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return }
        let descriptor = FetchDescriptor<Milestone>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
        } else {
            let item = Milestone(title: dto.title, category: dto.category, emoji: dto.emoji, happenedAt: dto.happenedAt, isCustom: dto.isCustom)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
    }

    private func mergeRemoteFirstTime(_ dto: FirstTimeDTO) async {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return }
        let descriptor = FetchDescriptor<FirstTime>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
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
    }

    private func mergeRemoteMember(_ dto: FamilyMemberDTO) async {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return }
        let descriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
        } else {
            let item = FamilyMember(name: dto.name, relation: dto.relation, avatarEmoji: dto.avatarEmoji, themeColorHex: dto.themeColorHex)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
    }

    private func mergeRemoteChildProfile(_ dto: ChildProfileDTO) async {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return }
        let descriptor = FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
        } else {
            let item = ChildProfile(name: dto.name, birthday: dto.birthday)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
    }

    private func mergeRemoteHealth(_ dto: HealthRecordDTO) async {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return }
        let descriptor = FetchDescriptor<HealthRecord>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
        } else {
            let item = HealthRecord(kind: HealthRecordKind(rawValue: dto.kind) ?? .meal, title: dto.title, recordedAt: dto.recordedAt)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
    }

    private func mergeRemoteComment(_ dto: CommentDTO) async {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId), let entryId = UUID(uuidString: dto.entryLocalId) else { return }
        let descriptor = FetchDescriptor<Comment>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
        } else {
            let entryDescriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryId })
            guard let entry = try? context.fetch(entryDescriptor).first else { return }
            let item = Comment(authorRole: dto.authorRole, text: dto.text)
            item.id = localId; Self.apply(dto, to: item); item.entry = entry; item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
    }

    private func mergeRemoteVoiceNote(_ dto: VoiceNoteDTO) async {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId), let entryId = UUID(uuidString: dto.entryLocalId) else { return }
        let descriptor = FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
        } else {
            let entryDescriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryId })
            guard let entry = try? context.fetch(entryDescriptor).first else { return }
            let item = VoiceNote(localFileName: nil, durationSeconds: dto.durationSeconds, authorRole: dto.authorRole, waveformSamples: dto.waveform)
            item.id = localId; Self.apply(dto, to: item); item.entry = entry; item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
    }

    private func mergeRemoteVoiceMemo(_ dto: VoiceMemoDTO) async {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return }
        let descriptor = FetchDescriptor<VoiceMemo>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced { Self.apply(dto, to: existing); existing.remoteId = dto.id }
        } else {
            let item = VoiceMemo(kind: VoiceMemo.Kind(rawValue: dto.kind) ?? .childVoice, recordedAt: dto.recordedAt)
            item.id = localId; Self.apply(dto, to: item); item.remoteId = dto.id; item.syncState = .synced
            context.insert(item)
        }
        try? context.save()
    }

    private func mergeRemoteTimeCapsule(_ dto: TimeCapsuleDTO) async {
        guard let context = modelContext, let localId = UUID(uuidString: dto.localId) else { return }
        let descriptor = FetchDescriptor<TimeCapsule>(predicate: #Predicate { $0.id == localId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.syncState == .synced {
                Self.apply(dto, to: existing)
                existing.remoteId = dto.id
                await ensureLocalCapsuleBlob(for: existing, dto: dto)
            }
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
    }

    private func ensureLocalCapsuleBlob(for capsule: TimeCapsule, dto: TimeCapsuleDTO) async {
        if let fileName = capsule.encryptedBlobFileName,
           mediaStore.fileExists(forMedia: fileName) {
            return
        }
        guard let remoteURL = dto.encryptedBlobRemoteURL else { return }
        do {
            let data = try await apiClient.downloadFile(from: remoteURL)
            capsule.encryptedBlobFileName = try mediaStore.saveBlob(data)
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
            isArchived: entry.isArchived, editedAt: entry.editedAt, createdAt: entry.createdAt)
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
                        gender: item.gender, birthPlace: item.birthPlace, createdAt: item.createdAt)
    }

    private static func apply(_ dto: ChildProfileDTO, to item: ChildProfile) {
        item.name = dto.name; item.birthday = dto.birthday; item.gender = dto.gender; item.birthPlace = dto.birthPlace
    }

    private static func makeDTO(_ item: HealthRecord) -> HealthRecordDTO {
        HealthRecordDTO(id: item.remoteId, localId: item.id.uuidString, kind: item.kindRaw, title: item.title,
                        detail: item.detail, recordedAt: item.recordedAt, amountText: item.amountText,
                        reaction: item.reaction, createdAt: item.createdAt)
    }

    private static func apply(_ dto: HealthRecordDTO, to item: HealthRecord) {
        item.kindRaw = dto.kind; item.title = dto.title; item.detail = dto.detail; item.recordedAt = dto.recordedAt
        item.amountText = dto.amountText; item.reaction = dto.reaction
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
        item.unlockAt = dto.unlockAt
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
        entry.editedAt = dto.editedAt
    }
}
