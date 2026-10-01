import Foundation
import SwiftData
import WatchConnectivity
import os

// MARK: - 手表连接（iPhone 侧）
/// 收手表发来的记录意图 → 写入 App Group 共享 store（EntryWriter，幂等）→ 通知 App 触发同步。
/// 同时把概览快照推给手表。手表不跑 SwiftData/同步，一切写入与上云都在 iPhone 完成。
@MainActor
final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    /// 收到手表记录后广播，AppEnvironment 监听以立即同步 + 刷新快照。
    static let didRecordNotification = Notification.Name("bubu.watch.didRecord")

    private let log = Logger(subsystem: "com.bubu.timemachine", category: "WatchConnectivity")
    private var pendingSnapshot: WatchSnapshot?

    /// 只复用 App 的容器；后台写入使用独立 context，不能把 UI 未保存的对象当成已落盘记录。
    /// 未注入（如后台被 WC 唤醒）时回退到共享容器。
    var appContext: ModelContext?

    /// 已撤销记录的 localId 名单（保最近 50 条）。
    /// 手表 deliver 是双保险投递：sendMessage 送达但回执误报失败时，同一 payload
    /// 会再走 transferUserInfo 迟到几分钟——若用户中途撤销了，迟到副本会因
    /// 「exists 检查不到」被原样重建。落库前先查这份名单即可挡住。
    /// 持久化到 UserDefaults：App 被杀后队列里的迟到副本仍会投递。
    private static let undoneKey = "bubu.watch.undoneLocalIds"
    private var undoneLocalIds: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.undoneKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.suffix(50)), forKey: Self.undoneKey) }
    }
    private var persistentContainer: ModelContainer? {
        guard !BubuStoreHealth.loadFailed,
              let container = appContext?.container ?? SharedModelContainer.sharedIfAvailable,
              WatchVoiceInbox.isPersistent(container) else { return nil }
        return container
    }

    private var writeContext: ModelContext? {
        guard let container = persistentContainer else { return nil }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// 把概览快照推给手表（合并最新态，省电）。未激活时缓存，激活后补发。
    func push(_ snapshot: WatchSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { pendingSnapshot = snapshot; return }
        guard let data = WatchLink.encode(snapshot) else { return }
        do {
            try session.updateApplicationContext([WatchLink.snapshotKey: data])
        } catch {
            log.error("push snapshot failed: \(error.localizedDescription)")
        }
        pushPhotoBundle(names: photoNames(memories: snapshot.memories, recent: snapshot.recent),
                        session: session)
    }

    // MARK: 回忆照片包（transferFile）

    /// 上次已送达手表的照片集合指纹。集合没变就不重传——快照每次进前台都推，
    /// 但 400KB 的照片包只该在照片真的换了批时走一次。
    /// nonisolated：didFinish 回调在 WC 队列上作废它。
    nonisolated private static let sentFingerprintKey = "bubu.watch.photoBundle.sentFingerprint"
    /// 最近一次组包用的照片名清单，手表请求补发时直接按它重组，不用重读库。
    private var lastPhotoNames: [String]?

    /// 回忆 + 最近 两处引用的照片名并集（去重保序）。
    private func photoNames(memories: [WatchMemory]?, recent: [WatchRecent]?) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for name in (memories ?? []).compactMap(\.photoFileName) where seen.insert(name).inserted {
            names.append(name)
        }
        for name in (recent ?? []).compactMap(\.photoFileName) where seen.insert(name).inserted {
            names.append(name)
        }
        return names
    }

    /// 正在后台编码照片包。冷启动/回前台会连着推好几次快照，
    /// 没有这个闸门就会同时起好几份 20 张图的解码任务。
    private var encodingPhotoBundle = false

    private func pushPhotoBundle(names: [String], session: WCSession) {
        guard !names.isEmpty else { return }
        lastPhotoNames = names
        let fingerprint = WatchPhotoBundle.fingerprint(names)
        guard fingerprint != UserDefaults.standard.string(forKey: Self.sentFingerprintKey) else { return }
        guard !encodingPhotoBundle else { return }
        encodingPhotoBundle = true

        // 约 20 张图的降采样 + JPEG 编码原来整段跑在主线程（冷启动与每次回前台都会走），
        // 是可感知的卡顿源。搬到全局并发执行器，编码完再回主线程排队传输。
        Task { [weak self] in
            let encoded = await Self.encodePhotoBundleOffMain(names: names)
            guard let self else { return }
            self.encodingPhotoBundle = false
            guard let encoded else { return }
            // 临时文件交给 WCSession 排队；didFinish 里删自己那份。
            // 文件名带随机后缀：同指纹补发时若复用同名文件，第一笔传输完成的 removeItem
            // 会把第二笔仍在排队的源文件删掉，第二笔必失败。
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("bubu-photobundle-\(fingerprint)-\(UUID().uuidString.prefix(8)).bin")
            do {
                try encoded.bundle.write(to: url, options: .atomic)
            } catch {
                self.log.error("photo bundle write failed: \(error.localizedDescription)")
                return
            }
            let session = WCSession.default
            guard session.activationState == .activated else { return }
            session.transferFile(url, metadata: [WatchLink.photoBundleKey: fingerprint])
            // 乐观记账：真正失败时手表侧会走「缺图请求补发」兜底，不会永久卡住。
            UserDefaults.standard.set(fingerprint, forKey: Self.sentFingerprintKey)
            self.log.notice("photo bundle queued: \(encoded.count) photos, \(encoded.bundle.count) bytes")
        }
    }

    private struct EncodedPhotoBundle: Sendable {
        let bundle: Data
        let count: Int
    }

    /// @concurrent：approachable-concurrency 下 nonisolated async 默认继承调用方执行器，
    /// 必须显式切到全局并发执行器，图片解码/JPEG 编码才真正离开主线程。
    @concurrent
    private nonisolated static func encodePhotoBundleOffMain(names: [String]) async -> EncodedPhotoBundle? {
        let photos = WatchSnapshotBuilder.photosData(for: names)
        guard !photos.isEmpty else { return nil }
        return EncodedPhotoBundle(bundle: WatchPhotoBundle.encode(photos), count: photos.count)
    }

    /// 手表说缓存缺图（重装/LRU 清掉了）：作废指纹并立即重发。
    private func resendPhotoBundle() {
        UserDefaults.standard.removeObject(forKey: Self.sentFingerprintKey)
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if let names = lastPhotoNames {
            pushPhotoBundle(names: names, session: session)
        }
        // lastPhotoNames 为空（App 刚被 WC 后台唤醒）：什么都不做，
        // 指纹已清，下次前台 pushWatchSnapshot 自然带上照片包。
    }

    // MARK: 落库
    private func handle(_ request: WatchRecordRequest) {
        guard let localId = UUID(uuidString: request.localId), let context = writeContext else { return }
        // 已撤销的记录：迟到的重复投递直接丢弃，不得重建。
        if request.type != .undo, undoneLocalIds.contains(where: { UUID(uuidString: $0) == localId }) { return }
        let role = FamilyRole(rawValue: request.roleRaw) ?? .mama
        do {
            switch request.type {
            case .text:
                try EntryWriter.quickTextEntry(note: request.note ?? "", role: role, in: context,
                                               localId: localId, happenedAt: request.happenedAt)
            case .mood:
                let mood = request.moodRaw.flatMap(Mood.init(rawValue:))
                let note = request.note?.isEmpty == false ? request.note! : (mood.map { "\($0.emoji) \($0.rawValue)" } ?? "记录了一个瞬间")
                try EntryWriter.quickTextEntry(note: note, mood: mood, role: role, in: context,
                                               localId: localId, happenedAt: request.happenedAt)
            case .health:
                let kind = request.healthKindRaw.flatMap(HealthRecordKind.init(rawValue:)) ?? .meal
                try EntryWriter.quickHealthEntry(kind: kind, title: request.healthTitle ?? kind.title,
                                                 role: role, in: context,
                                                 localId: localId, happenedAt: request.happenedAt)
            case .voice:
                // 语音只能经持久收件箱导入；单独收到意图时不能确认文件已保存。
                return
            case .undo:
                try undoRecord(localId: request.localId, in: context)
            case .sleepStart:
                // 与 iPhone 健康页共用同一份哄睡状态；灵动岛计时尽力而为
                //（后台被 WC 唤醒时 ActivityKit 不允许发起，失败无妨——状态在，前台自会接上）。
                // 已有进行中的计时（手机先点了、手表快照过期没显示）：保留更早的开始时刻，
                // 不然已进行 40 分钟的哄睡会被截断重置。
                if let existing = SharedDefaults.sleepStartedAt, existing < request.happenedAt {
                    break
                }
                SharedDefaults.sleepStartedAt = request.happenedAt
                let profile = try? context.fetch(FetchDescriptor<ChildProfile>()).first
                BubuActivityController.startSleepTimer(childName: profile?.name ?? "布布",
                                                       startedAt: request.happenedAt)
            case .sleepEnd:
                try endSleep(request, role: role, in: context)
            case .reaction:
                try applyReaction(request, role: role, in: context)
            }
            NotificationCenter.default.post(name: Self.didRecordNotification, object: nil)
        } catch {
            context.rollback()
            log.error("watch record write failed: \(error.localizedDescription)")
        }
    }

    /// 手表结束哄睡：落一条带起止时刻的睡眠记录。语义与 iPhone 健康页 endSleep 一致，
    /// 这样无论从哪端收尾，时光轴里都是同一种「睡了 X 小时」的卡。
    /// 手机侧状态丢了（重装等）就用手表带来的 happenedAt 兜底记一条无时长的。
    private func endSleep(_ request: WatchRecordRequest, role: FamilyRole, in context: ModelContext) throws {
        // 幂等：deliver 双保险可能同 localId 投递两次。第二次时 sleepStartedAt 已清，
        // 会走"无时长兜底"用 nil 覆盖掉刚记好的时长（unique id 触发 upsert），还多插一条动态。
        if let localId = UUID(uuidString: request.localId) {
            let d = FetchDescriptor<HealthRecord>(predicate: #Predicate { $0.id == localId })
            if ((try? context.fetchCount(d)) ?? 0) > 0 { return }
        }
        let end = request.happenedAt
        let started = SharedDefaults.sleepStartedAt
        SharedDefaults.sleepStartedAt = nil

        // 误触保护：不到一分钟就"醒了"多半是手滑连点，清状态但不落一条 0 分钟的睡眠卡。
        if let started, end.timeIntervalSince(started) < 60 {
            BubuActivityController.endSleepTimer(elapsedText: "")
            return
        }
        let record = HealthRecord(kind: .sleep, title: "睡觉", recordedAt: end)
        if let localId = UUID(uuidString: request.localId) { record.id = localId }
        if let started, started < end {
            record.startAt = started
            record.endAt = end
            record.amountValue = end.timeIntervalSince(started) / 3600
            record.amountUnit = "小时"
            record.amountText = HealthRecordDraft.durationText(from: started, to: end)
        }
        context.insert(record)
        let summaryText = record.amountText
        context.insert(FeedEvent(kind: .healthRecorded, actorRole: role.rawValue,
                                 summary: "记录了睡眠：\(summaryText ?? "醒来啦")",
                                 targetLocalId: record.id.uuidString, happenedAt: end))
        try context.save()
        BubuActivityController.endSleepTimer(elapsedText: summaryText ?? "")
    }

    /// 手表在时光机里重温某条 → 给那条记录点一个「亲亲」。
    ///
    /// 复用 App 里已有的 Reaction 机制（Comment + `\u{1}RXN:` 哨兵前缀）而不是另造一套：
    /// 那套已经跨三台手机同步、时光轴卡片上已有 ReactionRow 渲染、且按作者去重
    /// （同一人重温十次仍是一颗心）——正好避免"重温十次时光轴多十条垃圾"。
    /// 零 schema 变更、零新 UI。
    private func applyReaction(_ request: WatchRecordRequest, role: FamilyRole,
                               in context: ModelContext) throws {
        guard let targetId = request.note, let entryId = UUID(uuidString: targetId) else { return }
        let d = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryId })
        guard let entry = try context.fetch(d).first else { return }

        let myRole = role.rawValue
        // 同一人只保留最新一条反应：先清掉自己的旧反应。
        for comment in entry.comments where comment.authorRole == myRole && Reaction.isReaction(comment) {
            if Reaction.decode(comment.text) == .heart { return }   // 已经亲过，重复重温不再写库
            // 与 App 内 toggleReaction 同款：不入删除队列的话，已同步的旧反应下轮 pull 就复活。
            PendingDeletion.enqueue(collection: "comments", remoteId: comment.remoteId, in: context)
            context.delete(comment)
        }
        let comment = Comment(authorRole: myRole, text: Reaction.heart.encodedText)
        comment.entry = entry
        context.insert(comment)
        context.insert(FeedEvent(kind: .commentAdded, actorRole: myRole,
                                 summary: "\(myRole) 在手表上重温了这一刻 ❤️",
                                 targetLocalId: entry.id.uuidString))
        try context.save()
    }

    /// 撤销手表刚打的一条（防手滑）。localId 是原记录的幂等键，
    /// 打卡是 HealthRecord、文字/心情是 Entry——两处都找；删除走 App 标准三件套
    /// （PendingDeletion 入队 → 本地删 → save），已同步到服务器的也能墓碑掉，不复活。
    private func undoRecord(localId: String, in context: ModelContext) throws {
        guard let id = UUID(uuidString: localId) else { return }
        undoneLocalIds.append(localId)
        let idString = id.uuidString

        let healthFetch = FetchDescriptor<HealthRecord>(predicate: #Predicate { $0.id == id })
        if let record = try context.fetch(healthFetch).first {
            PendingDeletion.enqueue(collection: "healthrecords", remoteId: record.remoteId, in: context)
            context.delete(record)
        } else {
            let entryFetch = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
            guard let entry = try context.fetch(entryFetch).first else { return }
            PendingDeletion.enqueue(collection: "entries", remoteId: entry.remoteId, in: context)
            context.delete(entry)
        }
        // 连带清掉这条在「最近」里的动态，手表/家人不再看到已撤销的事。
        let eventFetch = FetchDescriptor<FeedEvent>(predicate: #Predicate { $0.targetLocalId == idString })
        for event in try context.fetch(eventFetch) { context.delete(event) }
        try context.save()
        log.notice("watch undo applied: \(localId, privacy: .public)")
    }
}

// MARK: - 概览快照构建（iPhone 侧读库 → 手表展示）
enum WatchSnapshotBuilder {
    @MainActor
    static func make(context: ModelContext, role: FamilyRole) -> WatchSnapshot? {
        guard let profile = try? context.fetch(FetchDescriptor<ChildProfile>()).first else { return nil }
        // 「最近」用 FeedEvent（统一涵盖记录/健康打卡/语音等），这样手表打卡后也能立刻在「最近」看到。
        // 按 createdAt（动作时刻）排：导入旧照片的动态也能进「最近」，不被事件真实时间埋掉。
        var feedDescriptor = FetchDescriptor<FeedEvent>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        feedDescriptor.fetchLimit = 6
        let events = (try? context.fetch(feedDescriptor)) ?? []
        let recent = events
            .filter { $0.kind != .entryArchived }
            .prefix(4)
            .map { e in
                WatchRecent(id: e.id.uuidString,
                            dateText: BubuDateFormat.monthDay(e.createdAt),
                            note: e.summary,
                            moodEmoji: e.kind.emoji,
                            photoFileName: recentPhotoName(targetLocalId: e.targetLocalId, context: context))
            }
        let milestones = (try? context.fetch(FetchDescriptor<Milestone>())) ?? []
        let achieved = milestones.filter { $0.isAchieved }.count
        return WatchSnapshot(childName: profile.name, birthday: profile.birthday,
                             roleRaw: role.rawValue,
                             achievedMilestones: achieved, totalMilestones: milestones.count,
                             recent: Array(recent), avatarData: avatarThumbData(profile.avatarMediaFileName),
                             updatedAt: .now,
                             memories: memories(context: context, birthday: profile.birthday),
                             todayStats: todayStats(context: context),
                             sleepingSince: SharedDefaults.sleepStartedAt)
    }

    // MARK: 回忆序列（表冠时光机）

    /// 一次下发多少段。手表侧一屏一段，20 段大约是拧 3 圈表冠——够远，又不至于让照片包过大。
    private static let memoryCount = 20

    /// 组装回忆序列：近期 + 那年今日 + 更早的抽样，去重后**按时间倒序**。
    ///
    /// 为什么必须单调有序：手表侧拧表冠是「越拧越远」的时间旅行，顶部还有一条年代刻度尺。
    /// 池子里混序的话，刻度尺会来回跳，那个「往回走」的体感就没了。
    /// 「那年今日」不单独排在一起，而是就地打标记——它本来就属于它那个年份。
    @MainActor
    private static func memories(context: ModelContext, birthday: Date?) -> [WatchMemory]? {
        let store = MediaStore()
        var descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.happenedAt, order: .reverse)])
        descriptor.fetchLimit = 300
        guard let entries = try? context.fetch(descriptor), !entries.isEmpty else { return nil }

        let cal = Calendar.current
        let todayMonth = cal.component(.month, from: .now)
        let todayDay = cal.component(.day, from: .now)

        var picked: [Entry] = []
        var seen = Set<UUID>()
        func take(_ entry: Entry) {
            guard !seen.contains(entry.id) else { return }
            seen.insert(entry.id)
            picked.append(entry)
        }

        // ① 近期 8 条：时光机的起点得是「刚发生的事」，不然一拧就跳到三年前很突兀。
        for entry in entries.prefix(8) { take(entry) }
        // ② 那年今日：同月同日的旧记录，是这个功能最有价值的部分。
        for entry in entries where picked.count < 14 {
            guard cal.component(.month, from: entry.happenedAt) == todayMonth,
                  cal.component(.day, from: entry.happenedAt) == todayDay,
                  !cal.isDateInToday(entry.happenedAt) else { continue }
            take(entry)
        }
        // ③ 更早的等距抽样：让剩下的格子铺满整个时间跨度，而不是全挤在最近一个月。
        let remaining = entries.filter { !seen.contains($0.id) }
        if !remaining.isEmpty, picked.count < memoryCount {
            let need = memoryCount - picked.count
            let stride = max(1, remaining.count / need)
            for i in Swift.stride(from: 0, to: remaining.count, by: stride) where picked.count < memoryCount {
                take(remaining[i])
            }
        }

        let onThisDay = Set(picked.filter {
            cal.component(.month, from: $0.happenedAt) == todayMonth
                && cal.component(.day, from: $0.happenedAt) == todayDay
                && !cal.isDateInToday($0.happenedAt)
        }.map(\.id))

        return picked
            .sorted { $0.happenedAt > $1.happenedAt }
            .map { entry in
                // 【别改回 `a ?? b` 的写法】`??` 右侧是 autoclosure，会捕获 SwiftData 模型对象，
                // Release（whole-module）下被判成「main actor 闭包捕获 task-isolated 值」而编译失败。
                // 先取成局部量再拼装。
                let firstPerson = clip(entry.firstPersonNote, 46)
                let plain = clip(entry.note, 46)
                let title = clip(entry.title, 46)
                let text = firstPerson ?? plain ?? title ?? "这一天"
                return WatchMemory(
                    id: entry.id.uuidString,
                    dateText: BubuDateFormat.monthDay(entry.happenedAt),
                    note: text,
                    ageText: birthday.map { AgeCalculator.compactAge(birthday: $0, at: entry.happenedAt) } ?? "",
                    isOnThisDay: onThisDay.contains(entry.id),
                    moodEmoji: entry.mood?.emoji,
                    photoFileName: photoName(for: entry, store: store))
            }
    }

    /// 这条记录代表哪一张照片。返回的名字同时是手表缓存里的 key，所以必须稳定
    /// （同一条记录每次都算出同一个名字，手表才不会重复下载同一张图）。
    ///
    /// 【必须校验文件真的在本地】家人发来的照片，缩略图可能还没下载完。
    /// 若在这里返回一个手机自己都没有的文件名，就会形成死循环：
    /// 组包时这张被跳过 → 手表数出「快照引用了 N 张、缓存只有 N-1 张」→ 请求补发 →
    /// 手机作废指纹重传约 600KB → 下一轮再缺 → 无限。所以缺文件的直接跳到下一张。
    @MainActor
    private static func photoName(for entry: Entry, store: MediaStore) -> String? {
        for media in entry.sortedMedia where media.type == .photo {
            let thumb = media.thumbnailFileName
            let original = media.localFileName
            guard let name = thumb ?? original, !name.isEmpty else { continue }
            let short = (name as NSString).lastPathComponent
            guard hasLocalFile(short, store: store) else { continue }
            return short
        }
        return nil
    }

    /// 缩略图目录或原图目录任一存在即可（组包侧的取图顺序与此一致）。
    nonisolated static func hasLocalFile(_ name: String, store: MediaStore) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: store.thumbnailURL(for: name).path)
            || fm.fileExists(atPath: store.mediaURL(for: name).path)
    }

    /// 「最近」一条动态对应的照片：FeedEvent 只带 targetLocalId，回查 Entry 取首图。
    @MainActor
    private static func recentPhotoName(targetLocalId: String?, context: ModelContext) -> String? {
        guard let targetLocalId, let id = UUID(uuidString: targetLocalId) else { return nil }
        let d = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
        guard let entry = try? context.fetch(d).first else { return nil }
        return photoName(for: entry, store: MediaStore())
    }

    private static func clip(_ value: String?, _ maxLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count <= maxLength ? trimmed : String(trimmed.prefix(maxLength)) + "…"
    }

    /// 把一批照片按名字裁成手表尺寸。
    /// 400px 长边 + JPEG 0.7 ≈ 20–30KB/张：手表最大屏（Ultra 2，410×502pt）显示一张卡够清晰，
    /// 20 张打包不到 600KB。再大是白给——手表看不出差别，传输却成倍变慢。
    /// nonisolated：整段只用 Sendable 的 MediaStore + nonisolated 的解码工具，
    /// 可以（也应该）在非主执行器上跑。
    nonisolated static func photosData(for names: [String]) -> [(name: String, data: Data)] {
        let store = MediaStore()
        var out: [(name: String, data: Data)] = []
        for name in names {
            let thumb = store.thumbnailURL(for: name)
            let url = FileManager.default.fileExists(atPath: thumb.path) ? thumb : store.mediaURL(for: name)
            guard FileManager.default.fileExists(atPath: url.path),
                  let image = ThumbnailProvider.downsample(url: url, maxPixel: 400),
                  let data = image.jpegData(compressionQuality: 0.7) else { continue }
            out.append((name: name, data: data))
        }
        return out
    }

    // MARK: 今日打卡计数

    /// 今天各类打卡了几次。手表打卡按钮的角标（🍼 ×4）用它——
    /// 「今天第几次」是喂养场景最常被问的一句，却是原来手表上唯一看不到的信息。
    @MainActor
    private static func todayStats(context: ModelContext) -> [String: Int]? {
        let start = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<HealthRecord>(
            predicate: #Predicate { $0.recordedAt >= start })
        guard let records = try? context.fetch(descriptor), !records.isEmpty else { return [:] }
        var stats: [String: Int] = [:]
        for record in records {
            stats[record.kindRaw, default: 0] += 1
        }
        return stats
    }

    /// 布布头像小缩略图（120px，jpeg 0.7，<30KB），供手表概览显示。
    private static func avatarThumbData(_ fileName: String?) -> Data? {
        guard let fileName, !fileName.isEmpty else { return nil }
        // 经 MediaStore 读回退解析：媒体后台迁移窗口内头像可能只在旧沙盒目录，
        // 直接拼 App Group 路径会漏读、手表概览丢头像。thumbnailURL/mediaURL 自动回退旧目录。
        let store = MediaStore()
        let thumb = store.thumbnailURL(for: fileName)
        let url = FileManager.default.fileExists(atPath: thumb.path) ? thumb : store.mediaURL(for: fileName)
        guard let image = ThumbnailProvider.downsample(url: url, maxPixel: 120) else { return nil }
        return image.jpegData(compressionQuality: 0.7)
    }
}

