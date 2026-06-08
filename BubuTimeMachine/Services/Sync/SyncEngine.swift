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

    private var apiClient: APIClient
    private let config: ServerConfig
    private let mediaStore: MediaStore
    private var modelContext: ModelContext?
    private var realtimeTask: Task<Void, Never>?
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
        self.apiClient = client
    }
    /// 由 App 注入主上下文（同步需要读写 SwiftData）。
    func attach(context: ModelContext) {
        self.modelContext = context
    }

    /// 启动同步层：已配置则连接 + 首次全量推拉 + 起轮询；否则保持离线。
    func start() {
        guard config.isConfigured else {
            connectionState = .offline
            return
        }
        connectionState = .connecting
        Task { await connectAndSync() }
    }

    /// 手动触发一次同步（设置页/下拉刷新可调）。
    func syncNow() {
        guard config.isConfigured else { return }
        Task { await pushLocal(); await pullRemote() }
    }

    // MARK: - 连接

    private func connectAndSync() async {
        let ok = (try? await apiClient.ping()) ?? false
        guard ok else { connectionState = .offline; return }
        // 鉴权
        _ = try? await apiClient.authenticate(role: config.currentRole.rawValue)
        connectionState = .online

        await pushLocal()
        await pullRemote()
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
            predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" })
        guard let locals = try? context.fetch(descriptor) else { return }
        pendingCount = locals.count

        for entry in locals {
            entry.syncState = .uploading
            let dto = Self.makeDTO(entry)
            do {
                let saved = try await apiClient.createEntry(dto)
                entry.remoteId = saved.id
                // 上传该 Entry 的媒体
                await pushMedia(of: entry)
                entry.syncState = .synced
            } catch {
                entry.syncState = .failed
            }
        }
        await pushLocalJSONObjects(context)
        try? context.save()
        pendingCount = 0
        lastSyncedAt = .now
    }

    private func pushLocalJSONObjects(_ context: ModelContext) async {
        let localMilestones = (try? context.fetch(FetchDescriptor<Milestone>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" }))) ?? []
        for item in localMilestones {
            do { let saved = try await apiClient.upsertMilestone(Self.makeDTO(item)); item.remoteId = saved.id; item.syncState = .synced }
            catch { item.syncState = .failed }
        }
        let localFirstTimes = (try? context.fetch(FetchDescriptor<FirstTime>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" }))) ?? []
        for item in localFirstTimes {
            do { let saved = try await apiClient.upsertFirstTime(Self.makeDTO(item)); item.remoteId = saved.id; item.syncState = .synced }
            catch { item.syncState = .failed }
        }
        let localMembers = (try? context.fetch(FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" }))) ?? []
        for item in localMembers {
            do { let saved = try await apiClient.upsertFamilyMember(Self.makeDTO(item)); item.remoteId = saved.id; item.syncState = .synced }
            catch { item.syncState = .failed }
        }
        let localProfiles = (try? context.fetch(FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" }))) ?? []
        for item in localProfiles {
            do { let saved = try await apiClient.upsertChildProfile(Self.makeDTO(item)); item.remoteId = saved.id; item.syncState = .synced }
            catch { item.syncState = .failed }
        }
        let localHealth = (try? context.fetch(FetchDescriptor<HealthRecord>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" }))) ?? []
        for item in localHealth {
            do { let saved = try await apiClient.upsertHealthRecord(Self.makeDTO(item)); item.remoteId = saved.id; item.syncState = .synced }
            catch { item.syncState = .failed }
        }
        await pushLocalFileObjects(context)
    }

    private func pushLocalFileObjects(_ context: ModelContext) async {
        let comments = (try? context.fetch(FetchDescriptor<Comment>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" }))) ?? []
        for comment in comments {
            do {
                var saved = try await apiClient.upsertComment(Self.makeDTO(comment))
                if let fileName = comment.voiceFileName, let entryId = comment.entry?.id {
                    let url = mediaStore.mediaURL(for: fileName)
                    if FileManager.default.fileExists(atPath: url.path) {
                        for try await event in apiClient.uploadCommentVoice(commentId: comment.id, entryLocalId: entryId, fileURL: url, fileName: fileName) {
                            if case .completed(let remoteId, let remoteURL) = event { saved.id = remoteId; comment.remoteURL = remoteURL }
                        }
                    }
                }
                comment.remoteId = saved.id; comment.syncState = .synced
            } catch { comment.syncState = .failed }
        }
        let notes = (try? context.fetch(FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" }))) ?? []
        for note in notes {
            do {
                var saved = try await apiClient.upsertVoiceNote(Self.makeDTO(note))
                if let fileName = note.localFileName, let entryId = note.entry?.id {
                    let url = mediaStore.mediaURL(for: fileName)
                    if FileManager.default.fileExists(atPath: url.path) {
                        for try await event in apiClient.uploadVoiceNote(voiceId: note.id, entryLocalId: entryId, fileURL: url, fileName: fileName) {
                            if case .completed(let remoteId, let remoteURL) = event { saved.id = remoteId; note.remoteURL = remoteURL }
                        }
                    }
                }
                note.remoteId = saved.id; note.syncState = .synced
            } catch { note.syncState = .failed }
        }
        let memos = (try? context.fetch(FetchDescriptor<VoiceMemo>(predicate: #Predicate { $0.syncStateRaw == "local" || $0.syncStateRaw == "failed" }))) ?? []
        for memo in memos {
            do {
                var saved = try await apiClient.upsertVoiceMemo(Self.makeDTO(memo))
                if let fileName = memo.localFileName {
                    let url = mediaStore.mediaURL(for: fileName)
                    if FileManager.default.fileExists(atPath: url.path) {
                        for try await event in apiClient.uploadVoiceMemo(memoId: memo.id, fileURL: url, fileName: fileName) {
                            if case .completed(let remoteId, let remoteURL) = event { saved.id = remoteId; memo.remoteURL = remoteURL }
                        }
                    }
                }
                memo.remoteId = saved.id; memo.syncState = .synced
            } catch { memo.syncState = .failed }
        }
    }

    private func pushMedia(of entry: Entry) async {
        for media in entry.media where media.syncState != .synced {
            guard let fileName = media.localFileName else { continue }
            let url = mediaStore.mediaURL(for: fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            media.syncState = .uploading
            let request = MediaUploadRequest(
                mediaId: media.id, entryLocalId: entry.id,
                fileURL: url, type: media.type, fileName: fileName)
            do {
                for try await event in apiClient.uploadMedia(request) {
                    switch event {
                    case .progress(let p): media.uploadProgress = p
                    case .completed(let remoteId, let remoteURL):
                        media.remoteId = remoteId
                        media.remoteURL = remoteURL
                        media.uploadProgress = 1
                        media.syncState = .synced
                    }
                }
            } catch {
                media.syncState = .failed
            }
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
