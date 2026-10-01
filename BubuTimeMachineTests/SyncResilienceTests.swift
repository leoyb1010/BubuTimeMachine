import Testing
import Foundation
import SwiftData
@testable import BubuTimeMachine

// MARK: - 同步韧性回归测试
/// 钉两件在真机上很难复现、但一旦错了就长期不被发现的事：
/// ① 断网时的退避曲线（错了只表现为「有点费电」，没人会报）
/// ② 一轮同步的处理上限（没有上限时，首次全家上云会把主线程占几分钟）
struct SyncResilienceTests {

    @Test("没有失败时保持 30 秒基础节奏")
    func baseIntervalWhenHealthy() {
        #expect(SyncBackoff.interval(failures: 0) == 30)
    }

    @Test("连续失败按 2 的幂退避：30 → 60 → 120 → 240 → 480")
    func exponentialGrowth() {
        #expect(SyncBackoff.interval(failures: 1) == 60)
        #expect(SyncBackoff.interval(failures: 2) == 120)
        #expect(SyncBackoff.interval(failures: 3) == 240)
        #expect(SyncBackoff.interval(failures: 4) == 480)
    }

    @Test("退避封顶在 8 分钟——再长会让「服务器修好了」迟迟不被发现")
    func cappedAtEightMinutes() {
        for failures in 5...50 {
            #expect(SyncBackoff.interval(failures: failures) == SyncBackoff.maxInterval)
        }
        #expect(SyncBackoff.maxInterval == 480)
    }

    @Test("退避曲线单调不减，且永远不小于基础间隔")
    func monotonicAndNeverFasterThanBase() {
        var previous = SyncBackoff.interval(failures: 0)
        for failures in 1...20 {
            let current = SyncBackoff.interval(failures: failures)
            #expect(current >= previous)
            #expect(current >= SyncBackoff.baseInterval)
            previous = current
        }
    }

    @Test("一轮同步的推送上限存在且有界")
    func pushBatchIsBounded() async {
        // 无上限时，首次全家上云 / SSD 批量导入后的几千条待推会一次性取回内存并逐条推，
        // 整轮几分钟全程占用主线程。上限必须存在，且不能大到失去意义。
        #expect(SyncEngine.pushBatchCap > 0)
        #expect(SyncEngine.pushBatchCap <= 500)
    }
}

// MARK: - 时光轴卡片文案回归测试
/// v2.10.1 及更早：没有标题的记录会把正文顶上去当标题，下面那行摘要又原样再渲染一次，
/// 同一句话在同一张卡上下重复。这里把规则钉死。
struct TimelineCardTextTests {

    @Test("有标题时用标题，正文作为副文案")
    func titleAndNote() {
        #expect(TimelineCardText.headline(title: "第一次站起来", note: "扶着沙发") == "第一次站起来")
        #expect(TimelineCardText.subtitle(title: "第一次站起来", note: "扶着沙发") == "扶着沙发")
    }

    @Test("没有标题时正文顶上去当标题，且不再重复渲染为副文案")
    func noteBecomesHeadlineOnce() {
        #expect(TimelineCardText.headline(title: nil, note: "今天也很可爱") == "今天也很可爱")
        #expect(TimelineCardText.subtitle(title: nil, note: "今天也很可爱") == nil)
        // 空字符串等价于没有标题
        #expect(TimelineCardText.headline(title: "", note: "今天也很可爱") == "今天也很可爱")
        #expect(TimelineCardText.subtitle(title: "", note: "今天也很可爱") == nil)
    }

    @Test("标题与正文逐字相同时不重复显示")
    func identicalTitleAndNote() {
        #expect(TimelineCardText.headline(title: "布布的笑", note: "布布的笑") == "布布的笑")
        #expect(TimelineCardText.subtitle(title: "布布的笑", note: "布布的笑") == nil)
    }

    @Test("既没有标题也没有正文时回落到「记录此刻」，且没有副文案")
    func emptyEntry() {
        #expect(TimelineCardText.headline(title: nil, note: nil) == "记录此刻")
        #expect(TimelineCardText.subtitle(title: nil, note: nil) == nil)
        #expect(TimelineCardText.headline(title: "", note: "") == "记录此刻")
    }
}

