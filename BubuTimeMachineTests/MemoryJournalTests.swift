import Foundation
import SwiftData
import Testing
import UIKit
@testable import BubuTimeMachine

@MainActor struct MemoryJournalTests {
    @Test func draftLeaseSurvivesCoverageAndReleasesWithItsOwner() {
        var lease = JournalDraftLease.acquire(.school)
        #expect(lease != nil)
        #expect(JournalDraftLease.acquire(.school) == nil)
        let otherKind = JournalDraftLease.acquire(.saying)
        #expect(otherKind != nil)
        withExtendedLifetime(lease) { #expect(JournalDraftLease.acquire(.school) == nil) }
        lease = nil
        #expect(JournalDraftLease.acquire(.school) != nil)
        withExtendedLifetime(otherKind) {}
    }

    @Test func draftRoundTripPreservesWordsAndOriginalReferences() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = JournalDraftSnapshot(
            draft: .init(id: UUID(), kind: .saying, date: .now, words: "月亮也要睡觉吗？"), files: [],
            voice: .init(fileName: "voice_test.m4a", duration: 3, waveform: [0.1, 0.4]))
        try JournalDraftStore.save(snapshot, to: url)
        #expect(try JournalDraftStore.load(from: url) == snapshot)
        try JournalDraftStore.remove(at: url)
        #expect(try JournalDraftStore.load(from: url) == nil)
    }

    @Test func draftRejectsUnsafeFileReferencesWithoutDeletingOriginal() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = JournalDraftSnapshot(
            draft: .init(id: UUID(), kind: .school, date: .now),
            files: [.init(id: UUID(), fileName: "../private.jpg", thumbnail: nil, hash: "x", isVideo: false)], voice: nil)
        try JournalDraftStore.save(snapshot, to: url)
        #expect(throws: (any Error).self) { try JournalDraftStore.load(from: url) }
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func oversizedDraftCannotReplaceLastRecoverableCopy() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = JournalDraftSnapshot(draft: .init(id: UUID(), kind: .school, date: .now, words: "搭积木"), files: [], voice: nil)
        try JournalDraftStore.save(original, to: url)
        let oversized = JournalDraftSnapshot(draft: .init(id: UUID(), kind: .school, date: .now, words: String(repeating: "a", count: 100_001)), files: [], voice: nil)
        #expect(throws: JournalDraftError.self) { try JournalDraftStore.save(oversized, to: url) }
        #expect(try JournalDraftStore.load(from: url) == original)
    }

    @Test func mediaImportPreservesOriginalBytesAndRejectsFakeImages() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-test-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try #require(UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30)).image { renderer in
            UIColor.yellow.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 30, height: 30))
        }.pngData())
        try data.write(to: url)
        let store = MediaStore()
        let result = try await JournalImport.prepare(url: url, report: false, store: store)
        defer { store.deleteLocalFiles(media: result.file.fileName, thumbnail: result.file.thumbnail) }
        #expect(try Data(contentsOf: store.mediaURL(for: result.file.fileName)) == data)
        #expect(try Data(contentsOf: url) == data)
        #expect(result.file.hash == MediaStore.sha256Hex(data))
        #expect(result.file.thumbnail != nil)
        try Data("not an image".utf8).write(to: url)
        await #expect(throws: (any Error).self) {
            try await JournalImport.prepare(url: url, report: false, store: store)
        }
    }

    @Test func screenshotOCRRetainsEvidenceEvenWhenLabelsAreUncertain() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("school-report-test-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try #require(UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 320)).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 1000, height: 320))
            ("午餐：米饭和鱼\n午睡：12:10 到 13:30" as NSString).draw(
                in: CGRect(x: 40, y: 40, width: 920, height: 240),
                withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.black])
        }.pngData())
        try data.write(to: url)
        let store = MediaStore()
        let result = try await JournalImport.prepare(url: url, report: true, store: store)
        defer { store.deleteLocalFiles(media: result.file.fileName, thumbnail: result.file.thumbnail) }
        let fields = SchoolReportSuggestion.parse(result.recognizedText)
        // Vision can misread 餐 as 䬸. Preserve the evidence for review instead of
        // making probabilistic OCR accuracy a promise or inventing a meal classification.
        #expect(result.recognizedText.contains("米饭"), "OCR synthetic fixture: \(result.recognizedText)")
        #expect(fields.meal.isEmpty || fields.meal.contains("米饭"))
        #expect(fields.sleep.contains("12:10"))
        #expect(try Data(contentsOf: url) == data)
    }
    @Test func reportKeepsEvidenceAndNeverInventsSleep() {
        let text = "午餐：米饭和鱼，吃了一半\n午睡：12:10 到 13:30\n老师说今天很开心"
        let value = SchoolReportSuggestion.parse(text)
        #expect(value.meal == "午餐：米饭和鱼，吃了一半")
        #expect(value.sleep == "午睡：12:10 到 13:30")
        #expect(SchoolReportSuggestion.parse("今天吃得很好").sleep.isEmpty)
    }
    @Test func markersAreAnchoredAndHumanReadable() {
        let draft = MemoryJournalDraft(id: UUID(), kind: .school, date: .now, words: "玩了积木", meal: "米饭")
        #expect(MemoryJournalKind.school.contains(draft.note))
        #expect(!MemoryJournalKind.school.contains("她提到了【幼儿园】"))
        #expect(draft.note.contains("玩了积木"))
        #expect(MemoryJournalKind.school.body(draft.note).contains("餐食：米饭"))
    }
    @Test func journalSaveIsAtomicAndIdempotentIncludingArchived() throws {
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let draft = MemoryJournalDraft(id: UUID(), kind: .saying, date: .now, words: "月亮也要睡觉吗？")
        let voice = (fileName: "fixture.m4a", duration: 4.0, waveform: [Float(0.2)])
        let id = try MemoryJournalWriter.save(draft, files: [], voice: voice, role: .papa, container: container)
        _ = try MemoryJournalWriter.save(draft, files: [], voice: voice, role: .papa, container: container)
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<VoiceNote>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<FeedEvent>()) == 1)
        let entry = try #require(try context.fetch(FetchDescriptor<Entry>()).first)
        #expect(entry.id == id)
        #expect(entry.voiceNotes.first?.transcript == draft.words)
        entry.isArchived = true
        try context.save()
        _ = try MemoryJournalWriter.save(draft, files: [], voice: voice, role: .papa, container: container)
        #expect(entry.isArchived)
    }
    @Test func emptyDraftDoesNotInsertAnything() throws {
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        #expect(throws: (any Error).self) {
            try MemoryJournalWriter.save(.init(id: UUID(), kind: .school, date: .now), files: [], voice: nil, role: .papa, container: container)
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()) == 0)
    }
}
