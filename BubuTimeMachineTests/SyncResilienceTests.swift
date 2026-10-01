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
                 editedAt: editedAt, createdAt: entry.createdAt)
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
                try SyncEngine.completeEntryUpload(response, localId: localId, in: context)
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

    @Test("更晚的远端编辑仍按原有 LWW 规则收敛")
    func newerRemoteReplyWins() throws {
        let context = try context()
        let entry = Entry(authorRole: "audit", note: "旧内容")
        entry.createdAt = Date(timeIntervalSince1970: 1_000)
        entry.editedAt = entry.createdAt
        entry.syncState = .uploading
        context.insert(entry)
        let saved = reply(for: entry, note: "远端新内容", editedAt: entry.createdAt.addingTimeInterval(20))
        try SyncEngine.completeEntryUpload(saved, localId: entry.id, in: context)
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
        try SyncEngine.completeEntryUpload(saved, localId: localId, in: context)
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
