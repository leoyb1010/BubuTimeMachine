import Foundation
import SwiftData
import WatchConnectivity
import os

// MARK: - 手表连接（iPhone 侧）
/// 收手表发来的记录意图 → 写入 App Group 共享 store（EntryWriter，幂等）→ 通知 App 触发同步。
/// 同时把概览快照推给手表。手表不跑 SwiftData/同步，一切写入与上云都在 iPhone 完成。
@MainActor
final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    /// 收到手表记录后广播，AppEnvironment 监听以立即同步 + 刷新快照。
    static let didRecordNotification = Notification.Name("bubu.watch.didRecord")

    private let log = Logger(subsystem: "com.bubu.timemachine", category: "WatchConnectivity")
    private var pendingSnapshot: WatchSnapshot?

    /// App 正在用的 mainContext（与 @Query/UI 同一个）。激活时注入，保证手表写入能让前台时光轴实时刷新。
    /// 未注入（如后台被 WC 唤醒）时回退到共享容器，数据仍落库、下次前台自会显示。
    var appContext: ModelContext?
    private var writeContext: ModelContext? { appContext ?? SharedModelContainer.sharedIfAvailable?.mainContext }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// 把概览快照推给手表（合并最新态，省电）。未激活时缓存，激活后补发。
    func push(_ snapshot: WatchSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { pendingSnapshot = snapshot; return }
        guard let data = WatchLink.encode(snapshot) else { return }
        do {
            try session.updateApplicationContext([WatchLink.snapshotKey: data])
        } catch {
            log.error("push snapshot failed: \(error.localizedDescription)")
        }
    }

    // MARK: 落库
    private func handle(_ request: WatchRecordRequest, movedVoiceFileName: String? = nil) {
        guard let context = writeContext else { return }
        let role = FamilyRole(rawValue: request.roleRaw) ?? .mama
        let localId = UUID(uuidString: request.localId)
        do {
            switch request.type {
            case .text:
                try EntryWriter.quickTextEntry(note: request.note ?? "", role: role, in: context,
                                               localId: localId, happenedAt: request.happenedAt)
            case .mood:
                let mood = request.moodRaw.flatMap(Mood.init(rawValue:))
                let note = request.note?.isEmpty == false ? request.note! : (mood.map { "\($0.emoji) \($0.rawValue)" } ?? "记录了一个瞬间")
                try EntryWriter.quickTextEntry(note: note, mood: mood, role: role, in: context,
                                               localId: localId, happenedAt: request.happenedAt)
            case .health:
                let kind = request.healthKindRaw.flatMap(HealthRecordKind.init(rawValue:)) ?? .meal
                try EntryWriter.quickHealthEntry(kind: kind, title: request.healthTitle ?? kind.title,
                                                 role: role, in: context,
                                                 localId: localId, happenedAt: request.happenedAt)
            case .voice:
                try writeVoice(request, fileName: movedVoiceFileName, role: role, in: context)
            }
            NotificationCenter.default.post(name: Self.didRecordNotification, object: nil)
        } catch {
            log.error("watch record write failed: \(error.localizedDescription)")
        }
    }

    private func writeVoice(_ request: WatchRecordRequest, fileName: String?,
                            role: FamilyRole, in context: ModelContext) throws {
        guard let fileName else { return }
        if let localId = UUID(uuidString: request.localId) {
            let d = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == localId })
            if ((try? context.fetchCount(d)) ?? 0) > 0 {
                // 重复投递：删掉刚导入的孤儿音频，避免 App Group 里堆积无引用文件。
                try? FileManager.default.removeItem(at: BubuStorage.mediaDirectory.appendingPathComponent(fileName))
                return
            }
        }
        let entry = Entry(happenedAt: request.happenedAt, authorRole: role.rawValue, note: nil)
        if let localId = UUID(uuidString: request.localId) { entry.id = localId }
        context.insert(entry)
        let voice = VoiceNote(localFileName: fileName, durationSeconds: request.voiceDuration ?? 0,
                              authorRole: role.rawValue, waveformSamples: [])
        voice.entry = entry
        context.insert(voice)
        context.insert(FeedEvent(kind: .voiceAdded, actorRole: role.rawValue,
                                 summary: "从手表录了一段声音",
                                 targetLocalId: entry.id.uuidString, happenedAt: entry.happenedAt))
        try context.save()
    }
}

// MARK: - 概览快照构建（iPhone 侧读库 → 手表展示）
enum WatchSnapshotBuilder {
    @MainActor
    static func make(context: ModelContext, role: FamilyRole) -> WatchSnapshot? {
        guard let profile = try? context.fetch(FetchDescriptor<ChildProfile>()).first else { return nil }
        // 「最近」用 FeedEvent（统一涵盖记录/健康打卡/语音等），这样手表打卡后也能立刻在「最近」看到。
        var feedDescriptor = FetchDescriptor<FeedEvent>(
            sortBy: [SortDescriptor(\.happenedAt, order: .reverse)])
        feedDescriptor.fetchLimit = 6
        let events = (try? context.fetch(feedDescriptor)) ?? []
        let recent = events
            .filter { $0.kind != .entryArchived }
            .prefix(4)
            .map { e in
                WatchRecent(id: e.id.uuidString,
                            dateText: BubuDateFormat.monthDay(e.happenedAt),
                            note: e.summary,
                            moodEmoji: e.kind.emoji)
            }
        let milestones = (try? context.fetch(FetchDescriptor<Milestone>())) ?? []
        let achieved = milestones.filter { $0.isAchieved }.count
        return WatchSnapshot(childName: profile.name, birthday: profile.birthday,
                             roleRaw: role.rawValue,
                             achievedMilestones: achieved, totalMilestones: milestones.count,
                             recent: Array(recent), avatarData: avatarThumbData(profile.avatarMediaFileName),
                             updatedAt: .now)
    }

    /// 布布头像小缩略图（120px，jpeg 0.7，<30KB），供手表概览显示。
    private static func avatarThumbData(_ fileName: String?) -> Data? {
        guard let fileName, !fileName.isEmpty else { return nil }
        let thumb = BubuStorage.thumbnailDirectory.appendingPathComponent(fileName)
        let media = BubuStorage.mediaDirectory.appendingPathComponent(fileName)
        let url = FileManager.default.fileExists(atPath: thumb.path) ? thumb : media
        guard let image = ThumbnailProvider.downsample(url: url, maxPixel: 120) else { return nil }
        return image.jpegData(compressionQuality: 0.7)
    }
}

// MARK: - WCSessionDelegate（回调在 WC 队列，写库统一切回 MainActor）
extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let pending = self.pendingSnapshot { self.pendingSnapshot = nil; self.push(pending) }
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()   // 切换手表后重新激活
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[WatchLink.recordKey] as? Data,
              let request = WatchLink.decode(WatchRecordRequest.self, from: data) else { return }
        Task { @MainActor in self.handle(request) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[WatchLink.recordKey] as? Data,
              let request = WatchLink.decode(WatchRecordRequest.self, from: data) else { return }
        Task { @MainActor in self.handle(request) }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let json = file.metadata?[WatchLink.fileMetaKey] as? String,
              let data = json.data(using: .utf8),
              let request = WatchLink.decode(WatchRecordRequest.self, from: data) else { return }
        // 把语音文件搬进 App Group 媒体目录（在后台队列做完文件搬运，再切回主线程写库）。
        let tempURL = file.fileURL
        let moved = try? MediaStore().importFile(from: tempURL, preferredExtension: "m4a")
        Task { @MainActor in self.handle(request, movedVoiceFileName: moved) }
    }
}
