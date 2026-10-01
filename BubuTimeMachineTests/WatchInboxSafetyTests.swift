import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

/// Synthetic bytes and temporary stores only. Requires Apple SwiftData runtime;
/// these are native release-gate tests, not a claim of execution on Linux.
@MainActor
struct WatchInboxSafetyTests {
    private enum InjectedFailure: Error { case diskFull }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WatchInbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func container(at directory: URL) throws -> ModelContainer {
        let schema = SharedModelContainer.schema
        return try ModelContainer(for: schema,
                                  configurations: [ModelConfiguration(schema: schema,
                                      url: directory.appendingPathComponent("synthetic.store"))])
    }

    private func request(localId: String = UUID().uuidString) -> WatchRecordRequest {
        WatchRecordRequest(type: .voice, localId: localId, roleRaw: FamilyRole.mama.rawValue,
                           voiceDuration: 2, happenedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func stage(_ request: WatchRecordRequest, inbox: WatchVoiceInbox, root: URL,
                       bytes: Data = Data("synthetic voice bytes".utf8)) throws -> URL {
        let source = root.appendingPathComponent("WC-\(UUID().uuidString).m4a")
        try bytes.write(to: source)
        let data = try #require(WatchLink.encode(request))
        let json = try #require(String(data: data, encoding: .utf8))
        let package = try inbox.stage(audio: source, metadata: [WatchLink.fileMetaKey: json])
        // Simulate WC deleting its temporary URL immediately after callback return.
        try FileManager.default.removeItem(at: source)
        return package
    }

    @Test("传输送达但手机暂存失败时没有持久回执，手表原件保留供后续重试")
    func failedStagingCannotReleaseWatchSource() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let intent = request()
        let original = root.appendingPathComponent("\(intent.localId).m4a")
        let sidecar = original.deletingPathExtension().appendingPathExtension("json")
        let bytes = Data("synthetic Watch original".utf8)
        try bytes.write(to: original)
        let encoded = try #require(WatchLink.encode(intent))
        try encoded.write(to: sidecar)
        let metadata = [WatchLink.fileMetaKey: try #require(String(data: encoded, encoding: .utf8))]
        let inbox = WatchVoiceInbox(directory: root.appendingPathComponent("phone-inbox"))
        var receipt: WatchVoiceReceipt?
        #expect(throws: InjectedFailure.self) {
            receipt = try inbox.stageForReceipt(audio: original, metadata: metadata) { _, output in
                try Data("partial".utf8).write(to: output)
                throw InjectedFailure.diskFull
            }
        }
        #expect(receipt == nil)
        #expect(try Data(contentsOf: original) == bytes)
        #expect(try Data(contentsOf: sidecar) == encoded)
        #expect(try inbox.pendingVoices().isEmpty)
        #expect(throws: WatchVoiceInbox.ImportError.self) {
            receipt = try inbox.stageForReceipt(audio: original, metadata: metadata) { _, output in
                try Data("silently truncated".utf8).write(to: output)
            }
        }
        #expect(receipt == nil)
        #expect(try inbox.pendingVoices().isEmpty)

        // Normal foreground reconciliation retries. The complete phone package now owns
        // the original before the queued explicit receipt releases the Watch's copy.
        let acknowledged = try #require(try inbox.stageForReceipt(audio: original, metadata: metadata))
        let queued = try #require(try inbox.pendingVoices().first)
        #expect(try Data(contentsOf: queued.audio) == bytes)
        #expect(try acknowledged.removeAcknowledgedSource(audio: original, metadata: sidecar))
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(!FileManager.default.fileExists(atPath: sidecar.path))
        #expect(try !acknowledged.removeAcknowledgedSource(audio: original, metadata: sidecar))

        let disk = try container(at: root)
        #expect(throws: InjectedFailure.self) {
            try inbox.importVoice(queued, into: disk, mediaDirectory: root.appendingPathComponent("media"),
                                  save: { _ in throw InjectedFailure.diskFull })
        }
        #expect(try Data(contentsOf: queued.audio) == bytes)
        try inbox.importVoice(queued, into: disk, mediaDirectory: root.appendingPathComponent("media"))
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<VoiceNote>()) == 1)
    }

    @Test("迟到或不匹配的语音回执不能按 UUID 单独删掉变更的原音频和意图")
    func receiptRequiresSameAudioAndOriginalIntent() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let intent = request()
        let original = root.appendingPathComponent("\(intent.localId).m4a")
        let sidecar = original.deletingPathExtension().appendingPathExtension("json")
        let bytes = Data("synthetic Watch source".utf8)
        let encoded = try #require(WatchLink.encode(intent))
        try bytes.write(to: original)
        try encoded.write(to: sidecar)
        let receipt = try WatchVoiceReceipt.make(audio: original, request: intent)
        try Data("newer same-ID audio".utf8).write(to: original)
        #expect(try !receipt.removeAcknowledgedSource(audio: original, metadata: sidecar))
        try bytes.write(to: original)
        var changedIntent = intent
        changedIntent.roleRaw = "another synthetic parent"
        try #require(WatchLink.encode(changedIntent)).write(to: sidecar)
        #expect(try !receipt.removeAcknowledgedSource(audio: original, metadata: sidecar))
        try encoded.write(to: sidecar)
        let invalid = WatchVoiceReceipt(version: 2, localId: receipt.localId,
            intentSHA256: receipt.intentSHA256, audioSHA256: receipt.audioSHA256)
        #expect(try !invalid.removeAcknowledgedSource(audio: original, metadata: sidecar))
        let mismatched = WatchVoiceReceipt(version: 1, localId: UUID(),
            intentSHA256: receipt.intentSHA256, audioSHA256: receipt.audioSHA256)
        #expect(try !mismatched.removeAcknowledgedSource(audio: original, metadata: sidecar))
        #expect(try Data(contentsOf: original) == bytes)
        #expect(try Data(contentsOf: sidecar) == encoded)
        let replay = try #require(WatchLink.decode(WatchVoiceReceipt.self,
            from: try #require(WatchLink.encode(receipt))))
        #expect(replay == receipt)
        #expect(try replay.removeAcknowledgedSource(audio: original, metadata: sidecar))
    }

    @Test("非法元数据仍保留手机保护副本，但不能回执让手表删原件")
    func malformedMetadataCannotAcknowledgeSource() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data("preserve original audio".utf8).write(to: source)
        let inbox = WatchVoiceInbox(directory: root.appendingPathComponent("inbox"))
        #expect(try inbox.stageForReceipt(audio: source, metadata: [WatchLink.fileMetaKey: "damaged"]) == nil)
        #expect(try inbox.stageForReceipt(audio: source, metadata: [:]) == nil)
        #expect(try inbox.pendingVoices().isEmpty)
        let packages = try FileManager.default.contentsOfDirectory(at: inbox.directory, includingPropertiesForKeys: nil)
        #expect(packages.count == 2)
        for package in packages {
            #expect(try Data(contentsOf: package.appendingPathComponent("recording.m4a")) == Data(contentsOf: source))
        }
    }

    @Test("WC 回调返回前已独立保存原音频和原元数据，重复投递不覆盖")
    func stagePreservesOriginalAndMetadata() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = WatchVoiceInbox(directory: root.appendingPathComponent("inbox"))
        let request = request()
        let first = try stage(request, inbox: inbox, root: root)
        let second = try stage(request, inbox: inbox, root: root, bytes: Data("second delivery".utf8))
        #expect(first != second)
        #expect(try Data(contentsOf: first.appendingPathComponent("recording.m4a")) == Data("synthetic voice bytes".utf8))
        #expect(try Data(contentsOf: second.appendingPathComponent("recording.m4a")) == Data("second delivery".utf8))
        #expect(try inbox.pendingVoices().count == 2)
        #expect(FileManager.default.fileExists(atPath: first.appendingPathComponent("metadata.plist").path))
    }

    @Test("路径穿越和损坏元数据不会导入，也不会删除唯一副本")
    func invalidMetadataAndOrphansRemain() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = WatchVoiceInbox(directory: root.appendingPathComponent("inbox"))
        let malicious = try stage(request(localId: "../../outside"), inbox: inbox, root: root)
        let source = root.appendingPathComponent("source.m4a")
        try Data("preserve corrupt metadata voice".utf8).write(to: source)
        let malformed = try inbox.stage(audio: source, metadata: [WatchLink.fileMetaKey: "not json"])
        let missing = try inbox.stage(audio: source, metadata: [:])
        let legacyID = UUID().uuidString
        let legacyAudio = inbox.directory.appendingPathComponent("\(legacyID).m4a")
        let legacyMetadata = inbox.directory.appendingPathComponent("\(legacyID).json")
        try Data("legacy only copy".utf8).write(to: legacyAudio)
        try Data("damaged".utf8).write(to: legacyMetadata)
        let orphan = inbox.directory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data("old orphan only copy".utf8).write(to: orphan)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: orphan.path)
        #expect(try inbox.pendingVoices().isEmpty)
        for package in [malicious, malformed, missing] {
            #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("recording.m4a").path))
            #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("metadata.plist").path))
        }
        #expect(try Data(contentsOf: legacyAudio) == Data("legacy only copy".utf8))
        #expect(try Data(contentsOf: legacyMetadata) == Data("damaged".utf8))
        #expect(try Data(contentsOf: orphan) == Data("old orphan only copy".utf8))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("outside.m4a").path))
    }

    @Test("恢复内存库不消费持久收件箱，健康磁盘库之后仍可导入")
    func recoveryStoreDoesNotConsumePendingVoice() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = WatchVoiceInbox(directory: root.appendingPathComponent("inbox"))
        let package = try stage(request(), inbox: inbox, root: root)
        let voice = try #require(try inbox.pendingVoices().first)
        let memory = try ModelContainer(for: SharedModelContainer.schema,
                                       configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let media = root.appendingPathComponent("media")
        #expect(throws: WatchVoiceInbox.ImportError.self) {
            try inbox.importVoice(voice, into: memory, mediaDirectory: media)
        }
        #expect(FileManager.default.fileExists(atPath: package.path))
        #expect(try ModelContext(memory).fetchCount(FetchDescriptor<Entry>()) == 0)
        let disk = try container(at: root)
        try inbox.importVoice(voice, into: disk, mediaDirectory: media)
        #expect(!FileManager.default.fileExists(atPath: package.path))
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<VoiceNote>()) == 1)
    }

    @Test("保存失败 rollback 且不删原件；重试只落一条并复用媒体副本")
    func saveFailurePreservesInboxAndRetriesExactlyOnce() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = WatchVoiceInbox(directory: root.appendingPathComponent("inbox"))
        let request = request()
        let package = try stage(request, inbox: inbox, root: root)
        let voice = try #require(try inbox.pendingVoices().first)
        let disk = try container(at: root)
        let media = root.appendingPathComponent("media")
        var attemptedContext: ModelContext?
        #expect(throws: InjectedFailure.self) {
            try inbox.importVoice(voice, into: disk, mediaDirectory: media, save: { context in
                #expect(!context.autosaveEnabled)
                attemptedContext = context
                throw InjectedFailure.diskFull
            })
        }
        let failedContext = try #require(attemptedContext)
        #expect(!failedContext.hasChanges)
        #expect(try failedContext.fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("recording.m4a").path))
        #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("metadata.plist").path))
        try inbox.importVoice(voice, into: disk, mediaDirectory: media)
        #expect(!FileManager.default.fileExists(atPath: package.path))
        let duplicate = try stage(request, inbox: inbox, root: root)
        try inbox.importVoice(try #require(try inbox.pendingVoices().first), into: disk, mediaDirectory: media)
        #expect(!FileManager.default.fileExists(atPath: duplicate.path))
        let readback = ModelContext(disk)
        #expect(try readback.fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(try readback.fetchCount(FetchDescriptor<VoiceNote>()) == 1)
        #expect(try readback.fetchCount(FetchDescriptor<FeedEvent>()) == 1)
        #expect(try FileManager.default.contentsOfDirectory(at: media, includingPropertiesForKeys: nil).count == 1)
        let note = try #require(try readback.fetch(FetchDescriptor<VoiceNote>()).first)
        let name = try #require(note.localFileName)
        #expect(try Data(contentsOf: media.appendingPathComponent(name)) == Data("synthetic voice bytes".utf8))
    }

    @Test("拷贝中途失败不占用最终文件名；遗留 partial 不阻止下一次完整导入")
    func partialMediaCopyCanRetryWithoutOverwritingFinal() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = WatchVoiceInbox(directory: root.appendingPathComponent("inbox"))
        let package = try stage(request(), inbox: inbox, root: root)
        let voice = try #require(try inbox.pendingVoices().first)
        let disk = try container(at: root)
        let media = root.appendingPathComponent("media")
        let final = media.appendingPathComponent("watch-\(voice.deliveryId.uuidString).m4a")
        var interruptedTemporary: URL?
        #expect(throws: InjectedFailure.self) {
            try inbox.importVoice(voice, into: disk, mediaDirectory: media, copyAudio: { _, temporary in
                interruptedTemporary = temporary
                try Data("truncated".utf8).write(to: temporary)
                throw InjectedFailure.diskFull
            })
        }
        #expect(!FileManager.default.fileExists(atPath: final.path))
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(try Data(contentsOf: voice.audio) == Data("synthetic voice bytes".utf8))
        #expect(FileManager.default.fileExists(atPath: voice.metadata.path))
        let leftover = try #require(interruptedTemporary)
        #expect(leftover.deletingLastPathComponent().standardizedFileURL.path == media.standardizedFileURL.path)
        #expect(leftover != final)
        // Simulate process death before defer could remove a previous attempt's partial.
        try Data("abandoned partial".utf8).write(to: leftover)
        try inbox.importVoice(voice, into: disk, mediaDirectory: media)
        #expect(try Data(contentsOf: final) == Data("synthetic voice bytes".utf8))
        #expect(try Data(contentsOf: leftover) == Data("abandoned partial".utf8))
        #expect(!FileManager.default.fileExists(atPath: package.path))
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<VoiceNote>()) == 1)
    }

    @Test("不完整拷贝不能发布，既有冲突目标也绝不能被重试覆盖")
    func truncatedCopyAndExistingFinalRemainSafe() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = WatchVoiceInbox(directory: root.appendingPathComponent("inbox"))
        let package = try stage(request(), inbox: inbox, root: root)
        let voice = try #require(try inbox.pendingVoices().first)
        let disk = try container(at: root)
        let media = root.appendingPathComponent("media")
        let final = media.appendingPathComponent("watch-\(voice.deliveryId.uuidString).m4a")
        #expect(throws: WatchVoiceInbox.ImportError.self) {
            try inbox.importVoice(voice, into: disk, mediaDirectory: media, copyAudio: { _, temporary in
                try Data("truncated without throwing".utf8).write(to: temporary)
            })
        }
        #expect(!FileManager.default.fileExists(atPath: final.path))
        let existing = Data("existing conflicting audio must survive".utf8)
        try existing.write(to: final)
        #expect(throws: WatchVoiceInbox.ImportError.self) {
            try inbox.importVoice(voice, into: disk, mediaDirectory: media)
        }
        #expect(try Data(contentsOf: final) == existing)
        try FileManager.default.removeItem(at: final)
        // Another writer publishes a conflicting final after our existence check.
        #expect(throws: (any Error).self) {
            try inbox.importVoice(voice, into: disk, mediaDirectory: media, copyAudio: { source, temporary in
                try FileManager.default.copyItem(at: source, to: temporary)
                try existing.write(to: final)
            })
        }
        #expect(try Data(contentsOf: final) == existing)
        #expect(FileManager.default.fileExists(atPath: package.path))
        #expect(try Data(contentsOf: voice.audio) == Data("synthetic voice bytes".utf8))
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<Entry>()) == 0)
    }

    @Test("无真实提交时，不能用同 context 的脏对象伪造已落盘去重")
    func freshContextReadbackRequiredBeforeDeletingOriginal() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = WatchVoiceInbox(directory: root.appendingPathComponent("inbox"))
        let package = try stage(request(), inbox: inbox, root: root)
        let disk = try container(at: root)
        let voice = try #require(try inbox.pendingVoices().first)
        #expect(throws: WatchVoiceInbox.ImportError.self) {
            try inbox.importVoice(voice, into: disk, mediaDirectory: root.appendingPathComponent("media"), save: { _ in })
        }
        #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("recording.m4a").path))
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<Entry>()) == 0)
    }

    @Test("同 ID 只有 Entry 或不同音频不算已保存，必须保留待恢复副本")
    func incompleteOrConflictingDuplicateIsNotConsumed() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = WatchVoiceInbox(directory: root.appendingPathComponent("inbox"))
        let request = request()
        let package = try stage(request, inbox: inbox, root: root)
        let disk = try container(at: root)
        let seed = ModelContext(disk)
        seed.autosaveEnabled = false
        let entry = Entry(authorRole: FamilyRole.mama.rawValue, note: "synthetic conflicting entry")
        entry.id = try #require(UUID(uuidString: request.localId))
        seed.insert(entry)
        try seed.save()
        let voice = try #require(try inbox.pendingVoices().first)
        let media = root.appendingPathComponent("media")
        #expect(throws: WatchVoiceInbox.ImportError.self) {
            try inbox.importVoice(voice, into: disk, mediaDirectory: media)
        }
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try Data("different audio".utf8).write(to: media.appendingPathComponent("different.m4a"))
        let note = VoiceNote(localFileName: "different.m4a", durationSeconds: 1,
                             authorRole: FamilyRole.mama.rawValue)
        note.entry = entry
        seed.insert(note)
        try seed.save()
        #expect(throws: WatchVoiceInbox.ImportError.self) {
            try inbox.importVoice(voice, into: disk, mediaDirectory: media)
        }
        #expect(FileManager.default.fileExists(atPath: package.path))
        #expect(try Data(contentsOf: media.appendingPathComponent("different.m4a")) == Data("different audio".utf8))
    }

    @Test("新版仍可导入旧收件箱，且不会顺带保存 UI 的未提交对象")
    func legacyInboxAndContextIsolation() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = WatchVoiceInbox(directory: root.appendingPathComponent("inbox"))
        try FileManager.default.createDirectory(at: inbox.directory, withIntermediateDirectories: true)
        let request = request()
        let audio = inbox.directory.appendingPathComponent("\(request.localId).m4a")
        let metadata = inbox.directory.appendingPathComponent("\(request.localId).json")
        try Data("legacy audio".utf8).write(to: audio)
        try #require(WatchLink.encode(request)).write(to: metadata)
        let disk = try container(at: root)
        let ui = ModelContext(disk)
        ui.autosaveEnabled = false
        ui.insert(Entry(authorRole: FamilyRole.mama.rawValue, note: "unsaved UI edit"))
        let voice = try #require(try inbox.pendingVoices().first)
        try inbox.importVoice(voice, into: disk, mediaDirectory: root.appendingPathComponent("media"))
        #expect(ui.hasChanges)
        #expect(try ModelContext(disk).fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(!FileManager.default.fileExists(atPath: audio.path))
        #expect(!FileManager.default.fileExists(atPath: metadata.path))
        ui.rollback()
    }
}
