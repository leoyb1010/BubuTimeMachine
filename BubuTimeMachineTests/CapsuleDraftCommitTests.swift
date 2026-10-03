import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

@MainActor
struct CapsuleDraftCommitTests {
    private enum Failure: Error { case diskFull }
    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: SharedModelContainer.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }
    private func draft(id: UUID = UUID(), rewrites: Bool = true) -> CapsuleDraftCommit.Draft {
        .init(id: id, title: "合成的信", fromRole: "audit", emoji: "💌",
              unlockAt: Date(timeIntervalSince1970: 1_000), blobName: "synthetic.capsule", rewritesPayload: rewrites)
    }

    @Test("封存失败不留下挂起的信，也不提交或回滚别的草稿；重试只有一封")
    func failureRetryIsIsolated() throws {
        let context = try context()
        let other = Entry(authorRole: "audit", note: "没有保存的其他草稿")
        context.insert(other)
        let value = draft()
        #expect(throws: Failure.self) {
            try CapsuleDraftCommit.save(value, editing: nil, in: context) { transaction in
                #expect(transaction !== context)
                #expect(!transaction.autosaveEnabled)
                throw Failure.diskFull
            }
        }
        #expect(try context.fetchCount(FetchDescriptor<TimeCapsule>()) == 0)
        #expect(other.note == "没有保存的其他草稿")
        #expect(context.hasChanges)
        try CapsuleDraftCommit.save(value, editing: nil, in: context)
        let fresh = ModelContext(context.container)
        #expect(try fresh.fetchCount(FetchDescriptor<TimeCapsule>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<Entry>()) == 0)
    }

    @Test("失败后取消，再保存另一个功能不会把失败的信一起提交")
    func cancelledFailureNeverLeaksIntoLaterSave() throws {
        let context = try context()
        #expect(throws: Failure.self) {
            try CapsuleDraftCommit.save(draft(), editing: nil, in: context) { _ in throw Failure.diskFull }
        }
        context.insert(Entry(authorRole: "audit", note: "另一次保存"))
        try context.save()
        #expect(try ModelContext(context.container).fetchCount(FetchDescriptor<TimeCapsule>()) == 0)
    }

    @Test("只改封面失败保留原元数据和原密文，重试才提交")
    func metadataFailurePreservesOriginal() throws {
        let context = try context()
        let original = TimeCapsule(title: "原来的信", fromRole: "audit", unlockAt: .distantFuture)
        original.encryptedBlobFileName = "original.capsule"
        original.cryptoVersion = 3
        original.syncState = .synced
        context.insert(original)
        try context.save()
        let value = draft(id: original.id, rewrites: false)
        #expect(throws: Failure.self) {
            try CapsuleDraftCommit.save(value, editing: original, in: context) { _ in throw Failure.diskFull }
        }
        #expect(original.title == "原来的信")
        #expect(original.encryptedBlobFileName == "original.capsule")
        #expect(original.syncState == .synced)
        #expect(!context.hasChanges)
        try CapsuleDraftCommit.save(value, editing: original, in: context)
        let saved = try #require(ModelContext(context.container).fetch(FetchDescriptor<TimeCapsule>()).first)
        #expect(saved.title == value.title)
        #expect(saved.encryptedBlobFileName == "original.capsule")
        #expect(saved.unlockAt == .distantFuture)
    }
}
