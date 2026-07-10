import Foundation
import AVFoundation
import Observation

// MARK: - 手表录音（AVAudioRecorder）
/// 抬腕说一句：录成 m4a，交给 WatchConnector 送手机。权限拒绝时给出提示，不崩。
@MainActor
@Observable
final class WatchVoiceRecorder: NSObject {
    var isRecording = false
    var permissionDenied = false
    private var isStarting = false     // 门闩：start() 有 await，防止录音启动窗口内二次进入孤立 recorder
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private(set) var fileURL: URL?

    func toggle() async -> (url: URL, duration: Double)? {
        if isRecording { return stop() }
        await start()
        return nil
    }

    private func start() async {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        let granted = await requestPermission()
        guard granted else { permissionDenied = true; return }
        permissionDenied = false
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bubu-watch-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.record()
            recorder = rec
            fileURL = url
            startedAt = Date()
            isRecording = true
        } catch {
            isRecording = false
        }
    }

    /// 取消录音（离页/中断时兜底）：停录、丢弃文件、复位状态、反激活会话。
    func cancel() {
        guard isRecording else { return }
        recorder?.stop()
        recorder = nil
        isRecording = false
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stop() -> (url: URL, duration: Double)? {
        recorder?.stop()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url = fileURL else { return nil }
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        recorder = nil
        // 太短（误触）直接丢弃
        guard duration >= 0.6 else { try? FileManager.default.removeItem(at: url); return nil }
        return (url, duration)
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }
}
