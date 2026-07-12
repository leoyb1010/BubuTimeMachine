import Foundation
import AVFoundation
import Observation

// MARK: - 手表录音（AVAudioRecorder）
/// 抬腕说一句：录成 m4a，交给 WatchConnector 送手机。权限拒绝时给出提示，不崩。
/// 录音落 Application Support/PendingVoice/（持久，见 WatchPendingVoiceStore）——不放 tmp，
/// 避免后台排队传输期间被系统清空导致两端丢失。
@MainActor
@Observable
final class WatchVoiceRecorder: NSObject {
    var isRecording = false
    var permissionDenied = false
    private var isStarting = false     // 门闩：start() 有 await，防止录音启动窗口内二次进入孤立 recorder
    private var recorder: AVAudioRecorder?
    private(set) var fileURL: URL?
    private var interruptionObserver: NSObjectProtocol?

    /// 来电/Siri 等打断时自动收尾保留的录音（View 观察到后当作正常 stop 结果发送，已录的不丢）。
    private(set) var interruptedResult: (url: URL, duration: Double)?

    func consumeInterruptedResult() -> (url: URL, duration: Double)? {
        defer { interruptedResult = nil }
        return interruptedResult
    }

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

        // 直接写持久目录（stem 即 localId，稳定幂等键），录音从不落 tmp。
        let url = WatchPendingVoiceStore.newFileURL()
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
            isRecording = true
            observeInterruptions()
        } catch {
            isRecording = false
        }
    }

    /// 取消录音（离页时兜底）：停录、丢弃文件、复位状态、反激活会话。
    func cancel() {
        guard isRecording else { return }
        recorder?.stop()
        recorder = nil
        isRecording = false
        removeInterruptionObserver()
        if let url = fileURL { WatchPendingVoiceStore.remove(fileURL: url) }
        fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stop() -> (url: URL, duration: Double)? {
        guard let rec = recorder else { isRecording = false; return nil }
        // 时长用 AVAudioRecorder.currentTime（实际录音时长，挂起/打断不虚增）；必须在 stop() 前读，
        // 否则停录后归零。旧代码用 Date()-startedAt 墙钟，打断后与真实音频长度不符。
        let duration = rec.currentTime
        rec.stop()
        recorder = nil
        isRecording = false
        removeInterruptionObserver()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url = fileURL else { return nil }
        fileURL = nil
        // 太短（误触）直接丢弃（连同边车，此时通常还没边车，remove 幂等）。
        guard duration >= 0.6 else { WatchPendingVoiceStore.remove(fileURL: url); return nil }
        return (url, duration)
    }

    /// 来电/Siri 等打断：自动收尾并保留已录部分，复位 isRecording——
    /// 之前打断后 isRecording 仍为 true、后半段静默丢失（W-P2）。
    private func observeInterruptions() {
        removeInterruptionObserver()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: typeRaw) == .began else { return }
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.interruptedResult = self.stop()
            }
        }
    }

    private func removeInterruptionObserver() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }
}