// MARK: - 上传回执跨 await 的数据安全
@MainActor
struct SyncUploadCompletionTests {
    private func context() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SharedModelContainer.schema, configurations: [config])
        return ModelContext(container)
    }

    private func reply(for entry: Entry, note: String, editedAt: Date) -> EntryDTO {
        EntryDTO(id: "audit-entry", localId: entry.id.uuidString,
                 title: nil, note: note, firstPersonNote: nil,
                 happenedAt: entry.happenedAt, locationName: nil, latitude: nil, longitude: nil,
                 authorRole: entry.authorRole, mood: nil, isArchived: false,
                 inStorybook: entry.inStorybook, editedAt: editedAt, createdAt: entry.createdAt)
    }

    @Test("旧上传回执不能把 await 期间的新编辑标为已同步")
    func deferredReplyKeepsNewerLocalEdit() async throws {
        let context = try context()
        let entry = Entry(authorRole: "audit", note: "已发出的旧内容")
        let sentAt = Date(timeIntervalSince1970: 1_000)
        entry.createdAt = sentAt
        entry.editedAt = sentAt
        entry.syncState = .uploading
        context.insert(entry)
        try context.save()
        let localId = entry.id
        let saved = reply(for: entry, note: "已发出的旧内容", editedAt: sentAt)
        let delivery = AsyncStream<EntryDTO>.makeStream()
        let upload = Task { @MainActor in
            for await response in delivery.stream {
                try SyncEngine.completeEntryUpload(response, sent: saved, localId: localId, in: context)
                try context.save()
            }
        }
        // 确认回执尚未送达时发生用户编辑，再恢复异步回执。
        entry.note = "请求期间的新内容"
        entry.editedAt = sentAt.addingTimeInterval(10)
        entry.syncState = .local
        try context.save()
        delivery.continuation.yield(saved)
        delivery.continuation.finish()
        try await upload.value
        #expect(entry.note == "请求期间的新内容")
        #expect(entry.syncState == .local)
        #expect(entry.remoteId == "audit-entry")
        let reopened = ModelContext(context.container)
        #expect(try reopened.fetch(FetchDescriptor<Entry>()).first?.syncState == .local)
    }

    @Test("正文直接绑定尚未标脏时，旧回执也不能确认正在输入的内容")
    func deferredReplyKeepsUnmarkedTyping() async throws {
        let context = try context()
        let entry = Entry(authorRole: "audit", note: "请求发出时的正文")
        let sentAt = Date(timeIntervalSince1970: 1_000)
        entry.createdAt = sentAt
        entry.editedAt = sentAt
        entry.syncState = .uploading
        context.insert(entry)
        try context.save()
        let localId = entry.id
        let sent = reply(for: entry, note: "请求发出时的正文", editedAt: sentAt)
        let delivery = AsyncStream<EntryDTO>.makeStream()
        let upload = Task { @MainActor in
            for await response in delivery.stream {
                try SyncEngine.completeEntryUpload(response, sent: sent, localId: localId, in: context)
                try context.save()
            }
        }
        // 精确模拟 EntryDetailView 的 TextField：仅改 note，尚未点「完成」。
        entry.note = "仍在输入，还没有点完成"
        #expect(entry.syncState == .uploading)
        #expect(entry.editedAt == sentAt)
        delivery.continuation.yield(sent)
        delivery.continuation.finish()
        try await upload.value
        #expect(entry.note == "仍在输入，还没有点完成")
        #expect(entry.syncState == .local)
        #expect((entry.editedAt ?? .distantPast) > sentAt)
        #expect(entry.remoteId == "audit-entry")
        let reopened = ModelContext(context.container)
        let persisted = try reopened.fetch(FetchDescriptor<Entry>()).first
        #expect(persisted?.note == "仍在输入，还没有点完成")
        #expect(persisted?.syncState == .local)
    }

    @Test("更晚的远端编辑仍按原有 LWW 规则收敛")
    func newerRemoteReplyWins() throws {
        let context = try context()
        let entry = Entry(authorRole: "audit", note: "旧内容")
        entry.createdAt = Date(timeIntervalSince1970: 1_000)
        entry.editedAt = entry.createdAt
        entry.syncState = .uploading
        context.insert(entry)
        let sent = reply(for: entry, note: "旧内容", editedAt: entry.createdAt)
        let saved = reply(for: entry, note: "远端新内容", editedAt: entry.createdAt.addingTimeInterval(20))
        try SyncEngine.completeEntryUpload(saved, sent: sent, localId: entry.id, in: context)
        try context.save()
        #expect(entry.note == "远端新内容")
        #expect(entry.syncState == .synced)
    }

    @Test("删除后的媒体收到迟到回执只补墓碑，不重建本地媒体")
    func deferredMediaReplyPersistsDeletion() async throws {
        let context = try context()
        let media = Media(type: .photo, localFileName: nil)
        let localId = media.id
        media.syncState = .uploading
        context.insert(media)
        try context.save()
        let delivery = AsyncStream<String>.makeStream()
        let upload = Task { @MainActor in
            for await remoteId in delivery.stream {
                try SyncEngine.completeMediaUpload(localId: localId, remoteId: remoteId,
                    remoteURL: "https://example.invalid/audit.jpg", in: context)
                try context.save()
            }
        }
        context.delete(media)
        try context.save()
        delivery.continuation.yield("audit-media")
        delivery.continuation.finish()
        try await upload.value
        let reopened = ModelContext(context.container)
        #expect(try reopened.fetchCount(FetchDescriptor<Media>()) == 0)
        let deletions = try reopened.fetch(FetchDescriptor<PendingDeletion>())
        #expect(deletions.count == 1)
        #expect(deletions.first?.collection == "media")
        #expect(deletions.first?.remoteId == "audit-media")
    }

    @Test("删除后的记录收到迟到回执同样保留删除意图")
    func entryDeletionQueuesTombstone() throws {
        let context = try context()
        let entry = Entry(authorRole: "audit", note: "准备删除")
        let saved = reply(for: entry, note: "准备删除", editedAt: entry.createdAt)
        let localId = entry.id
        context.insert(entry)
        try context.save()
        context.delete(entry)
        try context.save()
        try SyncEngine.completeEntryUpload(saved, sent: saved, localId: localId, in: context)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(try context.fetch(FetchDescriptor<PendingDeletion>()).first?.collection == "entries")
    }

    @Test("普通媒体上传回执仍落库并标记同步完成")
    func existingMediaFinishesNormally() throws {
        let context = try context()
        let media = Media(type: .photo, localFileName: nil)
        media.syncState = .uploading
        context.insert(media)
        try SyncEngine.completeMediaUpload(localId: media.id, remoteId: "audit-media",
            remoteURL: "https://example.invalid/audit.jpg", in: context)
        try context.save()
        #expect(media.syncState == .synced)
        #expect(media.remoteId == "audit-media")
        #expect(media.uploadProgress == 1)
        #expect(try context.fetchCount(FetchDescriptor<PendingDeletion>()) == 0)
    }

    @Test("所有可编辑模型都只确认 uploading 状态，不清除新草稿")
    func completionStatePreservesDirtyRecords() {
        #expect(SyncEngine.uploadCompletionState(.uploading) == .synced)
        #expect(SyncEngine.uploadCompletionState(.local) == .local)
        #expect(SyncEngine.uploadCompletionState(.failed) == .failed)
        #expect(SyncEngine.uploadCompletionState(.synced) == .synced)
    }
}

