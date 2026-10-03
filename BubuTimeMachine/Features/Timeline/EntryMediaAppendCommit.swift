import SwiftData
import Foundation

@MainActor
enum EntryMediaAppendCommit {
    enum CommitError: LocalizedError {
        case unavailableEntry
        var errorDescription: String? { "这条记录已移除或归档，无法追加素材。" }
    }

    static func save(_ media: [Media], to entryID: UUID, in uiContext: ModelContext,
                     persist: (ModelContext) throws -> Void = { try $0.save() },
                     removeFiles: (String?, String?) -> Void) throws {
        guard !media.isEmpty else { return }
        let context = ModelContext(uiContext.container)
        context.autosaveEnabled = false
        let files = media.map { ($0.localFileName, $0.thumbnailFileName) }
        var committed = false
        defer {
            if !committed {
                context.rollback()
                for (file, thumbnail) in files { removeFiles(file, thumbnail) }
            }
        }
        try Task.checkCancellation()
        guard let entry = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryID })).first,
              !entry.isArchived else { throw CommitError.unavailableEntry }
        for item in media { item.entry = entry; context.insert(item) }
        entry.editedAt = .now
        entry.syncState = .local
        try persist(context)
        committed = true
    }
}
