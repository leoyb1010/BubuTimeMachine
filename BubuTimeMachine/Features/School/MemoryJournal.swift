import Foundation
import SwiftData
import os

/// Ownership follows the composer state lifetime, not visibility behind a system picker.
/// Releasing a covered view's lease would let another window delete its imported files.
nonisolated final class JournalDraftLease: Sendable {
    private static let owners = OSAllocatedUnfairLock(initialState: Set<MemoryJournalKind>())
    private let kind: MemoryJournalKind
    private init(kind: MemoryJournalKind) { self.kind = kind }
    static func acquire(_ kind: MemoryJournalKind) -> JournalDraftLease? {
        owners.withLock { active in
            guard active.insert(kind).inserted else { return nil }
            return JournalDraftLease(kind: kind)
        }
    }
    deinit { Self.owners.withLock { _ = $0.remove(kind) } }
}

/// Readable markers keep new journals compatible with existing sync, export and old clients.
nonisolated enum MemoryJournalKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case school, saying
    var id: String { rawValue }
    var marker: String { self == .school ? "【幼儿园】" : "【布布说】" }
    var title: String { self == .school ? "幼儿园" : "布布说" }
    var symbol: String { self == .school ? "backpack.fill" : "quote.bubble.fill" }
    func contains(_ note: String?) -> Bool {
        guard let note else { return false }
        return note == marker || note.hasPrefix(marker + "\n")
    }
    func body(_ note: String?) -> String {
        guard let note else { return "" }
        return contains(note) ? String(note.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines) : note
    }
}

nonisolated struct SchoolReportSuggestion: Equatable, Sendable {
    var meal = ""
    var sleep = ""
    /// Conservative extraction: preserve original phrases; no guessed calories, durations or dates.
    static func parse(_ text: String) -> Self {
        let lines = text.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return Self(
            meal: lines.filter { line in ["早餐", "午餐", "晚餐", "午饭", "吃饭", "餐食", "加餐"].contains { line.contains($0) } }.joined(separator: "\n"),
            sleep: lines.filter { line in ["午睡", "睡眠", "入睡", "起床"].contains { line.contains($0) } }.joined(separator: "\n"))
    }
}

nonisolated struct MemoryJournalDraft: Sendable, Codable, Equatable {
    let id: UUID
    let kind: MemoryJournalKind
    var date: Date
    var words = ""
    var context = ""
    var meal = ""
    var sleep = ""
    var source = ""
    var schoolReport: SchoolDailyReport?

    var hasText: Bool {
        schoolReport?.hasContent == true || [words, context, meal, sleep, source].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var note: String {
        var parts = [kind.marker]
        func append(_ label: String, _ value: String) {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { parts.append(label + value) }
        }
        append(kind == .saying ? "她说：" : "今天的小故事：", words)
        append("当时：", context)
        append("餐食：", meal)
        append("午睡：", sleep)
        if let schoolReport, !schoolReport.noteBlock.isEmpty { parts.append(schoolReport.noteBlock) }
        append("老师原文 / OCR 候选（可能有误）：\n", source)
        return parts.joined(separator: "\n\n")
    }
}

nonisolated struct JournalMediaFile: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let thumbnail: String?
    let hash: String
    let isVideo: Bool
    var isSchoolReport: Bool?
}

nonisolated struct JournalDraftSnapshot: Codable, Equatable, Sendable {
    struct Voice: Codable, Equatable, Sendable {
        let fileName: String
        let duration: Double
        let waveform: [Float]
    }
    let draft: MemoryJournalDraft
    let files: [JournalMediaFile]
    let voice: Voice?
}

nonisolated enum JournalDraftError: LocalizedError {
    case tooMuchText
    case reportNotConfirmed
    var errorDescription: String? {
        switch self {
        case .tooMuchText: "这一笔的文字太多，请拆成几天记录。原草稿没有被覆盖。"
        case .reportNotConfirmed: "请先对照原表核对日期与亲子桥内容，再收好。"
        }
    }
}

nonisolated enum JournalDraftStore {
    #if DEBUG && targetEnvironment(simulator)
    private static let testSession = UUID().uuidString
    #endif
    static func file(for kind: MemoryJournalKind) -> URL {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-uitest-in-memory") {
            return FileManager.default.temporaryDirectory.appendingPathComponent("JournalDrafts-\(testSession)/\(kind.rawValue).json")
        }
        #endif
        return BubuStorage.containerURL.appendingPathComponent("Documents/JournalDrafts/\(kind.rawValue).json")
    }
    static func save(_ snapshot: JournalDraftSnapshot, to url: URL) throws {
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 2_000_000, snapshot.draft.note.utf8.count <= 100_000 else { throw JournalDraftError.tooMuchText }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func load(from url: URL) throws -> JournalDraftSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_000_000 else {
            throw CocoaError(.fileReadTooLarge)
        }
        let value = try JSONDecoder().decode(JournalDraftSnapshot.self, from: Data(contentsOf: url))
        let names = value.files.flatMap { [$0.fileName, $0.thumbnail].compactMap { $0 } } + [value.voice?.fileName].compactMap { $0 }
        guard value.files.count <= 50,
              names.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("\\") && $0 != ".." && $0 != "." }),
              value.voice.map({ $0.duration.isFinite && $0.duration >= 0 && $0.waveform.count <= 1000 }) ?? true else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value
    }
    static func remove(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

enum MemoryJournalWriter {
    /// Dedicated context keeps rollback away from unrelated edits. Files remain owned by the draft
    /// until this transaction succeeds, so a disk failure can be retried without losing the recording.
    static func save(_ draft: MemoryJournalDraft, files: [JournalMediaFile],
                     voice: (fileName: String, duration: Double, waveform: [Float])?,
                     role: FamilyRole, container: ModelContainer) throws -> UUID {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let id = draft.id
        if try context.fetchCount(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })) > 0 {
            return id // Archived entries also count: never resurrect on repeated delivery.
        }
        guard draft.hasText || !files.isEmpty || voice != nil else { throw EntryWriterError.emptyNote }
        guard draft.note.utf8.count <= 100_000 else { throw JournalDraftError.tooMuchText }
        if let report = draft.schoolReport, !report.confirmed { throw JournalDraftError.reportNotConfirmed }
        let entry = Entry(happenedAt: draft.date, authorRole: role.rawValue, note: draft.note)
        entry.id = id
        entry.title = draft.kind == .school ? "幼儿园的一天" : "留住这句童言"
        context.insert(entry)
        var hashes = Set<String>()
        for file in files where hashes.insert(file.hash).inserted {
            let media = Media(type: file.isVideo ? .video : .photo, localFileName: file.fileName)
            media.contentHash = file.hash
            media.thumbnailFileName = file.thumbnail
            if file.isSchoolReport == true { media.aiTags = ["亲子桥原表"] }
            media.entry = entry
            context.insert(media)
        }
        if let voice {
            let note = VoiceNote(localFileName: voice.fileName, durationSeconds: voice.duration,
                                 authorRole: role.rawValue, waveformSamples: voice.waveform)
            note.transcript = draft.words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.words
            note.entry = entry
            context.insert(note)
        }
        context.insert(FeedEvent(kind: .entryCreated, actorRole: role.rawValue,
                                 summary: draft.kind == .school ? "收好了一段幼儿园时光" : "留住了一句布布的话",
                                 targetLocalId: id.uuidString, happenedAt: draft.date))
        do { try context.save() } catch { context.rollback(); throw error }
        return id
    }
}
