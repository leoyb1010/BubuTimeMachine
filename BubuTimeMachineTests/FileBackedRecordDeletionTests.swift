import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

@MainActor
struct FileBackedRecordDeletionTests {
    private enum InjectedFailure: Error { case diskFull, afterCommit }
    private struct Fixture {
        let root: URL
        let container: ModelContainer
        let parent: Entry
        let request: FileBackedRecordDeletion.Request
        var context: ModelContext { container.mainContext }
        func file(_ name: String) -> URL { root.appendingPathComponent(name) }
    }

    private func fixture(_ kind: String) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("delete-boundary-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(
            schema: schema, url: root.appendingPathComponent("synthetic.store"))])
        let context = container.mainContext
        context.autosaveEnabled = false
        let parent = Entry(authorRole: "synthetic", note: "persisted parent")
        parent.syncState = .synced
        context.insert(parent)
        let request: FileBackedRecordDeletion.Request
        switch kind {
        case "media":
            let value = Media(type: .photo, localFileName: "original.bin")
            value.remoteId = "remote-media"; value.thumbnailFileName = "thumbnail.bin"; value.entry = parent
            context.insert(value); request = .init(value)
        case "voice":
            let value = VoiceNote(localFileName: "original.bin", durationSeconds: 1, authorRole: "synthetic")
            value.remoteId = "remote-voice"; value.entry = parent
            context.insert(value); request = .init(value)
        default:
            let value = TimeCapsule(title: "synthetic capsule", fromRole: "synthetic", unlockAt: .now)
            value.remoteId = "remote-capsule"; value.encryptedBlobFileName = "original.bin"
            context.insert(value); request = .init(value)
        }
        try context.save()
        try Data("original bytes".utf8).write(to: root.appendingPathComponent("original.bin"))
        try Data("thumbnail bytes".utf8).write(to: root.appendingPathComponent("thumbnail.bin"))
        return Fixture(root: root, container: container, parent: parent, request: request)
    }

    private func recordCount(_ fixture: Fixture) throws -> Int {
        let context = ModelContext(fixture.container)
        let id = fixture.request.id
        switch fixture.request.kind {
        case .media: return try context.fetchCount(FetchDescriptor<Media>(predicate: #Predicate { $0.id == id }))
        case .voice: return try context.fetchCount(FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.id == id }))
        case .capsule: return try context.fetchCount(FetchDescriptor<TimeCapsule>(predicate: #Predicate { $0.id == id }))
        }
    }

    @Test("失败保留行和原文件；重试后清理；同父记录和其他草稿不回滚也不复活子行", arguments: ["media", "voice", "capsule"])
    func failureRetryPreservesDrafts(_ kind: String) async throws {
        let f = try fixture(kind)
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.parent.note = "unsaved same-parent correction"
        f.parent.editedAt = .now; f.parent.syncState = .local
        let otherDraft = Entry(authorRole: "synthetic", note: "unrelated unsaved draft")
        f.context.insert(otherDraft)
        var cleanups = 0
        var attempted: ModelContext?
        let cleanup: (String?, String?) -> Void = { media, thumbnail in
            cleanups += 1
            #expect((try? recordCount(f)) == 0)
            if let media { try? FileManager.default.removeItem(at: f.file(media)) }
            if let thumbnail { try? FileManager.default.removeItem(at: f.file(thumbnail)) }
        }
        #expect(throws: InjectedFailure.self) {
            try FileBackedRecordDeletion.delete(f.request, from: f.context, save: {
                attempted = $0
                #expect($0 !== f.context && !$0.autosaveEnabled)
                throw InjectedFailure.diskFull
            }, removeFiles: cleanup)
        }
        #expect(attempted?.hasChanges == false)
        #expect(cleanups == 0)
        #expect(try recordCount(f) == 1)
        #expect(try Data(contentsOf: f.file("original.bin")) == Data("original bytes".utf8))
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<PendingDeletion>()) == 0)
        #expect(f.parent.note == "unsaved same-parent correction" && f.context.hasChanges)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<Entry>()) == 1)

        try FileBackedRecordDeletion.delete(f.request, from: f.context, removeFiles: cleanup)
        #expect(cleanups == 1 && !FileManager.default.fileExists(atPath: f.file("original.bin").path))
        #expect(try recordCount(f) == 0)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<PendingDeletion>()) == 1)
        #expect(f.parent.note == "unsaved same-parent correction" && f.context.hasChanges)
        #expect(otherDraft.note == "unrelated unsaved draft")
        let persistedParent = try #require(try ModelContext(f.container).fetch(FetchDescriptor<Entry>()).first)
        #expect(persistedParent.note == "persisted parent")
        // Completing the already-open editor must not recreate a deleted relationship.
        try f.context.save()
        await Task.yield()
        #expect(try recordCount(f) == 0)
        let entries = try ModelContext(f.container).fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 2)
        #expect(entries.contains { $0.note == "unsaved same-parent correction" })
        if kind == "media" { #expect(f.parent.media.isEmpty) }
        if kind == "voice" { #expect(f.parent.voiceNotes.isEmpty) }
        #expect(throws: FileBackedRecordDeletion.DeletionError.self) {
            try FileBackedRecordDeletion.delete(f.request, from: f.context, removeFiles: cleanup)
        }
        #expect(cleanups == 1)
    }

    @Test("未真正提交的save回调不能清理原件", arguments: ["media", "voice", "capsule"])
    func ineffectiveSaveKeepsOriginal(_ kind: String) throws {
        let f = try fixture(kind)
        defer { try? FileManager.default.removeItem(at: f.root) }
        var attempted: ModelContext?
        var cleaned = false
        #expect(throws: FileBackedRecordDeletion.DeletionError.self) {
            try FileBackedRecordDeletion.delete(f.request, from: f.context, save: { attempted = $0 },
                removeFiles: { _, _ in cleaned = true })
        }
        #expect(!cleaned && attempted?.hasChanges == false)
        #expect(try recordCount(f) == 1)
        #expect(try Data(contentsOf: f.file("original.bin")) == Data("original bytes".utf8))
    }

    @Test("旧UI文件引用不能删除后来替换的文件", arguments: ["media", "voice", "capsule"])
    func changedFileRefusesStaleRequest(_ kind: String) throws {
        let f = try fixture(kind)
        defer { try? FileManager.default.removeItem(at: f.root) }
        let writer = ModelContext(f.container)
        switch f.request.kind {
        case .media:
            let value = try #require(try writer.fetch(FetchDescriptor<Media>()).first)
            value.localFileName = "new.bin"
        case .voice:
            let value = try #require(try writer.fetch(FetchDescriptor<VoiceNote>()).first)
            value.localFileName = "new.bin"
        case .capsule:
            let value = try #require(try writer.fetch(FetchDescriptor<TimeCapsule>()).first)
            value.encryptedBlobFileName = "new.bin"
        }
        try writer.save()
        try Data("new bytes".utf8).write(to: f.file("new.bin"))
        var cleaned = false
        #expect(throws: FileBackedRecordDeletion.DeletionError.self) {
            try FileBackedRecordDeletion.delete(f.request, from: f.context, removeFiles: { _, _ in cleaned = true })
        }
        #expect(!cleaned && FileManager.default.fileExists(atPath: f.file("new.bin").path))
        #expect(try recordCount(f) == 1)
        #expect(try Data(contentsOf: f.file("original.bin")) == Data("original bytes".utf8))
    }

    @Test("其他未保存草稿仍引用的文件不被释放", arguments: ["media", "voice", "capsule"])
    func unsavedSharedFileOwnerKeepsBytes(_ kind: String) throws {
        let f = try fixture(kind)
        defer { try? FileManager.default.removeItem(at: f.root) }
        let other = Media(type: .photo, localFileName: "original.bin")
        other.thumbnailFileName = "thumbnail.bin"
        f.context.insert(other)
        var cleaned = false
        try FileBackedRecordDeletion.delete(f.request, from: f.context, removeFiles: { _, _ in cleaned = true })
        #expect(!cleaned && f.context.hasChanges)
        #expect(try recordCount(f) == 0)
        #expect(try Data(contentsOf: f.file("original.bin")) == Data("original bytes".utf8))
        try f.context.save()
        #expect(try recordCount(f) == 0)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<Media>()) == 1)
    }

    @Test("提交后验证路径抛错也宁可留原文件", arguments: ["media", "voice", "capsule"])
    func postCommitErrorCannotAuthorizeCleanup(_ kind: String) throws {
        let f = try fixture(kind)
        defer { try? FileManager.default.removeItem(at: f.root) }
        var cleaned = false
        #expect(throws: InjectedFailure.self) {
            try FileBackedRecordDeletion.delete(f.request, from: f.context, save: {
                try $0.save()
                throw InjectedFailure.afterCommit
            }, removeFiles: { _, _ in cleaned = true })
        }
        #expect(!cleaned && FileManager.default.fileExists(atPath: f.file("original.bin").path))
        #expect(try recordCount(f) == 0)
    }

    @Test("内存保护容器与未提交的素材行都不能授权删除磁盘原件")
    func ephemeralAndUncommittedModelsCannotAuthorizeCleanup() throws {
        let schema = SharedModelContainer.schema
        let memory = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let capsule = TimeCapsule(title: "temporary", fromRole: "synthetic", unlockAt: .now)
        capsule.encryptedBlobFileName = "must-not-touch.bin"
        memory.mainContext.insert(capsule)
        try memory.mainContext.save()
        var cleaned = false
        #expect(throws: FileBackedRecordDeletion.DeletionError.self) {
            try FileBackedRecordDeletion.delete(.init(capsule), from: memory.mainContext,
                removeFiles: { _, _ in cleaned = true })
        }
        #expect(!cleaned)

        let f = try fixture("media")
        defer { try? FileManager.default.removeItem(at: f.root) }
        let pending = Media(type: .photo, localFileName: "pending.bin")
        pending.entry = f.parent
        f.context.insert(pending)
        let bytes = Data("unsaved original".utf8)
        try bytes.write(to: f.file("pending.bin"))
        #expect(throws: FileBackedRecordDeletion.DeletionError.self) {
            try FileBackedRecordDeletion.delete(.init(pending), from: f.context,
                removeFiles: { _, _ in cleaned = true })
        }
        #expect(!cleaned && f.context.hasChanges)
        #expect(try Data(contentsOf: f.file("pending.bin")) == bytes)
        #expect(try recordCount(f) == 1)
    }

    @Test("已换远端身份或父记录的素材不接受旧删除请求")
    func changedRemoteIdentityOrParentRefusesRequest() throws {
        for reparent in [false, true] {
            let f = try fixture("media")
            defer { try? FileManager.default.removeItem(at: f.root) }
            let context = ModelContext(f.container)
            let media = try #require(try context.fetch(FetchDescriptor<Media>()).first)
            if reparent {
                let parent = Entry(authorRole: "synthetic", note: "new parent")
                context.insert(parent)
                media.entry = parent
            } else { media.remoteId = "different-remote" }
            try context.save()
            var cleaned = false
            #expect(throws: FileBackedRecordDeletion.DeletionError.self) {
                try FileBackedRecordDeletion.delete(f.request, from: f.context,
                    removeFiles: { _, _ in cleaned = true })
            }
            #expect(!cleaned && FileManager.default.fileExists(atPath: f.file("original.bin").path))
            #expect(try recordCount(f) == 1)
        }
    }

}
