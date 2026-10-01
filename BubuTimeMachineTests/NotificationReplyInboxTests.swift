import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

/// All text, files and stores are synthetic and temporary. Native SwiftData execution is
/// required; constructing a handler here never resolves the real App Group directory.
@MainActor
struct NotificationReplyInboxTests {
    private enum InjectedFailure: Error { case diskFull, fetch, remove }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotificationReply-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func container(at root: URL) throws -> ModelContainer {
        let schema = SharedModelContainer.schema
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: root.appendingPathComponent("synthetic.store"))
        ])
    }

    private func reply(id: UUID = UUID(), note: String = "synthetic notification reply") -> NotificationReplyInbox.Reply {
        NotificationReplyInbox.Reply(id: id, note: note, role: .papa,
                                     happenedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func file(_ reply: NotificationReplyInbox.Reply, in inbox: NotificationReplyInbox) -> URL {
        inbox.directory.appendingPathComponent("\(reply.id.uuidString).json")
    }

    private func fetch(_ context: ModelContext, id: UUID) throws -> Entry? {
        try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })).first
    }

    @Test("先原子保护暂存，再尝试打开事实库；进程重启后仍保留原意图")
    func stagePrecedesStoreLookupAndSurvivesRestart() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = NotificationReplyInbox(directory: root.appendingPathComponent("inbox"))
        let intent = reply(note: "测试文字 👶\nsecond line")
        var lookedUpAfterStaging = false
        var signals = 0
        let handler = NotificationReplyHandler(inboxDirectory: { inbox.directory }, availableContainer: {
            lookedUpAfterStaging = (try? inbox.pendingReplies()) == [intent]
            return nil
        }, didRecord: { signals += 1 })
        try handler.receiveReply(text: intent.note, role: intent.role, id: intent.id, happenedAt: intent.happenedAt)
        #expect(lookedUpAfterStaging)
        #expect(signals == 0)
        let reopened = NotificationReplyInbox(directory: inbox.directory)
        #expect(try reopened.pendingReplies() == [intent])
        let attributes = try FileManager.default.attributesOfItem(atPath: file(intent, in: inbox).path)
        #expect(attributes[.protectionKey] as? FileProtectionType == .completeUntilFirstUserAuthentication)
        try reopened.stage(intent)
        #expect(try reopened.pendingReplies().count == 1)
        #expect(throws: NotificationReplyInbox.InboxError.self) {
            try reopened.stage(reply(id: intent.id, note: "different original"))
        }
        #expect(try reopened.pendingReplies() == [intent])
    }

    @Test("恢复内存库不消费回复；健康磁盘库恢复后才广播并清除意图")
    func unavailableAndMemoryStoresRetainReplyUntilHealthyRetry() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = NotificationReplyInbox(directory: root.appendingPathComponent("inbox"))
        let intent = reply()
        let memory = try ModelContainer(for: SharedModelContainer.schema,
                                       configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        var available: ModelContainer?
        var signals = 0
        let handler = NotificationReplyHandler(inboxDirectory: { inbox.directory }, availableContainer: { available },
                                               didRecord: { signals += 1 })
        try handler.receiveReply(text: intent.note, role: intent.role, id: intent.id, happenedAt: intent.happenedAt)
        available = memory
        handler.retryPendingReplies()
        #expect(throws: NotificationReplyInbox.InboxError.self) { try inbox.importReply(intent, into: memory) }
        #expect(signals == 0)
        #expect(try inbox.pendingReplies() == [intent])
        #expect(try ModelContext(memory).fetchCount(FetchDescriptor<Entry>()) == 0)

        let disk = try container(at: root)
        available = disk
        handler.retryPendingReplies()
        #expect(signals == 1)
        #expect(try inbox.pendingReplies().isEmpty)
        let stored = try #require(try fetch(ModelContext(disk), id: intent.id))
        #expect(stored.note == intent.note)
        #expect(stored.authorRole == intent.role.rawValue)
        #expect(stored.happenedAt == intent.happenedAt)
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<FeedEvent>()) == 1)
        handler.retryPendingReplies()
        #expect(signals == 1)
    }

    @Test("保存失败关闭自动保存并 rollback；重试恰好保存一条记录和动态")
    func saveFailureRollsBackAndKeepsIntent() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = NotificationReplyInbox(directory: root.appendingPathComponent("inbox"))
        let intent = reply()
        try inbox.stage(intent)
        let disk = try container(at: root)
        var attempted: ModelContext?
        #expect(throws: InjectedFailure.self) {
            try inbox.importReply(intent, into: disk, save: { context in
                #expect(!context.autosaveEnabled)
                #expect(context !== disk.mainContext)
                attempted = context
                throw InjectedFailure.diskFull
            })
        }
        let context = try #require(attempted)
        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<FeedEvent>()) == 0)
        #expect(try inbox.pendingReplies() == [intent])
        try inbox.importReply(intent, into: disk)
        #expect(try inbox.pendingReplies().isEmpty)
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<FeedEvent>()) == 1)
    }

    @Test("保存闭包未真正提交时独立回读拒绝删除意图")
    func uncommittedObjectsCannotAcknowledgeReply() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = NotificationReplyInbox(directory: root.appendingPathComponent("inbox"))
        let intent = reply()
        try inbox.stage(intent)
        let disk = try container(at: root)
        var attempted: ModelContext?
        #expect(throws: NotificationReplyInbox.InboxError.self) {
            try inbox.importReply(intent, into: disk, save: { attempted = $0 })
        }
        #expect(try inbox.pendingReplies() == [intent])
        #expect(attempted?.hasChanges == false)
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<Entry>()) == 0)
        try inbox.importReply(intent, into: disk)
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<Entry>()) == 1)
    }

    @Test("去重读取失败不能当成不存在或已保存；回读失败保留意图供幂等重试")
    func failedFetchNeverMeansSuccessfulDedupe() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = NotificationReplyInbox(directory: root.appendingPathComponent("inbox"))
        let intent = reply()
        try inbox.stage(intent)
        let disk = try container(at: root)
        var saveCalled = false
        #expect(throws: InjectedFailure.self) {
            try inbox.importReply(intent, into: disk, fetch: { _, _ in throw InjectedFailure.fetch },
                                  save: { _ in saveCalled = true })
        }
        #expect(!saveCalled)
        #expect(try inbox.pendingReplies() == [intent])
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<Entry>()) == 0)

        var reads = 0
        #expect(throws: InjectedFailure.self) {
            try inbox.importReply(intent, into: disk, fetch: { context, id in
                reads += 1
                if reads == 2 { throw InjectedFailure.fetch }
                return try fetch(context, id: id)
            })
        }
        #expect(try inbox.pendingReplies() == [intent])
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<Entry>()) == 1)
        try inbox.importReply(intent, into: disk)
        #expect(try inbox.pendingReplies().isEmpty)
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<FeedEvent>()) == 1)
    }

    @Test("提交后进程中断或删除失败仍可去重；不提交 UI context 的无关草稿")
    func interruptedCleanupRetriesWithoutDuplicatesOrCommittingUIDrafts() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = NotificationReplyInbox(directory: root.appendingPathComponent("inbox"))
        let intent = reply()
        try inbox.stage(intent)
        let disk = try container(at: root)
        disk.mainContext.autosaveEnabled = false
        disk.mainContext.insert(Entry(authorRole: FamilyRole.mama.rawValue, note: "unsaved UI draft"))
        #expect(throws: InjectedFailure.self) {
            try inbox.importReply(intent, into: disk, remove: { _ in throw InjectedFailure.remove })
        }
        #expect(disk.mainContext.hasChanges)
        #expect(try inbox.pendingReplies() == [intent])
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<Entry>()) == 1)
        // A new inbox models a fresh process after commit but before removing the staged JSON.
        let restarted = NotificationReplyInbox(directory: inbox.directory)
        try restarted.importReply(try #require(try restarted.pendingReplies().first), into: disk)
        #expect(try restarted.pendingReplies().isEmpty)
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<FeedEvent>()) == 1)
        disk.mainContext.rollback()
    }

    @Test("相同 UUID 的不同事实不能覆盖或误认成功，且不广播保存成功")
    func existingConflictPreservesBothVersionsWithoutSuccessSignal() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = NotificationReplyInbox(directory: root.appendingPathComponent("inbox"))
        let intent = reply()
        let disk = try container(at: root)
        let context = ModelContext(disk)
        let original = Entry(happenedAt: intent.happenedAt, authorRole: intent.role.rawValue, note: "previous unrelated fact")
        original.id = intent.id
        context.insert(original)
        try context.save()
        var signals = 0
        let handler = NotificationReplyHandler(inboxDirectory: { inbox.directory }, availableContainer: { disk },
                                               didRecord: { signals += 1 })
        try handler.receiveReply(text: intent.note, role: intent.role, id: intent.id, happenedAt: intent.happenedAt)
        #expect(signals == 0)
        #expect(try inbox.pendingReplies() == [intent])
        #expect(try fetch(ModelContext(disk), id: intent.id)?.note == "previous unrelated fact")
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<Entry>()) == 1)
    }

    @Test("损坏或文件名不匹配的原始回复保留，其他有效回复仍可处理")
    func malformedAndMismatchedFilesRemainUntouched() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = NotificationReplyInbox(directory: root.appendingPathComponent("inbox"))
        let intent = reply()
        try inbox.stage(intent)
        let damaged = inbox.directory.appendingPathComponent("\(UUID().uuidString).json")
        let mismatched = inbox.directory.appendingPathComponent("\(UUID().uuidString).json")
        let corruptBytes = Data("preserve truncated original".utf8)
        let mismatchBytes = try JSONEncoder().encode(reply())
        try corruptBytes.write(to: damaged)
        try mismatchBytes.write(to: mismatched)
        #expect(try inbox.pendingReplies() == [intent])
        try inbox.importReply(intent, into: container(at: root))
        #expect(try inbox.pendingReplies().isEmpty)
        #expect(try Data(contentsOf: damaged) == corruptBytes)
        #expect(try Data(contentsOf: mismatched) == mismatchBytes)
    }

    @Test("暂存本身失败时不打开事实库或广播成功")
    func stagingFailureDoesNotAttemptStoreOrSignalSuccess() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data("keep this file".utf8).write(to: blocked)
        var opened = false
        var signals = 0
        let handler = NotificationReplyHandler(inboxDirectory: { blocked }, availableContainer: {
            opened = true
            return nil
        }, didRecord: { signals += 1 })
        #expect(throws: (any Error).self) { try handler.receiveReply(text: "synthetic", role: .mama) }
        #expect(!opened)
        #expect(signals == 0)
        #expect(try Data(contentsOf: blocked) == Data("keep this file".utf8))
    }
}
