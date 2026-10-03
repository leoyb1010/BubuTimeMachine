import Foundation
import SwiftData

/// User-requested deletion only. Keep database intent and file ownership separate:
/// a failed/ineffective save cannot authorize removing the only local bytes.
@MainActor
enum FileBackedRecordDeletion {
    enum Kind: String { case media, voice, capsule }
    enum DeletionError: Error { case ephemeralStore, missingRecord, changedRecord, uncommittedDeletion }

    struct Request: Equatable {
        let kind: Kind
        let id: UUID
        let remoteID: String?
        let fileName: String?
        let thumbnail: String?
        let parentID: UUID?

        init(_ value: Media) {
            kind = .media; id = value.id; remoteID = value.remoteId
            fileName = value.localFileName; thumbnail = value.thumbnailFileName; parentID = value.entry?.id
        }
        init(_ value: VoiceNote) {
            kind = .voice; id = value.id; remoteID = value.remoteId
            fileName = value.localFileName; thumbnail = nil; parentID = value.entry?.id
        }
        init(_ value: TimeCapsule) {
            kind = .capsule; id = value.id; remoteID = value.remoteId
            fileName = value.encryptedBlobFileName; thumbnail = nil; parentID = nil
        }
        var collection: String {
            switch kind { case .media: "media"; case .voice: "voicenotes"; case .capsule: "timecapsules" }
        }
    }

    static func delete(_ request: Request, from uiContext: ModelContext,
                       save: @MainActor (ModelContext) throws -> Void = { try $0.save() },
                       removeFiles: (String?, String?) -> Void) throws {
        let container = uiContext.container
        // Recovery-mode/in-memory rows are not authority to destroy persistent files.
        guard !container.configurations.isEmpty,
              container.configurations.allSatisfy({ !$0.isStoredInMemoryOnly }) else {
            throw DeletionError.ephemeralStore
        }
        // Do not discard an unsaved edit on the exact object being deleted. A
        // separate context cannot safely settle that editor's pending update.
        let dirtyTarget = uiContext.changedModelsArray.contains { model in
            switch request.kind {
            case .media: return (model as? Media)?.id == request.id
            case .voice: return (model as? VoiceNote)?.id == request.id
            case .capsule: return (model as? TimeCapsule)?.id == request.id
            }
        }
        guard !dirtyTarget else { throw DeletionError.changedRecord }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let id = request.id
        do {
            var parent: Entry?
            switch request.kind {
            case .media:
                guard let value = try context.fetch(FetchDescriptor<Media>(predicate: #Predicate { $0.id == id })).first else {
                    throw DeletionError.missingRecord
                }
                guard Request(value) == request else { throw DeletionError.changedRecord }
                parent = value.entry
                context.delete(value)
            case .voice:
                guard let value = try context.fetch(FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.id == id })).first else {
                    throw DeletionError.missingRecord
                }
                guard Request(value) == request else { throw DeletionError.changedRecord }
                parent = value.entry
                context.delete(value)
            case .capsule:
                guard let value = try context.fetch(FetchDescriptor<TimeCapsule>(predicate: #Predicate { $0.id == id })).first else {
                    throw DeletionError.missingRecord
                }
                guard Request(value) == request else { throw DeletionError.changedRecord }
                context.delete(value)
            }
            if let parent { parent.editedAt = .now; parent.syncState = .local }
            let remoteID = request.remoteID ?? ""
            let collection = request.collection
            if !remoteID.isEmpty {
                let pending = FetchDescriptor<PendingDeletion>(predicate: #Predicate {
                    $0.collection == collection && $0.remoteId == remoteID
                })
                if try context.fetchCount(pending) == 0 {
                    context.insert(PendingDeletion(collection: collection, remoteId: remoteID))
                }
            }
            try save(context)
            let verification = ModelContext(container)
            verification.autosaveEnabled = false
            guard try !exists(request, in: verification) else { throw DeletionError.uncommittedDeletion }
            if !remoteID.isEmpty {
                let pending = FetchDescriptor<PendingDeletion>(predicate: #Predicate {
                    $0.collection == collection && $0.remoteId == remoteID
                })
                guard try verification.fetchCount(pending) > 0 else { throw DeletionError.uncommittedDeletion }
            }
            // A different saved record or an unrelated unsaved UI draft can still own
            // the same file. Never free shared bytes merely because one owner was removed.
            var media = request.fileName
            var thumbnail = request.thumbnail
            for reader in [verification, uiContext] {
                if let name = media, try referencesMedia(name, excluding: request, in: reader) { media = nil }
                if let name = thumbnail, try referencesThumbnail(name, excluding: request, in: reader) { thumbnail = nil }
            }
            if media != nil || thumbnail != nil { removeFiles(media, thumbnail) }
        } catch {
            context.rollback() // Only this dedicated context, never the UI's draft context.
            throw error
        }
    }

    private static func exists(_ request: Request, in context: ModelContext) throws -> Bool {
        let id = request.id
        switch request.kind {
        case .media: return try context.fetchCount(FetchDescriptor<Media>(predicate: #Predicate { $0.id == id })) > 0
        case .voice: return try context.fetchCount(FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.id == id })) > 0
        case .capsule: return try context.fetchCount(FetchDescriptor<TimeCapsule>(predicate: #Predicate { $0.id == id })) > 0
        }
    }

    private static func referencesThumbnail(_ name: String, excluding request: Request, in context: ModelContext) throws -> Bool {
        try context.fetch(FetchDescriptor<Media>(predicate: #Predicate { $0.thumbnailFileName == name }))
            .contains { request.kind != .media || $0.id != request.id }
    }

    private static func referencesMedia(_ name: String, excluding request: Request, in context: ModelContext) throws -> Bool {
        if try context.fetch(FetchDescriptor<Media>(predicate: #Predicate { $0.localFileName == name }))
            .contains(where: { request.kind != .media || $0.id != request.id }) { return true }
        if try context.fetch(FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.localFileName == name }))
            .contains(where: { request.kind != .voice || $0.id != request.id }) { return true }
        if try context.fetch(FetchDescriptor<TimeCapsule>(predicate: #Predicate { $0.encryptedBlobFileName == name }))
            .contains(where: { request.kind != .capsule || $0.id != request.id }) { return true }
        if try context.fetchCount(FetchDescriptor<VoiceMemo>(predicate: #Predicate { $0.localFileName == name })) > 0 { return true }
        if try context.fetchCount(FetchDescriptor<Comment>(predicate: #Predicate { $0.voiceFileName == name })) > 0 { return true }
        return try context.fetchCount(FetchDescriptor<ChildProfile>(predicate: #Predicate {
            $0.avatarMediaFileName == name || $0.heroBackgroundFileName == name
        })) > 0
    }
}
