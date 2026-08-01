import Foundation
import WatchConnectivity
import Observation
import WidgetKit

// MARK: - 手表连接器（watchOS 侧）
/// 收 iPhone 推来的概览快照；把记录意图发回 iPhone。可达时即时发送，不可达时排队保证送达（离线也不丢）。
@MainActor
@Observable
final class WatchConnector: NSObject {
    var snapshot: WatchSnapshot?
    /// 最近一次成功发出的提示时间（UI 显示「已送到手机」）。
    var lastSentLabel: String?
    /// 照片包落盘次数。视图 onChange 它来重取缓存图——照片总在快照之后才到，
    /// 没有这个信号，时光机会一直显示「快照有图名、缓存无图」的空格子直到下次重进。
    var photoVersion = 0
    /// 上次向手机请求补发照片包的时刻（节流：一分钟最多一次）。
    private var lastPhotoRequestAt: Date = .distantPast
    /// 已经为哪一批照片请求过补发。同一批只求一次——手机若真的没有那张图
    /// （比如家人的照片这台手机也还没下载），再求多少次也变不出来，
    /// 求下去只会每分钟白传一次整包。
    private var requestedFingerprints: [String] = []
    /// 会话未激活期间缓存的文字/心情/健康记录，激活后补发（#6：冷启动秒录窗口 session 尚未激活）。
    private var pendingRecords: [WatchRecordRequest] = []

    override init() {
        super.init()
        // 冷启动先显示上次的本地快照（复杂功能扩展已在用同一份），
        // 抬腕不再是空白等待，WCSession 连上后再刷新为最新。
        snapshot = WatchSnapshotStore.load()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private var roleRaw: String { snapshot?.roleRaw ?? "妈妈" }

    // MARK: 发送各类记录
    @discardableResult
    func sendText(_ note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let req = WatchRecordRequest(type: .text, roleRaw: roleRaw, note: trimmed)
        send(req, label: "已记下")
        return req.localId
    }

    func sendMood(rawValue: String, emoji: String) {
        send(WatchRecordRequest(type: .mood, roleRaw: roleRaw,
                                note: "\(emoji) \(rawValue)", moodRaw: rawValue), label: "已记下心情")
    }

    @discardableResult
    func sendHealth(kindRaw: String, title: String) -> String {
        let req = WatchRecordRequest(type: .health, roleRaw: roleRaw,
                                     healthKindRaw: kindRaw, healthTitle: title)
        send(req, label: "已打卡")
        // 乐观 +1：角标立即变，不等手机回推快照。
        if var stats = snapshot?.todayStats {
            stats[kindRaw, default: 0] += 1
            snapshot?.todayStats = stats
        } else {
            snapshot?.todayStats = [kindRaw: 1]
        }
        return req.localId
    }

    /// 撤销后的角标回退（乐观 -1）。
    func revertTodayStat(kindRaw: String) {
        guard var stats = snapshot?.todayStats else { return }
        stats[kindRaw] = max(0, (stats[kindRaw] ?? 1) - 1)
        snapshot?.todayStats = stats
    }

    /// 时光机里重温某条 → 给它点个亲亲。note 承载目标 Entry 的 id。
    func sendReaction(entryId: String) {
        send(WatchRecordRequest(type: .reaction, roleRaw: roleRaw, note: entryId), label: "❤️ 已送到")
    }

    /// 撤销刚才那条（防手滑）。localId 传当时发送用的那个。
    func sendUndo(localId: String) {
        send(WatchRecordRequest(type: .undo, localId: localId, roleRaw: roleRaw), label: "已撤销")
    }

    /// 哄睡开始/结束。本地乐观更新 sleepingSince，抬腕立即看到呼吸态，
    /// 不等手机回推快照（可能要几秒甚至更久）。
    func sendSleepStart() {
        let now = Date.now
        snapshot?.sleepingSince = now
        if let snap = snapshot { WatchSnapshotStore.save(snap) }
        send(WatchRecordRequest(type: .sleepStart, roleRaw: roleRaw, happenedAt: now), label: "哄睡计时开始")
    }

    func sendSleepEnd() {
        snapshot?.sleepingSince = nil
        if let snap = snapshot { WatchSnapshotStore.save(snap) }
        send(WatchRecordRequest(type: .sleepEnd, roleRaw: roleRaw), label: "睡眠已记好")
    }

    func sendVoice(fileURL: URL, duration: Double) {
        // localId = 文件名 stem（稳定幂等键）；先落边车，保证失败/未激活也能据此原样重发。
        let localId = WatchPendingVoiceStore.localId(forFile: fileURL)
        let req = WatchRecordRequest(type: .voice, localId: localId, roleRaw: roleRaw, voiceDuration: duration)
        WatchPendingVoiceStore.writeSidecar(req, forFile: fileURL)
        let session = WCSession.default
        guard session.activationState == .activated else {
            // #6：未激活（冷启动秒录）不立即 transferFile（会失败）。文件+边车已持久化，
            // activationDidCompleteWith / 进前台对账时重新入队。
            flash("语音已存好，联网即送")
            return
        }
        transferVoice(fileURL: fileURL, request: req, session: session)
        flash("语音已在路上")
    }

    /// 把持久待传文件交给 WCSession；请求随 metadata 一并送达（接收端据 localId 去重）。
    private func transferVoice(fileURL: URL, request: WatchRecordRequest, session: WCSession) {
        guard let data = WatchLink.encode(request), let json = String(data: data, encoding: .utf8) else { return }
        session.transferFile(fileURL, metadata: [WatchLink.fileMetaKey: json])
    }

    /// 传输完成：仅 error==nil（真正送达）才删源文件+边车。
    /// error != nil 表示系统已放弃（不再重试），此时删源=录音两端永久丢失（P0-2）——故保留，
    /// 下次激活/进前台对账重新 transferFile 入队。
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard error == nil else { return }
        WatchPendingVoiceStore.remove(fileURL: fileTransfer.file.fileURL)
    }

