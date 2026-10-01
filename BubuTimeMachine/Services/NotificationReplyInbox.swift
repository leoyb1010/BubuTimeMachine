import Foundation
import SwiftData

/// A notification response disappears when its callback finishes. Keep its original intent
/// independently of SwiftData until a persistent store has committed and read back both rows.
@MainActor
struct NotificationReplyInbox {
    nonisolated struct Reply: Codable, Equatable, Sendable {
        let version: Int
        let id: UUID
        let note: String
        let role: FamilyRole
        let happenedAt: Date

        init(id: UUID = UUID(), note: String, role: FamilyRole, happenedAt: Date = .now) {
            self.version = 1
            self.id = id
            self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            self.role = role
            self.happenedAt = happenedAt
        }
    }

    enum InboxError: Error {
        case invalidReply
        case intentConflict
        case ephemeralStore
        case entryConflict
        case missingDurableReply
    }

    let directory: URL

    private func file(for reply: Reply) -> URL {
        directory.appendingPathComponent("\(reply.id.uuidString).json")
    }

    /// Called synchronously before the notification callback returns, even if the store is
    /// unavailable. Atomic replacement prevents truncated JSON; protection permits locked-screen
    /// replies after first unlock. Existing intents are never replaced by conflicting content.
    func stage(_ reply: Reply) throws {
        guard reply.version == 1, !reply.note.isEmpty else { throw InboxError.invalidReply }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                  ofItemAtPath: directory.path)
        let destination = file(for: reply)
        if manager.fileExists(atPath: destination.path) {
            guard try JSONDecoder().decode(Reply.self, from: Data(contentsOf: destination)) == reply else {
                throw InboxError.intentConflict
            }
            return
        }
        let data = try JSONEncoder().encode(reply)
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        guard try JSONDecoder().decode(Reply.self, from: Data(contentsOf: destination)) == reply else {
            throw InboxError.intentConflict
        }
    }

    /// Invalid, future-version or unreadable files remain untouched for recovery. A damaged
    /// intent must neither block other replies nor be silently removed as an empty queue.
    func pendingReplies() throws -> [Reply] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return [] }
        return try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let reply = try? JSONDecoder().decode(Reply.self, from: data),
                      reply.version == 1,
                      !reply.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      url.lastPathComponent == "\(reply.id.uuidString).json" else { return nil }
                return reply
            }
            .sorted { $0.happenedAt < $1.happenedAt }
    }

    static func isPersistent(_ container: ModelContainer) -> Bool {
        !container.configurations.isEmpty && container.configurations.allSatisfy { !$0.isStoredInMemoryOnly }
    }

    /// Fault-injection closures are used only by synthetic tests. Every production attempt uses
    /// fresh contexts: failed saves cannot leak into autosave or masquerade as successful dedupe.
    func importReply(
        _ reply: Reply, into container: ModelContainer,
        fetch: @MainActor (ModelContext, UUID) throws -> Entry? = { context, id in
            try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })).first
        },
        save: @MainActor (ModelContext) throws -> Void = { try $0.save() },
        remove: @MainActor (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) throws {
        guard Self.isPersistent(container) else { throw InboxError.ephemeralStore }
        // Refuse an in-memory-only intent or a changed/corrupt original. Deletion below is always
        // tied to the exact staged bytes that this attempt is committing.
        let original = try Data(contentsOf: file(for: reply))
        guard try JSONDecoder().decode(Reply.self, from: original) == reply,
              reply.version == 1, !reply.note.isEmpty else { throw InboxError.intentConflict }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            if let existing = try fetch(context, reply.id) {
                guard Self.matches(existing, reply) else { throw InboxError.entryConflict }
            } else {
                let entry = Entry(happenedAt: reply.happenedAt, authorRole: reply.role.rawValue, note: reply.note)
                entry.id = reply.id
                context.insert(entry)
                context.insert(FeedEvent(kind: .entryCreated, actorRole: reply.role.rawValue,
                                         summary: "记录了：\(reply.note)", targetLocalId: reply.id.uuidString,
                                         happenedAt: reply.happenedAt))
                try save(context)
            }

            let verification = ModelContext(container)
            verification.autosaveEnabled = false
            guard let persisted = try fetch(verification, reply.id), Self.matches(persisted, reply) else {
                throw InboxError.missingDurableReply
            }
            let target = reply.id.uuidString
            let events = try verification.fetch(FetchDescriptor<FeedEvent>(predicate: #Predicate { $0.targetLocalId == target }))
            guard events.contains(where: {
                $0.kind == .entryCreated && $0.actorRole == reply.role.rawValue
                    && $0.summary == "记录了：\(reply.note)" && $0.happenedAt == reply.happenedAt
            }) else { throw InboxError.missingDurableReply }
        } catch {
            context.rollback()
            throw error
        }
        // A crash or deletion failure leaves a replayable UUID, not a second record. Recheck the
        // original before removing it, and never delete a changed intent merely because its ID matched.
        guard try Data(contentsOf: file(for: reply)) == original else { throw InboxError.intentConflict }
        try remove(file(for: reply))
    }

    private static func matches(_ entry: Entry, _ reply: Reply) -> Bool {
        entry.id == reply.id && entry.note == reply.note && entry.authorRole == reply.role.rawValue
            && entry.happenedAt == reply.happenedAt
    }
}