// MARK: - 上传之后、拉取之前的即时编辑
@MainActor
struct EntryImmediateDirtyBindingTests {
    private func uploadedEntry() -> (Entry, EntryDTO) {
        let entry = Entry(authorRole: "audit", note: "已上传的内容")
        let date = Date(timeIntervalSince1970: 1_000)
        entry.createdAt = date
        entry.editedAt = date
        entry.happenedAt = date
        entry.remoteId = "audit-entry"
        entry.syncState = .synced
        let remote = EntryDTO(id: entry.remoteId, localId: entry.id.uuidString,
                              title: nil, note: entry.note, firstPersonNote: nil,
                              happenedAt: date, locationName: nil, latitude: nil, longitude: nil,
                              authorRole: entry.authorRole, mood: nil, isArchived: false,
                              inStorybook: entry.inStorybook, editedAt: date, createdAt: date)
        return (entry, remote)
    }

    @Test("上传已完成，正文下一次输入立即标脏并挡住旧 pull")
    func noteChangedAfterUploadBeforePull() {
        let (entry, remote) = uploadedEntry()
        EntryDetailView.noteBinding(for: entry).wrappedValue = "尚未点击完成的新输入"
        #expect(entry.syncState == .local)
        #expect((entry.editedAt ?? .distantPast) > remote.editedAt!)
        #expect(!SyncEngine.mergeEntryPayload(remote, into: entry))
        #expect(entry.note == "尚未点击完成的新输入")
    }

    @Test("清空正文同样即时标脏，旧远端正文不能复活")
    func clearingNoteIsAnEdit() {
        let (entry, remote) = uploadedEntry()
        EntryDetailView.noteBinding(for: entry).wrappedValue = ""
        #expect(entry.note == nil)
        #expect(entry.syncState == .local)
        #expect(!SyncEngine.mergeEntryPayload(remote, into: entry))
        #expect(entry.note == nil)
    }

    @Test("发生时间和心情的绑定都在 setter 中标脏")
    func dateAndMoodDirtyImmediately() {
        let (entry, remote) = uploadedEntry()
        let newDate = entry.happenedAt.addingTimeInterval(60)
        EntryDetailView.editingBinding(for: entry, \.happenedAt).wrappedValue = newDate
        #expect(entry.syncState == .local)
        #expect(!SyncEngine.mergeEntryPayload(remote, into: entry))
        #expect(entry.happenedAt == newDate)
        entry.syncState = .synced
        let mood = Mood.allCases.first!
        EntryDetailView.editingBinding(for: entry, \.mood).wrappedValue = mood
        #expect(entry.syncState == .local)
        #expect(!SyncEngine.mergeEntryPayload(remote, into: entry))
        #expect(entry.mood == mood)
    }

    @Test("重复绑定值不制造虚假的编辑或时间戳")
    func unchangedBindingDoesNotDirty() {
        let (entry, remote) = uploadedEntry()
        EntryDetailView.noteBinding(for: entry).wrappedValue = entry.note!
        EntryDetailView.editingBinding(for: entry, \.happenedAt).wrappedValue = entry.happenedAt
        EntryDetailView.editingBinding(for: entry, \.mood).wrappedValue = entry.mood
        #expect(entry.syncState == .synced)
        #expect(entry.editedAt == remote.editedAt)
    }
}

