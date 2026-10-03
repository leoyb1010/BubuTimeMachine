import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

@MainActor
struct DiaryRewriteMutationTests {
    private enum Fault: Error { case rejected }

    @Test("磁盘改写保存失败不污染其他草稿；重试与重开仅修改指定记录")
    func diskFailureRetryAndReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("diary.store")
        let schema = SharedModelContainer.schema
        let aID: UUID, bID: UUID
        do {
            let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let main = store.mainContext; main.autosaveEnabled = false
            let a = Entry(authorRole: "妈妈", note: "Synthetic A")
            let b = Entry(authorRole: "爸爸", note: "Synthetic B")
            aID = a.id; bID = b.id
            main.insert(a); main.insert(b); try main.save()
            a.note = "Uncommitted A edit"
            b.note = "Uncommitted B edit"
            #expect(throws: Fault.self) {
                try DiaryRewriteMutation.save(entryID: aID, text: "A rewrite", container: store) { _ in throw Fault.rejected }
            }
            #expect(a.firstPersonNote == nil && b.firstPersonNote == nil)
            #expect(a.note == "Uncommitted A edit")
            #expect(b.note == "Uncommitted B edit" && main.hasChanges)
            _ = try DiaryRewriteMutation.save(entryID: aID, text: "A rewrite", container: store)
            _ = try DiaryRewriteMutation.save(entryID: aID, text: "A rewrite", container: store)
            #expect(a.note == "Uncommitted A edit")
            #expect(b.note == "Uncommitted B edit" && main.hasChanges)
            #expect(throws: DiaryRewriteMutation.MutationError.self) {
                try DiaryRewriteMutation.save(entryID: UUID(), text: "missing", container: store)
            }
        }
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let rows = try reopened.mainContext.fetch(FetchDescriptor<Entry>())
        #expect(rows.count == 2)
        #expect(rows.first { $0.id == aID }?.firstPersonNote == "A rewrite")
        #expect(rows.first { $0.id == aID }?.note == "Synthetic A")
        #expect(rows.first { $0.id == bID }?.firstPersonNote == nil)
        #expect(rows.first { $0.id == bID }?.note == "Synthetic B")
    }
    @Test("归档或已删除的来源不能被改写保存，也不会误改其他记录")
    func removedOriginCannotRedirectSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = SharedModelContainer.schema
        let store = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, url: directory.appendingPathComponent("archived.store"))])
        let entry = Entry(authorRole: "妈妈", note: "Synthetic archived source")
        let other = Entry(authorRole: "爸爸", note: "Synthetic other source")
        entry.isArchived = true
        store.mainContext.insert(entry); store.mainContext.insert(other); try store.mainContext.save()
        let id = entry.id
        #expect(throws: DiaryRewriteMutation.MutationError.archivedEntry) {
            try DiaryRewriteMutation.save(entryID: id, text: "must not save", container: store)
        }
        store.mainContext.delete(entry); try store.mainContext.save()
        #expect(throws: DiaryRewriteMutation.MutationError.missingEntry) {
            try DiaryRewriteMutation.save(entryID: id, text: "must not save", container: store)
        }
        let rows = try ModelContext(store).fetch(FetchDescriptor<Entry>())
        #expect(rows.count == 1 && rows.first?.id == other.id)
        #expect(rows.first?.firstPersonNote == nil)
    }

}
