import Foundation
import SwiftData

/// 同步游标与业务资料共用一个 store。数据库没有提交成功，进度就不能前进。
@Model
final class SyncCheckpoint {
    @Attribute(.unique) var key: String
    var serverUpdatedAt: Date
    var generation: String

    init(key: String, updated: Date, generation: String) {
        self.key = key
        self.serverUpdatedAt = updated
        self.generation = generation
    }

    @MainActor
    static func read(key: String, generation: String, in context: ModelContext) throws -> Date? {
        let query = FetchDescriptor<SyncCheckpoint>(predicate: #Predicate { $0.key == key })
        guard let checkpoint = try context.fetch(query).first,
              checkpoint.generation == generation else { return nil }
        return checkpoint.serverUpdatedAt
    }

    @MainActor
    static func commit(key: String, generation: String, updated: Date, in context: ModelContext,
                       saving: () throws -> Void) throws {
        let query = FetchDescriptor<SyncCheckpoint>(predicate: #Predicate { $0.key == key })
        let existing = try context.fetch(query).first
        let oldDate = existing?.serverUpdatedAt
        let oldGeneration = existing?.generation
        let item = existing ?? SyncCheckpoint(key: key, updated: updated, generation: generation)
        if existing == nil { context.insert(item) }
        item.serverUpdatedAt = oldGeneration == generation ? max(oldDate ?? updated, updated) : updated
        item.generation = generation
        do {
            try saving()
        } catch {
            // 不 rollback 整个主上下文，避免抹掉用户尚未保存的编辑；只撤回本次进度。
            if let oldDate, let oldGeneration {
                item.serverUpdatedAt = oldDate
                item.generation = oldGeneration
            } else {
                context.delete(item)
            }
            throw error
        }
    }
}
