import Foundation
import SwiftData

@MainActor
enum DiaryRewriteMutation {
    enum MutationError: Error, Equatable { case missingEntry, archivedEntry }

    /// Commit only the chosen diary text. A failure leaves every UI draft alone.
    static func save(entryID: UUID, text: String, container: ModelContainer,
                     persist: (ModelContext) throws -> Void = { try $0.save() }) throws -> Date {
        let transaction = ModelContext(container)
        transaction.autosaveEnabled = false
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryID })
        descriptor.fetchLimit = 1
        guard let entry = try transaction.fetch(descriptor).first else { throw MutationError.missingEntry }
        guard !entry.isArchived else { throw MutationError.archivedEntry }
        let timestamp = Date.now
        entry.firstPersonNote = text
        entry.editedAt = timestamp
        entry.syncState = .local
        do { try persist(transaction) } catch { transaction.rollback(); throw error }
        return timestamp
    }
}

#if DEBUG
@MainActor
enum DiaryRewriteUITestFault {
    private static var injected = false
    static func injectOnce(in container: ModelContainer) throws {
        let args = ProcessInfo.processInfo.arguments
        guard !injected, args.contains("-uitest-in-memory"), args.contains("-uitest-diary-fail-save"),
              !container.configurations.isEmpty,
              container.configurations.allSatisfy({ $0.isStoredInMemoryOnly }) else { return }
        injected = true
        throw CocoaError(.fileWriteOutOfSpace)
    }
}
#endif
