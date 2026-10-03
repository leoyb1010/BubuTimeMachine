import Foundation
import SwiftData

/// 家庭身份只在独立事务成功后改变；失败不能保存或回滚其它页面的草稿。
@MainActor
enum FamilyMemberMutation {
    struct Draft {
        var name: String
        var relation: String
        var emoji: String
        var colorHex: String

        func apply(to member: FamilyMember) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            member.name = trimmed.isEmpty ? relation : trimmed
            member.relation = relation
            member.avatarEmoji = emoji
            member.themeColorHex = colorHex
            member.syncState = .local
        }
    }

    struct Fallback { let id: UUID; let relation: String }
    enum MutationError: Error { case missingMember, lastMember }

    @discardableResult
    static func save(id: UUID?, newID: UUID = UUID(), draft: Draft, container: ModelContainer,
                     persist: (ModelContext) throws -> Void = { try $0.save() }) throws -> UUID {
        let transaction = ModelContext(container)
        transaction.autosaveEnabled = false
        let member: FamilyMember
        if let id {
            guard let existing = try transaction.fetch(FetchDescriptor<FamilyMember>()).first(where: { $0.id == id }) else {
                throw MutationError.missingMember
            }
            member = existing
        } else {
            if let existing = try transaction.fetch(FetchDescriptor<FamilyMember>()).first(where: { $0.id == newID }) {
                member = existing
            } else {
                member = FamilyMember(name: draft.name, relation: draft.relation)
                member.id = newID
                transaction.insert(member)
            }
        }
        draft.apply(to: member)
        let savedID = member.id
        do { try persist(transaction) } catch { transaction.rollback(); throw error }
        // save() 返回就是提交边界；不能再以可失败的读回把已提交结果报成失败。
        return savedID
    }

    static func delete(id: UUID, container: ModelContainer,
                       persist: (ModelContext) throws -> Void = { try $0.save() }) throws -> Fallback {
        let transaction = ModelContext(container)
        transaction.autosaveEnabled = false
        let members = try transaction.fetch(FetchDescriptor<FamilyMember>(sortBy: [SortDescriptor(\.createdAt)]))
        guard let member = members.first(where: { $0.id == id }) else { throw MutationError.missingMember }
        guard let fallback = members.first(where: { $0.id != id }) else { throw MutationError.lastMember }
        let result = Fallback(id: fallback.id, relation: fallback.relation)
        let remoteID = member.remoteId
        PendingDeletion.enqueue(collection: "members", remoteId: remoteID, in: transaction)
        transaction.delete(member)
        do { try persist(transaction) } catch { transaction.rollback(); throw error }
        return result
    }
}

#if DEBUG
/// 不可变启动参数 + 进程级一次故障，仅允许完整内存测试容器。
@MainActor
enum MemberMutationUITestFault {
    static var injected = Set<String>()
    static func injectOnce(_ operation: String, in container: ModelContainer) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-uitest-in-memory"),
              arguments.contains("-uitest-member-fail-" + operation),
              !container.configurations.isEmpty,
              container.configurations.allSatisfy({ $0.isStoredInMemoryOnly }),
              injected.insert(operation).inserted else { return }
        throw CocoaError(.fileWriteOutOfSpace)
    }
}
#endif
