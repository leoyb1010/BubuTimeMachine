import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

/// 2.27 · T7 同步与数据安全：档案唯一选择、编辑时间冲突、恢复重传、失败条目、轮询节流、草稿落盘。
@MainActor
struct Sync2_27Tests {

    private func memoryContext() throws -> ModelContext {
        let container = try ModelContainer(for: SharedModelContainer.schema,
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func scratchLedger() -> SyncLedger {
        SyncLedger(defaults: UserDefaults(suiteName: "t7-ledger-\(UUID().uuidString)")!)
    }

    // MARK: D9-01 布布档案唯一选择

    @Test("多份档案：家长固定的那份优先，否则取最早创建的，与取回顺序无关")
    func canonicalProfileIsDeterministic() {
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        let older = ChildProfile(name: "布布", birthday: base)
        older.createdAt = base
        let newer = ChildProfile(name: "布布", birthday: base.addingTimeInterval(86_400 * 30))
        newer.createdAt = base.addingTimeInterval(3_600)
        let newest = ChildProfile(name: "布布", birthday: base.addingTimeInterval(86_400 * 60))
        newest.createdAt = base.addingTimeInterval(7_200)

        for order in [[older, newer, newest], [newest, older, newer], [newer, newest, older]] {
            #expect(ChildProfile.canonical(from: order, preferredID: nil) === older)
            #expect(ChildProfile.canonical(from: order, preferredID: newest.id) === newest)
        }
        // 固定的那份已被删：回到最早的一份，而不是随机
        #expect(ChildProfile.canonical(from: [newer, newest, older], preferredID: UUID()) === older)
    }

    @Test("同一创建时间按 id 排序打破平局")
    func canonicalProfileTieBreaksByID() {
        let at = Date(timeIntervalSince1970: 1_780_000_000)
        let a = ChildProfile(name: "A", birthday: at); a.createdAt = at
        let b = ChildProfile(name: "B", birthday: at); b.createdAt = at
        let expected = a.id.uuidString < b.id.uuidString ? a : b
        #expect(ChildProfile.canonical(from: [a, b], preferredID: nil) === expected)
        #expect(ChildProfile.canonical(from: [b, a], preferredID: nil) === expected)
    }

    @Test("从库里选：只自动固定已在服务器上的档案，本机临时档案不固定")
    func canonicalInContextPinsOnlySyncedProfile() throws {
        let saved = SharedDefaults.canonicalChildProfileID
        defer { SharedDefaults.canonicalChildProfileID = saved }
        SharedDefaults.canonicalChildProfileID = nil
        let context = try memoryContext()
        let local = ChildProfile(name: "布布", birthday: .now)
        local.createdAt = Date(timeIntervalSince1970: 100)
        context.insert(local)
        try context.save()
        #expect(ChildProfile.canonical(in: context) === local)
        #expect(SharedDefaults.canonicalChildProfileID == nil)

        local.remoteId = "r1"
        try context.save()
        #expect(ChildProfile.canonical(in: context) === local)
        #expect(SharedDefaults.canonicalChildProfileID == local.id)

        // 之后出现一份更早的档案也不会让页面悄悄换人
        let earlier = ChildProfile(name: "布布", birthday: .distantPast)
        earlier.createdAt = Date(timeIntervalSince1970: 1)
        context.insert(earlier)
        try context.save()
        #expect(ChildProfile.canonical(in: context) === local)
    }

    // MARK: D9-02 编辑时间 / 恢复重传

    @Test("保存时只给「刚改过（.local）」的对象记编辑时间；重传标脏不算编辑")
    func ledgerStampsOnlyUserEdits() throws {
        let context = try memoryContext()
        let ledger = scratchLedger()
        let edited = HealthRecord(kind: .symptom, title: "发烧")
        let synced = HealthRecord(kind: .meal, title: "午饭")
        synced.syncState = .synced
        context.insert(edited)
        context.insert(synced)
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        ledger.recordEdits(in: context, at: at)
        #expect(ledger.editedAt(SyncLedger.key("healthrecords", edited.id)) == at)
        #expect(ledger.editedAt(SyncLedger.key("healthrecords", synced.id)) == nil)
        try context.save()

        synced.syncState = .local
        ledger.suppressEditStamps = true
        ledger.recordEdits(in: context, at: at.addingTimeInterval(60))
        ledger.suppressEditStamps = false
        #expect(ledger.editedAt(SyncLedger.key("healthrecords", synced.id)) == nil)

        ledger.clearAfterPush(SyncLedger.key("healthrecords", edited.id))
        #expect(ledger.editedAt(SyncLedger.key("healthrecords", edited.id)) == nil)
    }

    @Test("回执比较：远端编辑更新才采用远端；恢复模式下服务器带回的不是本次写入就采用")
    func remoteVersionComparison() {
        let sent = Date(timeIntervalSince1970: 1_790_000_000.4567)
        // PATCH 回执：毫秒截断后的自己
        let echoed = Date(timeIntervalSince1970: 1_790_000_000.456)
        #expect(!SyncEngine.remoteVersionWasKept(sent: sent, returned: echoed, createOnly: false))
        #expect(!SyncEngine.remoteVersionWasKept(sent: sent, returned: nil, createOnly: false))
        #expect(SyncEngine.remoteVersionWasKept(sent: sent, returned: sent.addingTimeInterval(30), createOnly: false))
        // 旧推送盖不掉家人新编辑；但更旧的远端会被本次更新覆盖
        #expect(!SyncEngine.remoteVersionWasKept(sent: sent, returned: sent.addingTimeInterval(-30), createOnly: false))
        // 恢复模式：服务器已有（无论新旧）都以服务器为准
        #expect(SyncEngine.remoteVersionWasKept(sent: sent, returned: sent.addingTimeInterval(-30), createOnly: true))
        #expect(!SyncEngine.remoteVersionWasKept(sent: sent, returned: echoed, createOnly: true))
    }

    @Test("恢复重传的记录回执：采用服务器版本，等待期间用户又改了则保留本机改动")
    func recoveredEntryAdoptsServerVersion() throws {
        let context = try memoryContext()
        let entry = Entry(happenedAt: .now, authorRole: "papa", note: "本机旧副本")
        entry.syncState = .uploading
        context.insert(entry)
        try context.save()
        let sent = EntryDTO(id: nil, localId: entry.id.uuidString, familyId: nil, authorUserId: nil,
                            title: entry.title, note: entry.note, firstPersonNote: entry.firstPersonNote,
                            happenedAt: entry.happenedAt, locationName: nil, latitude: nil, longitude: nil,
                            authorRole: entry.authorRole, mood: nil, isArchived: false, inStorybook: entry.inStorybook,
                            editedAt: entry.editedAt, createdAt: entry.createdAt, createOnly: true)
        var server = sent
        server.id = "remote-1"
        server.note = "妈妈后来改的新内容"
        server.editedAt = Date(timeIntervalSince1970: 1_790_000_000)
        try SyncEngine.completeRecoveredEntryUpload(server, sent: sent, localId: entry.id, in: context)
        #expect(entry.note == "妈妈后来改的新内容")
        #expect(entry.syncState == .synced)
        #expect(entry.remoteId == "remote-1")

        let edited = Entry(happenedAt: .now, authorRole: "papa", note: "原文")
        context.insert(edited)
        var sent2 = sent
        sent2.localId = edited.id.uuidString
        sent2.note = "原文"; sent2.happenedAt = edited.happenedAt; sent2.createdAt = edited.createdAt
        sent2.inStorybook = edited.inStorybook
        edited.note = "等待期间又改了"
        try SyncEngine.completeRecoveredEntryUpload(server, sent: sent2, localId: edited.id, in: context)
        #expect(edited.note == "等待期间又改了")
        #expect(edited.syncState == .local)
    }

    @Test("唯一索引冲突识别（POST 超时重发）")
    func duplicateLocalIdDetection() {
        let body = #"{"code":400,"message":"Failed to create record.","data":{"localId":{"code":"validation_not_unique"}}}"#
        #expect(PocketBaseClient.isDuplicateLocalId(.server(400, body)))
        #expect(!PocketBaseClient.isDuplicateLocalId(.server(400, "bad request")))
        #expect(!PocketBaseClient.isDuplicateLocalId(.server(500, body)))
    }

    // MARK: D9-03 失败条目

    @Test("文件丢失立即进「需要处理」；服务器单条拒收连续 3 轮才进；重试/编辑可移出")
    func attentionLedgerLifecycle() throws {
        let ledger = scratchLedger()
        let missing = UUID()
        #expect(ledger.noteFailure(collection: "media", id: missing, label: "一张照片", reason: "本地文件缺失", immediate: true))
        #expect(ledger.excludedIDs(for: "media") == [missing])

        let rejected = UUID()
        #expect(!ledger.noteFailure(collection: "healthrecords", id: rejected, label: "健康记录", reason: "拒收", immediate: false))
        #expect(!ledger.noteFailure(collection: "healthrecords", id: rejected, label: "健康记录", reason: "拒收", immediate: false))
        #expect(ledger.noteFailure(collection: "healthrecords", id: rejected, label: "健康记录", reason: "拒收", immediate: false))
        #expect(ledger.excludedCount == 2)

        ledger.resolveAttention(SyncLedger.key("media", missing))
        #expect(ledger.excludedIDs(for: "media").isEmpty)

        ledger.skipAttention(SyncLedger.key("healthrecords", rejected))
        #expect(ledger.attentionItems.first?.skipped == true)
        #expect(ledger.excludedIDs(for: "healthrecords") == [rejected])   // 放弃后仍不排队

        // 用户再次编辑这条（标 .local 并保存）→ 自动回到队列
        let context = try memoryContext()
        let record = HealthRecord(kind: .meal, title: "x")
        record.id = rejected
        context.insert(record)
        ledger.recordEdits(in: context)
        #expect(ledger.excludedIDs(for: "healthrecords").isEmpty)
    }

    @Test("永久失败分类：文件丢失与单条 4xx 是永久的，网络/账号/限流不是")
    func failureClassification() {
        #expect(SyncEngine.isHardLocalFailure(APIError.network("本地文件不见了")))
        #expect(!SyncEngine.isHardLocalFailure(APIError.network("timeout")))
        #expect(SyncEngine.isPermanentItemFailure(APIError.server(400, "x"), item: "健康记录"))
        #expect(SyncEngine.isPermanentItemFailure(APIError.fileTooLarge(bytes: 10, limit: 1), item: "媒体"))
        #expect(!SyncEngine.isPermanentItemFailure(APIError.server(429, "x"), item: "健康记录"))
        #expect(!SyncEngine.isPermanentItemFailure(APIError.server(503, "x"), item: "健康记录"))
        #expect(!SyncEngine.isPermanentItemFailure(APIError.unauthorized, item: "健康记录"))
        #expect(!SyncEngine.isPermanentItemFailure(APIError.server(404, "x"), item: "疫苗记录"))
    }

    @Test("被跳过的远端删除标记留账，可替换与清空")
    func deferredTombstones() {
        let ledger = scratchLedger()
        ledger.deferTombstones(collection: "entries", localIds: ["a", "b"])
        ledger.deferTombstones(collection: "entries", localIds: ["b", "c"])
        #expect(ledger.deferredTombstones()["entries"] == ["a", "b", "c"])
        ledger.replaceDeferredTombstones(collection: "entries", localIds: ["c"])
        #expect(ledger.deferredTombstones()["entries"] == ["c"])
        ledger.replaceDeferredTombstones(collection: "entries", localIds: [])
        #expect(ledger.deferredTombstones()["entries"] == nil)
    }

    // MARK: D4-04 / D4-05 轮询与小组件

    @Test("SSE 在线时轮询退到 5 分钟兜底，断开回到 30 秒；失败退避仍生效")
    func realtimeAwarePolling() {
        #expect(SyncBackoff.interval(failures: 0, realtimeConnected: false) == 30)
        #expect(SyncBackoff.interval(failures: 0, realtimeConnected: true) == SyncBackoff.realtimeSafetyInterval)
        #expect(SyncBackoff.interval(failures: 4, realtimeConnected: true) == 480)
        #expect(SyncBackoff.interval(failures: 2, realtimeConnected: false) == 120)
    }

    @Test("小组件快照只比内容不比生成时间")
    func widgetSnapshotContentEquality() {
        let a = SharedWidgetSnapshot(name: "布布", birthday: Date(timeIntervalSince1970: 0), updatedAt: .now)
        var b = a
        b.updatedAt = a.updatedAt.addingTimeInterval(30)
        #expect(a.hasSameContent(as: b))
        b.totalEntryCount = 3
        #expect(!a.hasSameContent(as: b))
    }

    @Test("归档记录的原图不再下载")
    func archivedMediaIsNotDownloaded() throws {
        let context = try memoryContext()
        let archived = Entry(happenedAt: .now, authorRole: "papa", note: "删了")
        archived.isArchived = true
        let live = Entry(happenedAt: .now, authorRole: "papa", note: "在")
        context.insert(archived); context.insert(live)
        let gone = Media(type: .photo, localFileName: nil)
        gone.remoteURL = "https://example.invalid/a.jpg"; gone.syncState = .synced; gone.entry = archived
        let kept = Media(type: .photo, localFileName: nil)
        kept.remoteURL = "https://example.invalid/b.jpg"; kept.syncState = .synced; kept.entry = live
        context.insert(gone); context.insert(kept)
        try context.save()
        let result = try SyncEngine.mediaNeedingDownload(in: context, limit: 10, fileExists: { _ in false })
        #expect(result.map(\.id) == [kept.id])
    }

    // MARK: D9-07 记录此刻草稿

    private func scratchDraftStore() -> CaptureDraftStore {
        CaptureDraftStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("t7-draft-\(UUID().uuidString)", isDirectory: true))
    }

    @Test("草稿落盘后，新进程打开面板能找回文字与心情；丢掉后不再出现")
    func captureDraftSurvivesRelaunch() {
        let store = scratchDraftStore()
        let first = CaptureModel(mediaStore: MediaStore(), analyzer: PhotoAnalyzer(), role: .mama, draftStore: store)
        first.note = "布布今天第一次自己穿鞋"
        first.mood = .happy
        first.persistDraftNow()
        #expect(store.load()?.note == "布布今天第一次自己穿鞋")

        // 模拟被系统回收后重开
        let relaunched = CaptureModel(mediaStore: MediaStore(), analyzer: PhotoAnalyzer(), role: .mama, draftStore: store)
        relaunched.startQuickCapture()
        #expect(relaunched.note == "布布今天第一次自己穿鞋")
        #expect(relaunched.mood == .happy)
        #expect(relaunched.restoredDraftNotice != nil)
        #expect(relaunched.showQuickCapture)

        relaunched.discardDraft()
        #expect(store.load() == nil)
        let again = CaptureModel(mediaStore: MediaStore(), analyzer: PhotoAnalyzer(), role: .mama, draftStore: store)
        again.startQuickCapture()
        #expect(again.note.isEmpty)
        #expect(again.restoredDraftNotice == nil)
    }

    @Test("带预填的新记录不被旧草稿顶替")
    func prefillDoesNotRestoreDraft() {
        let store = scratchDraftStore()
        store.save(CaptureDraft(note: "旧草稿", moodRaw: nil, voiceFileName: nil, voiceDuration: 0,
                                voiceWaveform: [], savedAt: .now))
        let model = CaptureModel(mediaStore: MediaStore(), analyzer: PhotoAnalyzer(), role: .mama, draftStore: store)
        model.startQuickCapture(prefillNote: "【今日一问】")
        #expect(model.note == "【今日一问】")
        #expect(model.restoredDraftNotice == nil)
    }

    @Test("孤儿录音清理：只删登记过且无人引用的文件，保留当前草稿与已入库的录音")
    func orphanDraftAudioCleanup() throws {
        let context = try memoryContext()
        let store = scratchDraftStore()
        let mediaStore = MediaStore()
        try FileManager.default.createDirectory(at: BubuStorage.mediaDirectory, withIntermediateDirectories: true)
        func makeFile() throws -> String {
            let name = "t7-\(UUID().uuidString).m4a"
            try Data("synthetic voice".utf8).write(to: BubuStorage.mediaDirectory.appendingPathComponent(name))
            store.trackDraftAudio(name)
            return name
        }
        let orphan = try makeFile()
        let draftVoice = try makeFile()
        let committed = try makeFile()
        let note = VoiceNote(localFileName: committed, durationSeconds: 1, authorRole: "mama", waveformSamples: [])
        context.insert(note)
        try context.save()
        store.save(CaptureDraft(note: "", moodRaw: nil, voiceFileName: draftVoice, voiceDuration: 1,
                                voiceWaveform: [], savedAt: .now))

        let removed = store.cleanupOrphanAudio(context: context, mediaStore: mediaStore)
        #expect(removed == [orphan])
        #expect(!mediaStore.fileExists(forMedia: orphan))
        #expect(mediaStore.fileExists(forMedia: draftVoice))
        #expect(mediaStore.fileExists(forMedia: committed))
        #expect(store.trackedAudio == [draftVoice])
        mediaStore.deleteMedia(named: draftVoice)
        mediaStore.deleteMedia(named: committed)
    }
}