// MARK: - 文件流必须有完成回执
@MainActor
struct SyncUploadStreamTests {
    @Test("空流或只有进度的流结束不算上传成功", arguments: [false, true])
    func missingReceiptThrows(includeProgress: Bool) async {
        let stream = AsyncThrowingStream<UploadEvent, Error>.makeStream()
        if includeProgress { stream.continuation.yield(.progress(1)) }
        stream.continuation.finish()
        do {
            _ = try await SyncEngine.consumeUpload(stream.stream, onProgress: { _ in })
            Issue.record("缺少完成回执却被当作成功")
        } catch {
            guard case APIError.network = error else {
                Issue.record("应报告可重试的网络错误，实际为 \(error)")
                return
            }
        }
    }

    @Test("合成上传挂起后发送完成回执，才允许返回身份与 URL")
    func suspendedStreamCompletes() async throws {
        let stream = AsyncThrowingStream<UploadEvent, Error>.makeStream()
        let progressSeen = AsyncStream<Double>.makeStream()
        var progress = progressSeen.stream.makeAsyncIterator()
        let consumer = Task { @MainActor in
            try await SyncEngine.consumeUpload(stream.stream, onProgress: { progressSeen.continuation.yield($0) })
        }
        stream.continuation.yield(.progress(0.5))
        #expect(await progress.next() == 0.5)
        stream.continuation.yield(.completed(remoteId: "audit-file", url: "https://example.invalid/file.bin"))
        stream.continuation.finish()
        let receipt = try await consumer.value
        #expect(receipt.remoteId == "audit-file")
        #expect(receipt.remoteURL == "https://example.invalid/file.bin")
        progressSeen.continuation.finish()
    }

    @Test("收到回执后流仍抛错，不把失败流确认成成功")
    func failureAfterReceiptStillThrows() async {
        let stream = AsyncThrowingStream<UploadEvent, Error>.makeStream()
        stream.continuation.yield(.completed(remoteId: "audit-file", url: "https://example.invalid/file.bin"))
        stream.continuation.finish(throwing: APIError.network("synthetic failure"))
        do {
            _ = try await SyncEngine.consumeUpload(stream.stream, onProgress: { _ in })
            Issue.record("抛错流被当作成功")
        } catch {}
    }

    @Test("取消导致流自然结束时仍抛取消错误，不能标 synced")
    func cancellationDoesNotAcknowledgeUpload() async {
        let stream = AsyncThrowingStream<UploadEvent, Error>.makeStream()
        let progressSeen = AsyncStream<Void>.makeStream()
        var progress = progressSeen.stream.makeAsyncIterator()
        let consumer = Task { @MainActor in
            try await SyncEngine.consumeUpload(stream.stream, onProgress: { _ in progressSeen.continuation.yield(()) })
        }
        stream.continuation.yield(.progress(0.5))
        _ = await progress.next()
        consumer.cancel()
        stream.continuation.finish()
        do {
            _ = try await consumer.value
            Issue.record("取消上传被当作成功")
        } catch {
            #expect(error is CancellationError)
        }
        progressSeen.continuation.finish()
    }
}

// MARK: - 前台 / 后台 / 强制补传共用同一许可
@MainActor
struct SyncRunGateTests {
    @Test("前台挂起时，后台同步与强制补传（包括标脏）不能重入")
    func serializesAllEntryPoints() async {
        let gate = SyncRunGate()
        let entered = AsyncStream<Int>.makeStream()
        var events = entered.stream.makeAsyncIterator()
        let release = AsyncStream<Void>.makeStream()
        let attempts = AsyncStream<Int>.makeStream()
        var attempted = attempts.stream.makeAsyncIterator()
        var active = 0
        var maximumActive = 0
        var didMarkForReupload = false
        let foreground = Task { @MainActor in
            await gate.withPermit {
                active += 1; maximumActive = max(maximumActive, active)
                entered.continuation.yield(1)
                for await _ in release.stream { break }
                active -= 1
            }
        }
        #expect(await events.next() == 1)
        let background = Task { @MainActor in
            attempts.continuation.yield(2)
            await gate.withPermit {
                active += 1; maximumActive = max(maximumActive, active)
                entered.continuation.yield(2)
                active -= 1
            }
        }
        let forced = Task { @MainActor in
            attempts.continuation.yield(3)
            await gate.withPermit {
                didMarkForReupload = true
                active += 1; maximumActive = max(maximumActive, active)
                entered.continuation.yield(3)
                active -= 1
            }
        }
        _ = await attempted.next()
        _ = await attempted.next()
        #expect(active == 1)
        #expect(!didMarkForReupload)
        release.continuation.finish()
        _ = await foreground.value
        _ = await background.value
        _ = await forced.value
        #expect(maximumActive == 1)
        #expect(didMarkForReupload)
        #expect(active == 0)
        entered.continuation.finish()
        attempts.continuation.finish()
    }

