import Foundation
import SwiftData
import Testing
import UIKit
@testable import BubuTimeMachine

/// Real temporary SwiftData stores, synthetic media, and deterministic import suspension.
/// Leave temporary SQLite roots to process/OS cleanup: unlinking a live ModelContainer's
/// database in defer violates SQLite's open-file lifetime, even for test fixtures.
@MainActor
struct CapturePersistenceTests {
    private enum Failure: Error { case diskFull }

    private struct Fixture {
        let root: URL
        let container: ModelContainer
        var context: ModelContext { container.mainContext }
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: root.appendingPathComponent("synthetic.store"))
        ])
        container.mainContext.autosaveEnabled = false
        return Fixture(root: root, container: container)
    }

    private func model(_ operations: CaptureModel.SaveOperations) -> CaptureModel {
        CaptureModel(mediaStore: MediaStore(), analyzer: PhotoAnalyzer(), role: .papa, operations: operations)
    }

    @MainActor
    private final class ImportGate {
        var started = false
        private var released = false
        private var continuation: CheckedContinuation<Void, Never>?
        func pause() async {
            started = true
            guard !released else { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { released = true; continuation?.resume(); continuation = nil }
    }

    @Test("保存失败仅回滚本次事务；新媒体清理、原录音与其他草稿保留，重试只存一条")
    func failureRetryPreservesDraftAndVoice() async throws {
        let f = try fixture()
        let unrelated = Entry(authorRole: "synthetic", note: "other unsaved draft")
        f.context.insert(unrelated)
        let voiceURL = f.root.appendingPathComponent("original.m4a")
        try Data("synthetic original voice".utf8).write(to: voiceURL)
        var createdFiles: [URL] = []
        var writes = 0
        var attempted: ModelContext?
        var transcriptions = 0
        var committed = 0
        var operations = CaptureModel.SaveOperations()
        operations.save = { context in
            attempted = context
            #expect(context !== f.context && !context.autosaveEnabled)
            writes += 1
            if writes == 1 { throw Failure.diskFull }
            try context.save()
        }
        operations.importCameraPhoto = { _, _ in
            let file = f.root.appendingPathComponent("\(UUID()).jpg")
            let thumb = f.root.appendingPathComponent("\(UUID()).thumb")
            try? Data("synthetic photo".utf8).write(to: file)
            try? Data("synthetic thumbnail".utf8).write(to: thumb)
            createdFiles += [file, thumb]
            let media = Media(type: .photo, localFileName: file.lastPathComponent)
            media.thumbnailFileName = thumb.lastPathComponent
            return (media, nil)
        }
        operations.removeFiles = { media, thumbnail in
            for name in [media, thumbnail].compactMap({ $0 }) {
                try? FileManager.default.removeItem(at: f.root.appendingPathComponent(name))
            }
        }
        operations.transcribe = { _ in transcriptions += 1; return nil }
        operations.didCommit = { _ in committed += 1 }
        let capture = model(operations)
        capture.startQuickCapture(prefillNote: "capture draft")
        capture.cameraPhotos = [SelectedCameraPhoto(image: UIImage())]
        capture.pendingVoice = (voiceURL.lastPathComponent, 1, [])

        #expect(await capture.savePickedItems(into: f.context) == false)
        await Task.yield()
        #expect(attempted?.hasChanges == false)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(f.context.hasChanges && unrelated.note == "other unsaved draft")
        #expect(try f.context.fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(capture.note == "capture draft" && capture.showQuickCapture)
        #expect(capture.pendingVoice?.fileName == "original.m4a")
        #expect(try Data(contentsOf: voiceURL) == Data("synthetic original voice".utf8))
        #expect(createdFiles.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(transcriptions == 0 && committed == 0)

        #expect(await capture.savePickedItems(into: f.context))
        let fresh = ModelContext(f.container)
        #expect(try fresh.fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<Media>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<VoiceNote>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<FeedEvent>()) == 1)
        #expect(f.context.hasChanges && unrelated.note == "other unsaved draft")
        #expect(createdFiles.suffix(2).allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(committed == 1 && !capture.isSaving && !capture.showQuickCapture)
    }

    @Test("导入挂起时不能退出、新开或重入保存；最终使用保存开始时的草稿快照")
    func suspendedImportIsSingleFlightAndUsesSnapshot() async throws {
        let f = try fixture()
        let gate = ImportGate()
        var imports = 0
        var transcribed = false
        var operations = CaptureModel.SaveOperations()
        operations.importCameraPhoto = { _, includeLocation in
            imports += 1
            #expect(!includeLocation)
            if imports == 1 { await gate.pause() }
            return (Media(type: .photo, localFileName: "synthetic.jpg"), nil)
        }
        operations.removeFiles = { _, _ in }
        operations.transcribe = { _ in transcribed = true; return nil }
        operations.didCommit = { _ in }
        let capture = model(operations)
        capture.startQuickCapture(prefillNote: "original draft")
        capture.cameraPhotos = [SelectedCameraPhoto(image: UIImage())]
        let saving = Task { await capture.savePickedItems(into: f.context) }
        defer { gate.release() }
        for _ in 0..<1_000 where !gate.started { await Task.yield() }
        try #require(gate.started)
        #expect(capture.isSaving)
        capture.showQuickCapture = false
        #expect(capture.showQuickCapture)
        capture.startQuickCapture(prefillNote: "replacement draft")
        #expect(capture.note == "original draft")
        #expect(await capture.savePickedItems(into: f.context) == false)
        // Simulate a late asynchronous UI callback; it must not change the save snapshot.
        capture.role = .mama
        capture.includeLocation = true
        capture.pendingVoice = ("late-callback.m4a", 2, [])
        gate.release()
        #expect(await saving.value)
        let fresh = ModelContext(f.container)
        let saved = try #require(fresh.fetch(FetchDescriptor<Entry>()).first)
        #expect(saved.note == "original draft" && saved.authorRole == FamilyRole.papa.rawValue)
        #expect(try fresh.fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<VoiceNote>()) == 0)
        #expect(imports == 1 && !transcribed)
    }

    @Test("转写只在提交可独立回读之后启动，回写不提交无关 UI 草稿")
    func transcriptionStartsAfterCommit() async throws {
        let f = try fixture()
        let unrelated = Entry(authorRole: "synthetic", note: "unsaved")
        f.context.insert(unrelated)
        var transcriptionFinished = false
        var operations = CaptureModel.SaveOperations()
        operations.transcribe = { _ in
            let fresh = ModelContext(f.container)
            #expect((try? fresh.fetchCount(FetchDescriptor<VoiceNote>())) == 1)
            #expect((try? fresh.fetchCount(FetchDescriptor<Entry>())) == 1)
            transcriptionFinished = true
            return "synthetic transcript"
        }
        operations.didCommit = { _ in }
        let capture = model(operations)
        capture.startQuickCapture(prefillNote: "voice draft")
        capture.pendingVoice = ("synthetic-voice.m4a", 2, [])
        #expect(await capture.savePickedItems(into: f.context))
        for _ in 0..<100 where !transcriptionFinished { await Task.yield() }
        #expect(transcriptionFinished)
        await Task.yield()
        let fresh = ModelContext(f.container)
        #expect(try fresh.fetch(FetchDescriptor<VoiceNote>()).first?.transcript == "synthetic transcript")
        #expect(try fresh.fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(f.context.hasChanges)
    }

    @Test("导入期间取消会清理本次副本、保留草稿，不能提交半条记录")
    func cancelledImportDoesNotCommit() async throws {
        let f = try fixture()
        let gate = ImportGate()
        var removed: [String] = []
        var operations = CaptureModel.SaveOperations()
        operations.importCameraPhoto = { _, _ in
            await gate.pause()
            return (Media(type: .photo, localFileName: "temporary-import.jpg"), nil)
        }
        operations.removeFiles = { media, _ in if let media { removed.append(media) } }
        operations.didCommit = { _ in }
        let capture = model(operations)
        capture.startQuickCapture(prefillNote: "cancelled draft")
        capture.cameraPhotos = [SelectedCameraPhoto(image: UIImage())]
        let saving = Task { await capture.savePickedItems(into: f.context) }
        defer { gate.release() }
        for _ in 0..<1_000 where !gate.started { await Task.yield() }
        try #require(gate.started)
        saving.cancel()
        gate.release()
        #expect(await saving.value == false)
        #expect(try ModelContext(f.container).fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(removed == ["temporary-import.jpg"])
        #expect(capture.note == "cancelled draft" && capture.showQuickCapture && !capture.isSaving)
    }
}
