import Foundation
import SwiftData

/// 一份尚未提交的信。密文已写入新文件，但在数据库提交前仍由草稿持有。
@MainActor
enum CapsuleDraftCommit {
    struct Identity: Equatable {
        let id: UUID
        let blobName: String?
        let unlockAt: Date
        let cryptoVersion: Int?
        init(_ capsule: TimeCapsule) {
            id = capsule.id
            blobName = capsule.encryptedBlobFileName
            unlockAt = capsule.unlockAt
            cryptoVersion = capsule.cryptoVersion
        }
    }
    enum CommitError: LocalizedError {
        case changed, notCommitted
        var errorDescription: String? {
            switch self {
            case .changed: return "这封信已经更新或移除，请重新打开后再修改。"
            case .notCommitted: return "这封信尚未保存，请保留草稿后重试。"
            }
        }
    }
    struct Draft {
        var id: UUID
        var title: String
        var fromRole: String
        var emoji: String
        var unlockAt: Date
        var blobName: String?
        var rewritesPayload: Bool
    }

    static func save(_ draft: Draft, editing: TimeCapsule?, in uiContext: ModelContext,
                     expected: Identity? = nil,
                     persist: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let context = ModelContext(uiContext.container)
        context.autosaveEnabled = false
        let id = draft.id
        let query = FetchDescriptor<TimeCapsule>(predicate: #Predicate { $0.id == id })
        let capsule: TimeCapsule
        if let editing {
            guard let stored = try context.fetch(query).first,
                  Identity(stored) == (expected ?? Identity(editing)) else { throw CommitError.changed }
            capsule = stored
        } else {
            guard try context.fetchCount(query) == 0 else { throw CommitError.changed }
            capsule = TimeCapsule(title: draft.title, fromRole: draft.fromRole, unlockAt: draft.unlockAt)
            context.insert(capsule)
        }
        capsule.id = draft.id
        capsule.title = draft.title
        capsule.coverEmoji = draft.emoji
        if draft.rewritesPayload {
            capsule.unlockAt = draft.unlockAt
            capsule.encryptedBlobFileName = draft.blobName
            capsule.cryptoVersion = 3
            capsule.isLocked = draft.unlockAt > .now
        }
        capsule.syncState = .local
        do {
            try persist(context)
            guard try isCommitted(draft, in: uiContext.container) else { throw CommitError.notCommitted }
        } catch {
            context.rollback()
            // A callback can report a post-commit failure. Never tell the view to
            // delete a blob that has already become the persisted letter.
            if (try? isCommitted(draft, in: uiContext.container)) == true { return }
            throw error
        }
    }

    private static func isCommitted(_ draft: Draft, in container: ModelContainer) throws -> Bool {
        let id = draft.id
        let context = ModelContext(container)
        guard let saved = try context.fetch(FetchDescriptor<TimeCapsule>(predicate: #Predicate { $0.id == id })).first,
              saved.title == draft.title, saved.coverEmoji == draft.emoji else { return false }
        return !draft.rewritesPayload || (saved.encryptedBlobFileName == draft.blobName &&
            saved.cryptoVersion == 3 && saved.unlockAt == draft.unlockAt)
    }
}