    @Test("取消排队的 BGTask 立即退出，不取消占用许可的前台轮次")
    func cancelledWaiterDoesNotAffectOwnerOrLeakPermit() async {
        let gate = SyncRunGate()
        let entered = AsyncStream<Void>.makeStream()
        var events = entered.stream.makeAsyncIterator()
        let release = AsyncStream<Void>.makeStream()
        let owner = Task { @MainActor in
            await gate.withPermit {
                entered.continuation.yield(())
                for await _ in release.stream { break }
                return "owner"
            }
        }
        _ = await events.next()
        let queued = Task { @MainActor in
            entered.continuation.yield(())
            return await gate.withPermit { "must-not-run" }
        }
        _ = await events.next()
        queued.cancel()
        #expect(await queued.value == nil)
        #expect(!owner.isCancelled)
        release.continuation.finish()
        #expect(await owner.value == "owner")
        #expect(await gate.withPermit { "next" } == "next")
        entered.continuation.finish()
    }
}

// MARK: - 迟到下载结果不得写回已删除 / 被替换的模型
@MainActor
struct SyncDownloadCompletionTests {
    private func context() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SharedModelContainer.schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func media(in context: ModelContext) throws -> Media {
        let media = Media(type: .photo, localFileName: nil)
        media.remoteId = "audit-media"
        media.remoteURL = "https://example.invalid/original.bin"
        media.remoteThumbURL = "https://example.invalid/preview.jpg"
        media.syncState = .synced
        context.insert(media)
        try context.save()
        return media
    }

    private func outcome(for media: Media, store: MediaStore, thumbnailOnly: Bool = false) throws -> SyncEngine.DownloadOutcome {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("synthetic download".utf8).write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let name = thumbnailOnly
            ? try store.importThumbnail(from: temporary)
            : try store.importFile(from: temporary, preferredExtension: "bin")
        let thumb = thumbnailOnly ? nil : try store.importThumbnail(from: temporary)
        return SyncEngine.DownloadOutcome(snapshot: SyncEngine.MediaDownloadSnapshot(media), fileName: name,
                                          thumbName: thumb, assignAsThumbnailOnly: thumbnailOnly)
    }

    @Test("媒体在下载挂起期间已删除：结果不重建模型并清理新下载文件")
    func lateDownloadAfterDeletionIsDiscarded() async throws {
        let context = try context()
        let store = MediaStore()
        let media = try media(in: context)
        let result = try outcome(for: media, store: store)
        let delivery = AsyncStream<SyncEngine.DownloadOutcome>.makeStream()
        let download = Task { @MainActor in
            for await result in delivery.stream {
                #expect(try SyncEngine.completeMediaDownload(result, in: context, store: store) == false)
                try context.save()
            }
        }
        context.delete(media)
        try context.save()
        delivery.continuation.yield(result)
        delivery.continuation.finish()
        try await download.value
        #expect(try context.fetchCount(FetchDescriptor<Media>()) == 0)
        #expect(!store.fileExists(forMedia: result.fileName!))
        #expect(!FileManager.default.fileExists(atPath: store.thumbnailURL(for: result.thumbName!).path))
    }

    @Test("资源身份或目标槽在 await 期间改变时丢弃旧下载", arguments: ["remoteURL", "remoteId", "remoteThumbURL", "localFileName", "thumbnailFileName", "syncState"])
    func changedDestinationRejectsStaleDownload(field: String) async throws {
        let context = try context()
        let store = MediaStore()
        let media = try media(in: context)
        let result = try outcome(for: media, store: store)
        let delivery = AsyncStream<SyncEngine.DownloadOutcome>.makeStream()
        let download = Task { @MainActor in
            for await result in delivery.stream {
                #expect(try SyncEngine.completeMediaDownload(result, in: context, store: store) == false)
                try context.save()
            }
        }
        switch field {
        case "remoteURL": media.remoteURL = "https://example.invalid/new-original.bin"
        case "remoteId": media.remoteId = "new-audit-media"
        case "remoteThumbURL": media.remoteThumbURL = "https://example.invalid/new-preview.jpg"
        case "localFileName": media.localFileName = "user-replacement.bin"
        case "thumbnailFileName": media.thumbnailFileName = "user-replacement.jpg"
        default: media.syncState = .local
        }
        try context.save()
        delivery.continuation.yield(result)
        delivery.continuation.finish()
        try await download.value
        #expect(!store.fileExists(forMedia: result.fileName!))
        #expect(!FileManager.default.fileExists(atPath: store.thumbnailURL(for: result.thumbName!).path))
        #expect(media.localFileName == (field == "localFileName" ? "user-replacement.bin" : nil))
        #expect(media.thumbnailFileName == (field == "thumbnailFileName" ? "user-replacement.jpg" : nil))
    }

