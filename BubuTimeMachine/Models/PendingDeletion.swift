import Foundation
import SwiftData

// MARK: - 待同步删除队列
/// 离线优先的「删除意图」持久化：本地删除时入队，SyncEngine 每轮先消费队列再推数据，
/// 成功写入远端 tombstone（或远端 404 本就不存在）才出队——断网取消打卡不再于下轮拉取时复活。
/// 任意 PocketBase collection 都走同一队列，merge 侧会先查队列防复活。
@Model
final class PendingDeletion {
    @Attribute(.unique) var id: UUID
    /// PocketBase collection 名，如 "vaccinerecords"。
    var collection: String
    var remoteId: String
    var createdAt: Date

    init(collection: String, remoteId: String) {
        self.id = UUID()
        self.collection = collection
        self.remoteId = remoteId
        self.createdAt = .now
    }

    static func enqueue(collection: String, remoteId: String?, in context: ModelContext) {
        guard let remoteId, !remoteId.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<PendingDeletion>())) ?? []
        guard !existing.contains(where: { $0.collection == collection && $0.remoteId == remoteId }) else { return }
        context.insert(PendingDeletion(collection: collection, remoteId: remoteId))
    }
}
