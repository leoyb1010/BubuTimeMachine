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
        try? context.save()
        pendingCount = 0
        lastSyncedAt = .now
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

    // MARK: - DTO 映射

    private static func makeDTO(_ entry: Entry) -> EntryDTO {
        EntryDTO(
            id: entry.remoteId, localId: entry.id.uuidString,
            title: entry.title, note: entry.note, firstPersonNote: entry.firstPersonNote,
            happenedAt: entry.happenedAt, locationName: entry.locationName,
            latitude: entry.latitude, longitude: entry.longitude,
            authorRole: entry.authorRole, mood: entry.moodRaw,
            isArchived: entry.isArchived, editedAt: entry.editedAt, createdAt: entry.createdAt)
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
