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
            b.note = "Uncommitted B edit"
            #expect(throws: Fault.self) {
                try DiaryRewriteMutation.save(entryID: aID, text: "A rewrite", container: store) { _ in throw Fault.rejected }
            }
            #expect(a.firstPersonNote == nil && b.firstPersonNote == nil)
            #expect(b.note == "Uncommitted B edit" && main.hasChanges)
            _ = try DiaryRewriteMutation.save(entryID: aID, text: "A rewrite", container: store)
            _ = try DiaryRewriteMutation.save(entryID: aID, text: "A rewrite", container: store)
            #expect(b.note == "Uncommitted B edit" && main.hasChanges)
            #expect(throws: DiaryRewriteMutation.MutationError.self) {
                try DiaryRewriteMutation.save(entryID: UUID(), text: "missing", container: store)
            }
        }
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let rows = try reopened.mainContext.fetch(FetchDescriptor<Entry>())
        #expect(rows.count == 2)
        #expect(rows.first { $0.id == aID }?.firstPersonNote == "A rewrite")
        #expect(rows.first { $0.id == bID }?.firstPersonNote == nil)
        #expect(rows.first { $0.id == bID }?.note == "Synthetic B")
    }
}