    /// 激活后对账：把持久目录里「不在传输队列中」的残留语音重新入队（涵盖上次失败/未激活遗留）。
    func reconcilePending() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        // 补发未激活期间缓存的文字/心情/健康。
        let queued = pendingRecords
        pendingRecords.removeAll()
        for req in queued { deliver(req, session: session) }
        // 语音对账：排除仍在传输中的，避免重复入队（重复也被接收端 localId 去重，此处先减负）。
        let outstanding = Set(session.outstandingFileTransfers.map { $0.file.fileURL.standardizedFileURL })
        for url in WatchPendingVoiceStore.pendingFiles() where !outstanding.contains(url.standardizedFileURL) {
            guard let req = WatchPendingVoiceStore.readSidecar(forFile: url) else { continue }
            transferVoice(fileURL: url, request: req, session: session)
        }
    }

    private func send(_ request: WatchRecordRequest, label: String) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            pendingRecords.append(request)   // #6：未激活先缓存，activationDidComplete 后补发
            flash(label)
            return
        }
        deliver(request, session: session)
        flash(label)
    }

    private func deliver(_ request: WatchRecordRequest, session: WCSession) {
        guard let data = WatchLink.encode(request) else { return }
        if session.isReachable {
            // 即时送达；失败则排队补发，双保险。
            session.sendMessage([WatchLink.recordKey: data], replyHandler: nil) { _ in
                session.transferUserInfo([WatchLink.recordKey: data])
            }
        } else {
            session.transferUserInfo([WatchLink.recordKey: data])   // 排队，联网自动补传
        }
    }

    private var lastFlashAt: Date = .distantPast

    private func flash(_ label: String) {
        lastSentLabel = label
        let stamp = Date.now
        lastFlashAt = stamp
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            // 按时间戳判断：连打两次卡是同一句「已打卡」，只比字符串会让
            // 第一条的延时任务提前清掉第二条的横幅。
            if lastFlashAt == stamp { lastSentLabel = nil }
        }
    }
}