// MARK: - WCSessionDelegate（回调在 WC 队列，写库统一切回 MainActor）
extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let pending = self.pendingSnapshot { self.pendingSnapshot = nil; self.push(pending) }
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()   // 切换手表后重新激活
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[WatchLink.recordKey] as? Data,
              let request = WatchLink.decode(WatchRecordRequest.self, from: data) else { return }
        Task { @MainActor in self.handle(request) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message[WatchLink.photoBundleRequestKey] != nil {
            Task { @MainActor in self.resendPhotoBundle() }
            return
        }
        guard let data = message[WatchLink.recordKey] as? Data,
              let request = WatchLink.decode(WatchRecordRequest.self, from: data) else { return }
        Task { @MainActor in self.handle(request) }
    }

    /// 照片包送达（或系统放弃）后清掉临时文件；失败时同时作废指纹，让下轮重推。
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let url = fileTransfer.file.fileURL
        guard url.lastPathComponent.hasPrefix("bubu-photobundle-") else { return }
        try? FileManager.default.removeItem(at: url)
        if error != nil {
            UserDefaults.standard.removeObject(forKey: Self.sentFingerprintKey)
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // WC 的临时 URL 只在回调期间有效。先同步保全原音频和原始 metadata，
        // 无论媒体导入/数据库保存/解码是否成功，都不能只留下一个异步内存任务。
        do {
            try WatchVoiceInbox(directory: Self.emergencyVoiceDir()).stage(
                audio: file.fileURL, metadata: file.metadata ?? [:])
            Task { @MainActor in self.retryPendingVoiceImports() }
        } catch {
            // 磁盘完全不可写时无法保证接收成功；不把失败谎报成“已暂存”。
            Task { @MainActor in
                self.log.fault("watch voice staging failed; receipt not durable: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - iPhone 侧语音持久收件箱
extension WatchConnectivityManager {
    nonisolated private static func emergencyVoiceDir() -> URL {
        BubuStorage.containerURL.appendingPathComponent("PendingWatchVoice", isDirectory: true)
    }

    /// 成功保存至磁盘库（或确认磁盘库已引用完整音频）后，才消费应急副本。
    /// 恢复模式不消费、不清理；下次健康启动仍会重试。
    func retryPendingVoiceImports() {
        guard let container = persistentContainer else { return }
        let inbox = WatchVoiceInbox(directory: Self.emergencyVoiceDir())
        do {
            for voice in try inbox.pendingVoices() {
                guard !undoneLocalIds.contains(where: { UUID(uuidString: $0) == voice.localId }) else { continue }
                do {
                    try inbox.importVoice(voice, into: container, mediaDirectory: BubuStorage.mediaDirectory)
                    NotificationCenter.default.post(name: Self.didRecordNotification, object: nil)
                } catch {
                    log.error("watch voice remains queued: \(error.localizedDescription)")
                }
            }
        } catch {
            log.error("watch voice inbox unavailable: \(error.localizedDescription)")
        }
    }
}

/// 文件侧与数据库侧都可注入独立测试路径，不依赖真实 App Group 或 WCSession。
nonisolated struct WatchVoiceInbox: Sendable {
    let directory: URL

    struct PendingVoice: Sendable {
        let request: WatchRecordRequest
        let localId: UUID
        let deliveryId: UUID
        let audio: URL
        let metadata: URL
        let package: URL?
    }

    enum ImportError: Error {
        case ephemeralStore, missingDurableAudio, audioConflict
    }

    /// 每次投递分配自己的目录，绝不用未校验的 localId 拼路径，也不覆盖之前的应急副本。
    /// metadata 编码/写入失败时仍保留已经拷出的音频；后续重试不会清理这些孤儿。
    @discardableResult
    func stage(audio: URL, metadata: [String: Any]) throws -> URL {
        let fm = FileManager.default
        let package = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        try fm.copyItem(at: audio, to: package.appendingPathComponent("recording.m4a"))
        let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .binary, options: 0)
        try data.write(to: package.appendingPathComponent("metadata.plist"), options: .atomic)
        return package
    }

    /// 同时兼容旧版 <localId>.json/.m4a。损坏、缺元数据、非法 UUID 全部保留供恢复，
    /// 不按年龄删除可能是唯一副本的录音。只从受控文件名读取音频。
    func pendingVoices() throws -> [PendingVoice] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return urls.compactMap { url in
            let requestData: Data?
            let audio: URL
            let metadata: URL
            let package: URL?
            let deliveryId: UUID
            if url.pathExtension == "json" {
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
                deliveryId = id
                metadata = url
                audio = url.deletingPathExtension().appendingPathExtension("m4a")
                package = nil
                requestData = try? Data(contentsOf: url)
            } else {
                guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
                deliveryId = id
                package = url
                metadata = url.appendingPathComponent("metadata.plist")
                audio = url.appendingPathComponent("recording.m4a")
                guard let data = try? Data(contentsOf: metadata),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                      let values = plist as? [String: Any],
                      let json = values[WatchLink.fileMetaKey] as? String else { return nil }
                requestData = json.data(using: .utf8)
            }
            guard let requestData,
                  let request = WatchLink.decode(WatchRecordRequest.self, from: requestData),
                  request.type == .voice,
                  let localId = UUID(uuidString: request.localId),
                  package != nil || localId == deliveryId,
                  fm.fileExists(atPath: audio.path) else { return nil }
            return PendingVoice(request: request, localId: localId, deliveryId: deliveryId,
                                audio: audio, metadata: metadata, package: package)
        }
    }

    @MainActor
    static func isPersistent(_ container: ModelContainer) -> Bool {
        !container.configurations.isEmpty && container.configurations.allSatisfy { !$0.isStoredInMemoryOnly }
    }

    /// 每次尝试使用新 context；失败 rollback，下一次绝不能把未保存对象当成落盘去重证据。
    /// save 参数仅作为故障注入点。生产调用总是显式 save；autosave 永远关闭。
    @MainActor
    func importVoice(_ voice: PendingVoice, into container: ModelContainer, mediaDirectory: URL,
                     save: @MainActor (ModelContext) throws -> Void = { try $0.save() }) throws {
        guard Self.isPersistent(container) else { throw ImportError.ephemeralStore }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let id = voice.localId
            let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
            if let existing = try context.fetch(descriptor).first {
                // 单有 Entry 不是完整录音。缺音频/碰撞时保留收件箱，不误判为已安全落库。
                guard Self.hasMatchingAudio(existing, source: voice.audio, mediaDirectory: mediaDirectory) else {
                    throw ImportError.missingDurableAudio
                }
            } else {
                let fm = FileManager.default
                try fm.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
                // 稳定、已校验的投递 UUID：重试复用先前的拷贝，不无限生成孤儿音频。
                let fileName = "watch-\(voice.deliveryId.uuidString).m4a"
                let destination = mediaDirectory.appendingPathComponent(fileName)
                if fm.fileExists(atPath: destination.path) {
                    guard fm.contentsEqual(atPath: destination.path, andPath: voice.audio.path) else {
                        throw ImportError.audioConflict
                    }
                } else {
                    try fm.copyItem(at: voice.audio, to: destination)
                }
                let role = FamilyRole(rawValue: voice.request.roleRaw) ?? .mama
                let entry = Entry(happenedAt: voice.request.happenedAt, authorRole: role.rawValue, note: nil)
                entry.id = id
                context.insert(entry)
                let note = VoiceNote(localFileName: fileName, durationSeconds: voice.request.voiceDuration ?? 0,
                                     authorRole: role.rawValue, waveformSamples: [])
                note.entry = entry
                context.insert(note)
                context.insert(FeedEvent(kind: .voiceAdded, actorRole: role.rawValue,
                                         summary: "从手表录了一段声音", targetLocalId: id.uuidString,
                                         happenedAt: voice.request.happenedAt))
                try save(context)
            }
            // 独立 context 回读，不能用刚写过（可能仍脏）的 context 作为删原件凭据。
            let verification = ModelContext(container)
            verification.autosaveEnabled = false
            guard let persisted = try verification.fetch(descriptor).first,
                  Self.hasMatchingAudio(persisted, source: voice.audio, mediaDirectory: mediaDirectory) else {
                throw ImportError.missingDurableAudio
            }
        } catch {
            context.rollback()
            throw error
        }
        // 只在明确成功的路径删除。删除失败也安全：新 context 重试将以持久数据去重。
        if let package = voice.package {
            try FileManager.default.removeItem(at: package)
        } else {
            try FileManager.default.removeItem(at: voice.audio)
            try FileManager.default.removeItem(at: voice.metadata)
        }
    }

    @MainActor
    private static func hasMatchingAudio(_ entry: Entry, source: URL, mediaDirectory: URL) -> Bool {
        entry.voiceNotes.contains { note in
            guard let name = note.localFileName, !name.isEmpty,
                  name == (name as NSString).lastPathComponent else { return false }
            return FileManager.default.contentsEqual(
                atPath: mediaDirectory.appendingPathComponent(name).path, andPath: source.path)
        }
    }
}
