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
    func sendText(_ note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        send(WatchRecordRequest(type: .text, roleRaw: roleRaw, note: trimmed), label: "已记下")
    }

    func sendMood(rawValue: String, emoji: String) {
        send(WatchRecordRequest(type: .mood, roleRaw: roleRaw,
                                note: "\(emoji) \(rawValue)", moodRaw: rawValue), label: "已记下心情")
    }

    func sendHealth(kindRaw: String, title: String) {
        send(WatchRecordRequest(type: .health, roleRaw: roleRaw,
                                healthKindRaw: kindRaw, healthTitle: title), label: "已打卡")
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
        flash("语音已送到手机")
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

    private func flash(_ label: String) {
        lastSentLabel = label
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if lastSentLabel == label { lastSentLabel = nil }
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
        if let snap {
            WatchSnapshotStore.save(snap)
            WidgetCenter.shared.reloadAllTimelines()
        }
        let restored = snap
        let activated = (state == .activated)
        Task { @MainActor in
            if self.snapshot == nil, let restored { self.snapshot = restored }
            // 激活完成：补发缓存的记录 + 对账残留语音（#6 / P0-2 / W-P1-1 的重发入口）。
            if activated { self.reconcilePending() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context[WatchLink.snapshotKey] as? Data,
              let snap = WatchLink.decode(WatchSnapshot.self, from: data) else { return }
        // 落到手表本地 App Group 并刷新表盘复杂功能。
        WatchSnapshotStore.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
        Task { @MainActor in self.snapshot = snap }
    }
}