extension WatchConnector: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        // 冷启动回填：激活时用上次已收到的快照，避免概览/最近空白直到 iPhone 再次 push。
        // 在 nonisolated 作用域内解出 [String:Any]（非 Sendable），只让 Sendable 值跨到 MainActor。
        let ctx = session.receivedApplicationContext
        var snap: WatchSnapshot?
        if let data = ctx[WatchLink.snapshotKey] as? Data {
            snap = WatchLink.decode(WatchSnapshot.self, from: data)
        }
        if let snap, Self.isNewer(snap) {
            WatchSnapshotStore.save(snap)
            WidgetCenter.shared.reloadAllTimelines()
        }
        let restored = snap
        let activated = (state == .activated)
        Task { @MainActor in
            if self.snapshot == nil, let restored { self.snapshot = restored }
            // 激活完成：补发缓存的记录 + 对账残留语音（#6 / P0-2 / W-P1-1 的重发入口）。
            if activated {
                self.reconcilePending()
                self.requestPhotosIfMissing()
            }
        }
    }

    /// 只有比本地存的更新才落盘：激活回调给的 receivedApplicationContext 可能是旧的，
    /// 无条件覆盖会抹掉本地乐观状态（比如断连时在手表开的哄睡计时）；
    /// 迟到的旧快照同理会让打卡角标闪回。
    nonisolated static func isNewer(_ snap: WatchSnapshot) -> Bool {
        guard let stored = WatchSnapshotStore.load() else { return true }
        return snap.updatedAt >= stored.updatedAt
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context[WatchLink.snapshotKey] as? Data,
              let snap = WatchLink.decode(WatchSnapshot.self, from: data),
              Self.isNewer(snap) else { return }
        // 落到手表本地 App Group 并刷新表盘复杂功能。
        WatchSnapshotStore.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
        Task { @MainActor in
            self.snapshot = snap
            self.requestPhotosIfMissing()
        }
    }

    // MARK: 照片包接收（表冠时光机的图）

    /// 手机 transferFile 过来的回忆照片包。解包失败保留旧缓存——半套照片比一套旧照片难看。
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?[WatchLink.photoBundleKey] != nil else { return }
        // fileURL 只在回调期间有效，必须同步读完。
        guard let data = try? Data(contentsOf: file.fileURL),
              let items = WatchPhotoBundle.decode(data), !items.isEmpty else { return }
        WatchPhotoStore.save(items)
        WidgetCenter.shared.reloadAllTimelines()
        Task { @MainActor in
            // 修剪时护住当前回忆序列还引用的图。
            var keep = Set((self.snapshot?.memories ?? []).compactMap(\.photoFileName))
            keep.formUnion((self.snapshot?.recent ?? []).compactMap(\.photoFileName))
            WatchPhotoStore.prune(keeping: keep)
            self.photoVersion += 1
        }
    }

    /// 快照里引用的照片缓存里没有（手表重装 / LRU 淘汰过头）→ 请求手机重发照片包。
    /// 手机侧的指纹去重会以为「上次发过了」，这条消息是打破僵局的唯一通道。
    private func requestPhotosIfMissing() {
        guard let snapshot else { return }
        let names = (snapshot.memories ?? []).compactMap(\.photoFileName)
            + snapshot.recent.compactMap(\.photoFileName)
        guard !names.isEmpty else { return }
        let missing = names.filter { WatchPhotoStore.data(for: $0) == nil }
        guard !missing.isEmpty else { return }

        // 同一批照片只请求一次（指纹按整批算，换批自然重新可请求）。
        let fingerprint = WatchPhotoBundle.fingerprint(names)
        guard !requestedFingerprints.contains(fingerprint) else { return }
        guard Date.now.timeIntervalSince(lastPhotoRequestAt) > 60 else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }

        requestedFingerprints.append(fingerprint)
        // 只记最近几批（FIFO）。之前用 Set 时 removeFirst 删的是任意元素，
        // 可能把刚记的当前指纹删掉导致重复请求整包。
        if requestedFingerprints.count > 8 { requestedFingerprints.removeFirst() }
        lastPhotoRequestAt = .now
        session.sendMessage([WatchLink.photoBundleRequestKey: true], replyHandler: nil)
    }
}