    @Test("未变化的原片和预览图下载按正确目录落库", arguments: [false, true])
    func unchangedDownloadIsAccepted(thumbnailOnly: Bool) throws {
        let context = try context()
        let store = MediaStore()
        let media = try media(in: context)
        let result = try outcome(for: media, store: store, thumbnailOnly: thumbnailOnly)
        defer {
            store.deleteLocalFiles(media: thumbnailOnly ? nil : result.fileName,
                                   thumbnail: thumbnailOnly ? result.fileName : result.thumbName)
        }
        #expect(try SyncEngine.completeMediaDownload(result, in: context, store: store))
        try context.save()
        #expect(media.localFileName == (thumbnailOnly ? nil : result.fileName))
        #expect(media.thumbnailFileName == (thumbnailOnly ? result.fileName : result.thumbName))
        let reopened = ModelContext(context.container)
        let persisted = try reopened.fetch(FetchDescriptor<Media>()).first
        #expect(persisted?.localFileName == media.localFileName)
        #expect(persisted?.thumbnailFileName == media.thumbnailFileName)
    }
}

@MainActor
struct SyncClientReplacementTests {
    @Test("换客户端使后台/强制轮次和排队请求失效，旧请求返回后不能应用结果")
    func invalidationCancelsOwnedWorkAndQueuedRequests() async {
        let gate = SyncRunGate()
        let entered = AsyncStream<Void>.makeStream()
        var events = entered.stream.makeAsyncIterator()
        var resumeOldRequest: CheckedContinuation<Void, Never>?
        var appliedOldResult = false
        var oldOperationWasCancelled = false
        var startedNewRun = false
        let oldRun = Task { @MainActor in
            await gate.withPermit {
                // 模拟不理会任务取消、仍会迟到返回的网络实现。
                await withCheckedContinuation { continuation in
                    resumeOldRequest = continuation
                    entered.continuation.yield(())
                }
                oldOperationWasCancelled = Task.isCancelled
                if !Task.isCancelled { appliedOldResult = true }
                return "old"
            }
        }
        _ = await events.next()
        let queued = Task { @MainActor in
            entered.continuation.yield(())
            return await gate.withPermit { "obsolete queued request" }
        }
        _ = await events.next()
        gate.invalidate()
        #expect(await queued.value == nil)
        let newRun = Task { @MainActor in
            entered.continuation.yield(())
            return await gate.withPermit {
                startedNewRun = true
                return "new"
            }
        }
        _ = await events.next()
        #expect(!startedNewRun)
        resumeOldRequest?.resume()
        #expect(await oldRun.value == nil)
        #expect(await newRun.value == "new")
        #expect(oldOperationWasCancelled)
        #expect(!appliedOldResult)
        entered.continuation.finish()
    }
}

