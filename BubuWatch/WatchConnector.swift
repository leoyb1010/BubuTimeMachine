import Foundation
import WatchConnectivity
import Observation
import WidgetKit

/// Read-only photo delivery. No method can create a new record or recording.
@MainActor @Observable
final class WatchConnector: NSObject {
    var snapshot: WatchSnapshot?
    var photoVersion = 0
    private var photoRequestGate = WatchPhotoRequestGate()

    override init() {
        super.init()
        snapshot = WatchSnapshotStore.load()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func reconcilePending() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        requestPhotosIfMissing()
        // Transitional drain only: resend previously recorded files, never create
        // new audio/metadata or delete a source before a matching durable receipt.
        let outstanding = Set(session.outstandingFileTransfers.map { $0.file.fileURL.standardizedFileURL })
        for file in WatchPendingVoiceStore.pendingFiles() where !outstanding.contains(file.standardizedFileURL) {
            guard let request = WatchPendingVoiceStore.readSidecar(forFile: file),
                  let data = WatchLink.encode(request), let json = String(data: data, encoding: .utf8) else { continue }
            session.transferFile(file, metadata: [WatchLink.fileMetaKey: json])
        }
    }

    private func requestPhotosIfMissing() {
        let names = WatchReadModel.memories(from: snapshot).compactMap(\.photoFileName)
        guard !names.isEmpty, names.contains(where: { WatchPhotoStore.data(for: $0) == nil }) else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        let fingerprint = WatchPhotoBundle.fingerprint(names)
        guard photoRequestGate.begin(fingerprint: fingerprint, at: .now) else { return }
        session.sendMessage([WatchLink.photoBundleRequestKey: true], replyHandler: nil) { [weak self] _ in
            Task { @MainActor [weak self] in self?.photoRequestGate.failed(fingerprint: fingerprint) }
        }
    }
}

extension WatchConnector: WCSessionDelegate {
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in if reachable { self?.reconcilePending() } }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext[WatchLink.snapshotKey] as? Data
        let restored = data.flatMap { WatchLink.decode(WatchSnapshot.self, from: $0) }
        if let restored, Self.isNewer(restored) {
            WatchSnapshotStore.save(restored)
            WidgetCenter.shared.reloadAllTimelines()
        }
        let activated = state == .activated
        Task { @MainActor in
            if let restored, restored.updatedAt >= (self.snapshot?.updatedAt ?? .distantPast) {
                self.snapshot = restored
            }
            if activated { self.reconcilePending() }
        }
    }

    nonisolated static func isNewer(_ snapshot: WatchSnapshot) -> Bool {
        guard let stored = WatchSnapshotStore.load() else { return true }
        return snapshot.updatedAt >= stored.updatedAt
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context[WatchLink.snapshotKey] as? Data,
              let snapshot = WatchLink.decode(WatchSnapshot.self, from: data), Self.isNewer(snapshot) else { return }
        WatchSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        Task { @MainActor in
            guard snapshot.updatedAt >= (self.snapshot?.updatedAt ?? .distantPast) else { return }
            self.snapshot = snapshot
            self.requestPhotosIfMissing()
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?[WatchLink.photoBundleKey] != nil,
              let data = try? Data(contentsOf: file.fileURL),
              let items = WatchPhotoBundle.decode(data), !items.isEmpty else { return }
        WatchPhotoStore.save(items)
        WidgetCenter.shared.reloadAllTimelines()
        Task { @MainActor in
            WatchPhotoStore.prune(keeping: Set(WatchReadModel.memories(from: self.snapshot).compactMap(\.photoFileName)))
            self.photoVersion += 1
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[WatchLink.voiceReceiptKey] as? Data,
              let receipt = WatchLink.decode(WatchVoiceReceipt.self, from: data) else { return }
        WatchPendingVoiceStore.consume(receipt)
    }
}
