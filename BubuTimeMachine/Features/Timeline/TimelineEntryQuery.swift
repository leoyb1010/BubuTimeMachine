import Foundation
import SwiftData

@MainActor
enum TimelineEntryQuery {
    static func pendingRemoteCount(references: [(entryID: UUID, mediaID: String)], known: [Entry]) -> Int {
        let byID = Dictionary(uniqueKeysWithValues: known.map { ($0.id, $0) })
        var pending: Set<UUID> = []
        for reference in references {
            guard let entry = byID[reference.entryID] else { pending.insert(reference.entryID); continue }
            if !entry.isArchived, !reference.mediaID.isEmpty,
               !entry.media.contains(where: { $0.remoteId == reference.mediaID }) { pending.insert(entry.id) }
        }
        return pending.count
    }

    static func descriptor(filters: TimelineFilters, query: String, sort: TimelineSortMode,
                           limit: Int, calendar: Calendar = .current,
                           entryIDs: [UUID]? = nil) -> FetchDescriptor<Entry> {
        let (start, end) = filters.dateBounds(calendar: calendar)
        let kind = filters.kind.rawValue
        let marker = TimelineFilters.automaticMarker
        let prefix = marker + "\n"
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let restrictIDs = entryIDs != nil
        let ids = entryIDs ?? []
        let dates = #Predicate<Entry> { !$0.isArchived && $0.happenedAt >= start && $0.happenedAt < end }
        let origin: Predicate<Entry>
        switch filters.source {
        case .all: origin = #Predicate { _ in true }
        case .automatic: origin = #Predicate { $0.note == marker || ($0.note?.starts(with: prefix) ?? false) }
        case .family: origin = #Predicate { $0.note != marker && !($0.note?.starts(with: prefix) ?? false) }
        }
        let mediaType: Predicate<Entry>
        if filters.kind == .all { mediaType = #Predicate { _ in true } }
        else if filters.kind == .audio {
            mediaType = #Predicate { entry in
                !entry.voiceNotes.isEmpty || entry.media.contains { media in
                    media.typeRaw == "audio" && (media.resourceRoleRaw == nil || media.resourceRoleRaw == "" || media.resourceRoleRaw == "display")
                }
            }
        } else {
            mediaType = #Predicate { entry in
                entry.media.contains { media in
                    media.typeRaw == kind && (media.resourceRoleRaw == nil || media.resourceRoleRaw == "" || media.resourceRoleRaw == "display")
                }
            }
        }
        let content = #Predicate<Entry> { entry in
            (entry.note?.localizedStandardContains(text) ?? false)
                || (entry.title?.localizedStandardContains(text) ?? false)
                || (entry.firstPersonNote?.localizedStandardContains(text) ?? false)
        }
        let labels = #Predicate<Entry> { entry in
            (entry.locationName?.localizedStandardContains(text) ?? false)
                || entry.authorRole.localizedStandardContains(text)
                || (entry.moodRaw?.localizedStandardContains(text) ?? false)
                || (entry.firstTime?.what.localizedStandardContains(text) ?? false)
        }
        let spoken = #Predicate<Entry> { entry in
            entry.voiceNotes.contains { $0.transcript?.localizedStandardContains(text) ?? false }
        }
        let words: Predicate<Entry> = text.isEmpty ? #Predicate { _ in true }
            : #Predicate { content.evaluate($0) || labels.evaluate($0) || spoken.evaluate($0) }
        let predicate = #Predicate<Entry> { entry in
            dates.evaluate(entry) && origin.evaluate(entry) && mediaType.evaluate(entry)
                && words.evaluate(entry) && (!restrictIDs || ids.contains(entry.id))
        }
        let order: SortOrder = sort.ascending ? .forward : .reverse
        var descriptor = FetchDescriptor<Entry>(predicate: predicate, sortBy: sort == .recorded
            ? [SortDescriptor(\Entry.createdAt, order: .reverse)]
            : [SortDescriptor(\Entry.happenedAt, order: order)])
        descriptor.fetchLimit = max(1, limit)
        return descriptor
    }
}
