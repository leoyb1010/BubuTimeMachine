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
        let req = WatchRecordRequest(type: .voice, roleRaw: roleRaw, voiceDuration: duration)
        guard let data = WatchLink.encode(req), let json = String(data: data, encoding: .utf8) else { return }
        WCSession.default.transferFile(fileURL, metadata: [WatchLink.fileMetaKey: json])
        flash("语音已送到手机")
    }

    /// 传输完成后清理临时 m4a（否则 tmp 会堆积）。
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }

    private func send(_ request: WatchRecordRequest, label: String) {
        guard let data = WatchLink.encode(request) else { return }
        let session = WCSession.default
        if session.isReachable {
            // 即时送达；失败则排队补发，双保险。
            session.sendMessage([WatchLink.recordKey: data], replyHandler: nil) { _ in
                session.transferUserInfo([WatchLink.recordKey: data])
            }
        } else {
            session.transferUserInfo([WatchLink.recordKey: data])   // 排队，联网自动补传
        }
        flash(label)
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
        let ctx = session.receivedApplicationContext
        if let data = ctx[WatchLink.snapshotKey] as? Data,
           let snap = WatchLink.decode(WatchSnapshot.self, from: data) {
            WatchSnapshotStore.save(snap)
            WidgetCenter.shared.reloadAllTimelines()
            Task { @MainActor in if self.snapshot == nil { self.snapshot = snap } }
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
