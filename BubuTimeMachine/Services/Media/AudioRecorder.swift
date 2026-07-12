import Foundation
import AVFoundation
import Observation
import UIKit

// MARK: - 录音器
/// AVFoundation 录音，输出 .m4a 到沙盒，实时采集电平用于波形可视化。
/// 适老化：一键开始/停止，状态清晰。
@Observable
@MainActor
final class AudioRecorder: NSObject {
    enum State: Equatable { case idle, recording, finished }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels: [Float] = []      // 实时电平（0...1），驱动波形

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentURL: URL?
    private var interruptionObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?

    /// 来电/闹钟等中断时自动收尾保留的录音（UI 观察到后当作正常 stop 结果处理，已录的不丢）。
    private(set) var interruptedResult: (url: URL, duration: TimeInterval, waveform: [Float])?

    func consumeInterruptedResult() -> (url: URL, duration: TimeInterval, waveform: [Float])? {
        defer { interruptedResult = nil }
        return interruptedResult
    }

    /// 请求麦克风权限。
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// 开始录音。返回是否成功启动。
    @discardableResult
    func start() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch { return false }

        let fileName = "voice_\(UUID().uuidString).m4a"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.isMeteringEnabled = true
            guard rec.record() else { return false }   // 启动失败要如实返回，不装录着
            self.recorder = rec
            self.currentURL = url
            self.state = .recording
            self.elapsed = 0
            self.levels = []
            startTimer()
            observeInterruptions()
            observeBackgrounding()
            // 录音中 Live Activity（灵动岛/锁屏可见时长）；未授权时安静 no-op。
            BubuActivityController.startVoiceRecording(childName: SharedDefaults.childName)
            return true
        } catch {
            return false
        }
    }

    /// 来电/闹钟/Siri 中断：自动收尾并保留已录部分——
    /// 之前没有任何处理，来电后系统已停录，用户以为还在录，后半段静默丢失（R4 P2-37）。
    private func observeInterruptions() {
        removeInterruptionObserver()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: typeRaw) == .began else { return }
            Task { @MainActor in
                guard let self, self.state == .recording else { return }
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

    /// 进后台自动收尾：录音中锁屏/切后台，App 被系统挂起时录音停止，但这不是 AVAudioSession
    /// 打断，interruptionNotification 不触发；若不处理，回前台 UI 仍显示录音中、Live Activity 时长
    /// 照跳，且后半段静默丢失（W-P1-3）。此处进后台主动 stop() 保存已录部分，走与打断收尾同一路径
    /// （复位 state/isRecording + 结束 Live Activity），UI 的 .onChange(state==.finished) 照常导入。
    /// 不加 audio 后台模式（避免 App Review 风险），改用自动收尾。
    private func observeBackgrounding() {
        removeBackgroundObserver()
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .recording else { return }
                self.interruptedResult = self.stop()
            }
        }
    }

    private func removeBackgroundObserver() {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        backgroundObserver = nil
    }

    /// 停止录音，返回（临时文件 URL、时长、波形采样）。
    @discardableResult
    func stop() -> (url: URL, duration: TimeInterval, waveform: [Float])? {
        guard let recorder, let url = currentURL else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        timer?.invalidate()
        timer = nil
        state = .finished
        let waveform = downsample(levels, to: 40)
        self.recorder = nil
        removeInterruptionObserver()
        removeBackgroundObserver()
        try? AVAudioSession.sharedInstance().setActive(false)
        BubuActivityController.endVoiceRecording(elapsedText: Self.timeText(duration))
        return (url, duration, waveform)
    }

    func cancel() {
        recorder?.stop()
        if let url = currentURL { try? FileManager.default.removeItem(at: url) }
        timer?.invalidate(); timer = nil
        recorder = nil; currentURL = nil
        removeInterruptionObserver()
        removeBackgroundObserver()
        state = .idle
        elapsed = 0
        levels = []
        BubuActivityController.endVoiceRecording(elapsedText: "0:00")
    }

    /// 秒数 → "m:ss"。
    nonisolated static func timeText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let recorder, state == .recording else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)   // dB, -160...0
        let normalized = max(0, (power + 60) / 60)          // 映射到 0...1
        levels.append(normalized)
        elapsed = recorder.currentTime
    }

    /// 将密集电平降采样为固定数量的波形条。
    private func downsample(_ samples: [Float], to count: Int) -> [Float] {
        guard samples.count > count, count > 0 else { return samples }
        let bucket = samples.count / count
        return (0..<count).map { i in
            let slice = samples[(i * bucket)..<min((i + 1) * bucket, samples.count)]
            return slice.isEmpty ? 0 : slice.reduce(0, +) / Float(slice.count)
        }
    }
}