// MARK: - 已成功但迟到的创建回执：取消不撤销删除补偿，也不跨同步目标入队
@MainActor
struct SyncCancelledCreationReceiptTests {
    private func context() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SharedModelContainer.schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test("取消或换客户端后，迟到创建回执仅在同账号同服务器补持久化墓碑",
          arguments: ["cancel", "same-scope-replacement", "different-server", "different-account"])
    func cancelledCreationPreservesScopedDeletion(change: String) async throws {
        let context = try context()
        let entry = Entry(authorRole: "audit", note: "synthetic pending creation")
        let localId = entry.id
        entry.syncState = .uploading
        context.insert(entry)
        try context.save()
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == localId })
        let requestScope = "https://old.example.invalid|audit@example.invalid"
        var currentScope = requestScope
        let gate = SyncRunGate()
        let entered = AsyncStream<Void>.makeStream()
        var events = entered.stream.makeAsyncIterator()
        var resumeRequest: CheckedContinuation<String, Never>?
        var observedCancellation = false
        var preservedDeletion = false
        let upload = Task { @MainActor in
            await gate.withPermit {
                // 已提交的服务器请求可能不理会取消；continuation 可精确控制迟到成功回执。
                let remoteId = await withCheckedContinuation { continuation in
                    resumeRequest = continuation
                    entered.continuation.yield(())
                }
                observedCancellation = Task.isCancelled
                do {
                    preservedDeletion = try SyncEngine.persistDeletedUploadReceipt(remoteId,
                        collection: "entries", requestScope: requestScope, currentScope: currentScope,
                        descriptor: descriptor, in: context)
                } catch {
                    Issue.record("删除补偿落盘失败：\(error)")
                }
                return "receipt returned"
            }
        }
        _ = await events.next()
        #expect(entry.remoteId == nil)
        PendingDeletion.enqueue(collection: "entries", remoteId: entry.remoteId, in: context)
        context.delete(entry)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<PendingDeletion>()) == 0)

        switch change {
        case "cancel": upload.cancel()
        case "different-server":
            currentScope = "https://new.example.invalid|audit@example.invalid"
            gate.invalidate()
        case "different-account":
            currentScope = "https://old.example.invalid|other@example.invalid"
            gate.invalidate()
        default: gate.invalidate()
        }
        resumeRequest?.resume(returning: "audit-created-entry")
        let result = await upload.value
        #expect(result == nil)
        #expect(observedCancellation)
        let sameScope = currentScope == requestScope
        #expect(preservedDeletion == sameScope)
        let reopened = ModelContext(context.container)
        #expect(try reopened.fetchCount(descriptor) == 0)
        let deletions = try reopened.fetch(FetchDescriptor<PendingDeletion>())
        #expect(deletions.count == (sameScope ? 1 : 0))
        if sameScope {
            #expect(deletions.first?.collection == "entries")
            #expect(deletions.first?.remoteId == "audit-created-entry")
        }
        entered.continuation.finish()
    }

    @Test("取消回执补偿不确认仍存在的新草稿，也不重复新增墓碑")
    func existingDraftIsUntouchedAndDeletedReceiptIsIdempotent() throws {
        let context = try context()
        let entry = Entry(authorRole: "audit", note: "newer local draft")
        let localId = entry.id
        entry.syncState = .local
        context.insert(entry)
        try context.save()
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == localId })
        let didSettle = try SyncEngine.persistDeletedUploadReceipt("audit-created-entry", collection: "entries",
            requestScope: "same", currentScope: "same", descriptor: descriptor, in: context)
        #expect(!didSettle)
        #expect(entry.note == "newer local draft")
        #expect(entry.syncState == .local)
        #expect(entry.remoteId == nil)
        #expect(try context.fetchCount(FetchDescriptor<PendingDeletion>()) == 0)
        context.delete(entry)
        try context.save()
        for _ in 0..<2 {
            let didPreserve = try SyncEngine.persistDeletedUploadReceipt("audit-created-entry", collection: "entries",
                requestScope: "same", currentScope: "same", descriptor: descriptor, in: context)
            #expect(didPreserve)
        }
        let reopened = ModelContext(context.container)
        #expect(try reopened.fetchCount(FetchDescriptor<PendingDeletion>()) == 1)
    }

    @Test("媒体流已返回身份后取消，保留同目标删除补偿但仍不确认上传", arguments: [false, true])
    func observedStreamReceiptSurvivesCancellation(changeScope: Bool) async throws {
        let context = try context()
        let media = Media(type: .photo, localFileName: nil)
        let localId = media.id
        media.syncState = .uploading
        context.insert(media)
        try context.save()
        let descriptor = FetchDescriptor<Media>(predicate: #Predicate { $0.id == localId })
        let requestScope = "old-server|audit"
        var currentScope = requestScope
        var observedRemoteId: String?
        let stream = AsyncThrowingStream<UploadEvent, Error>.makeStream()
        let receipts = AsyncStream<Void>.makeStream()
        var received = receipts.stream.makeAsyncIterator()
        let upload = Task { @MainActor in
            do {
                _ = try await SyncEngine.consumeUpload(stream.stream, onProgress: { _ in }, onReceipt: { remoteId, _ in
                    observedRemoteId = remoteId
                    receipts.continuation.yield(())
                })
                Issue.record("取消的媒体流不应返回成功")
            } catch {
                #expect(error is CancellationError)
                if let observedRemoteId {
                    _ = try SyncEngine.persistDeletedUploadReceipt(observedRemoteId, collection: "media",
                        requestScope: requestScope, currentScope: currentScope, descriptor: descriptor, in: context)
                }
            }
        }
        stream.continuation.yield(.completed(remoteId: "audit-created-media", url: "https://example.invalid/file.bin"))
        _ = await received.next()
        context.delete(media)
        try context.save()
        if changeScope { currentScope = "new-server|audit" }
        upload.cancel()
        stream.continuation.finish()
        try await upload.value
        #expect(observedRemoteId == "audit-created-media")
        let reopened = ModelContext(context.container)
        #expect(try reopened.fetchCount(descriptor) == 0)
        let deletions = try reopened.fetch(FetchDescriptor<PendingDeletion>())
        #expect(deletions.count == (changeScope ? 0 : 1))
        if !changeScope { #expect(deletions.first?.remoteId == "audit-created-media") }
        receipts.continuation.finish()
    }
}

@MainActor
struct SyncAttachmentDownloadTests {
    private func context() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SharedModelContainer.schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func assertDeletedDownloadIsDiscarded<Model: PersistentModel>(
        _ model: Model, in context: ModelContext, descriptor: FetchDescriptor<Model>,
        localFile: ReferenceWritableKeyPath<Model, String?>) async throws {
        context.insert(model)
        try context.save()
        let store = MediaStore()
        let fileName = try store.savePhoto(Data("synthetic attachment".utf8), preferredExtension: "bin")
        let delivery = AsyncStream<String>.makeStream()
        let download = Task { @MainActor in
            for await fileName in delivery.stream {
                do {
                    let accepted = try SyncEngine.completeFileDownload(fileName, in: context, store: store,
                        descriptor: descriptor, localFile: localFile, isCurrent: { _ in true })
                    #expect(!accepted)
                } catch {
                    Issue.record("迟到附件下载验证失败：\(error)")
                }
            }
        }
        context.delete(model)
        try context.save()
        delivery.continuation.yield(fileName)
        delivery.continuation.finish()
        await download.value
        #expect(try context.fetchCount(descriptor) == 0)
        #expect(!store.fileExists(forMedia: fileName))
    }

    @Test("语音、家人补充、成长之声和胶囊被删除后，迟到文件都不写回旧模型")
    func deletedAttachmentsRejectLateFiles() async throws {
        let context = try context()
        let note = VoiceNote(localFileName: nil, durationSeconds: 1, authorRole: "audit")
        let noteId = note.id
        try await assertDeletedDownloadIsDiscarded(note, in: context,
            descriptor: FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.id == noteId }), localFile: \.localFileName)
        let comment = BubuTimeMachine.Comment(authorRole: "audit")
        let commentId = comment.id
        try await assertDeletedDownloadIsDiscarded(comment, in: context,
            descriptor: FetchDescriptor<BubuTimeMachine.Comment>(predicate: #Predicate { $0.id == commentId }), localFile: \.voiceFileName)
        let memo = VoiceMemo(kind: .childVoice)
        let memoId = memo.id
        try await assertDeletedDownloadIsDiscarded(memo, in: context,
            descriptor: FetchDescriptor<VoiceMemo>(predicate: #Predicate { $0.id == memoId }), localFile: \.localFileName)
        let capsule = TimeCapsule(title: "audit", fromRole: "audit", unlockAt: .distantFuture)
        let capsuleId = capsule.id
        try await assertDeletedDownloadIsDiscarded(capsule, in: context,
            descriptor: FetchDescriptor<TimeCapsule>(predicate: #Predicate { $0.id == capsuleId }), localFile: \.encryptedBlobFileName)
    }

    @Test("下载中更换头像不被旧文件覆盖，并清理被丢弃的下载")
    func replacedAvatarSurvivesLateFile() async throws {
        let context = try context()
        let store = MediaStore()
        let profile = ChildProfile(name: "audit", birthday: Date(timeIntervalSince1970: 0))
        let localId = profile.id
        let oldURL = "https://example.invalid/old-avatar.jpg"
        profile.avatarRemoteURL = oldURL
        context.insert(profile)
        try context.save()
        let staleFile = try store.savePhoto(Data("old avatar".utf8), preferredExtension: "bin")
        let chosenFile = try store.savePhoto(Data("new avatar".utf8), preferredExtension: "bin")
        defer { store.deleteLocalFiles(media: chosenFile) }
        let delivery = AsyncStream<String>.makeStream()
        let download = Task { @MainActor in
            for await name in delivery.stream {
                do {
                    let accepted = try SyncEngine.completeFileDownload(name, in: context, store: store,
                        descriptor: FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.id == localId }),
                        localFile: \.avatarMediaFileName, isCurrent: { $0.avatarRemoteURL == oldURL })
                    #expect(!accepted)
                } catch {
                    Issue.record("迟到头像下载验证失败：\(error)")
                }
            }
        }
        profile.avatarMediaFileName = chosenFile
        profile.avatarRemoteURL = nil
        profile.syncState = .local
        delivery.continuation.yield(staleFile)
        delivery.continuation.finish()
        await download.value
        #expect(profile.avatarMediaFileName == chosenFile)
        #expect(store.fileExists(forMedia: chosenFile))
        #expect(!store.fileExists(forMedia: staleFile))
    }

    @Test("原有缺失文件槽仍匹配时可以恢复胶囊文件；远端身份变更则拒绝")
    func attachmentIdentityAndMissingFileRecovery() throws {
        let context = try context()
        let store = MediaStore()
        let capsule = TimeCapsule(title: "audit", fromRole: "audit", unlockAt: .distantFuture)
        let localId = capsule.id
        capsule.remoteId = "old-remote"
        capsule.encryptedBlobFileName = "missing-file.capsule"
        context.insert(capsule)
        try context.save()
        let staleFile = try store.savePhoto(Data("stale".utf8), preferredExtension: "bin")
        capsule.remoteId = "new-remote"
        let descriptor = FetchDescriptor<TimeCapsule>(predicate: #Predicate { $0.id == localId })
        #expect(try SyncEngine.completeFileDownload(staleFile, in: context, store: store,
            descriptor: descriptor, localFile: \.encryptedBlobFileName, expectedFileName: "missing-file.capsule",
            isCurrent: { $0.remoteId == "old-remote" }) == false)
        #expect(!store.fileExists(forMedia: staleFile))
        let currentFile = try store.savePhoto(Data("current".utf8), preferredExtension: "bin")
        defer { store.deleteLocalFiles(media: currentFile) }
        #expect(try SyncEngine.completeFileDownload(currentFile, in: context, store: store,
            descriptor: descriptor, localFile: \.encryptedBlobFileName, expectedFileName: "missing-file.capsule",
            isCurrent: { $0.remoteId == "new-remote" }))
        #expect(capsule.encryptedBlobFileName == currentFile)
    }
}
