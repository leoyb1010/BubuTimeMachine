import Foundation
import AVFoundation
import Observation

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
            rec.record()
            self.recorder = rec
            self.currentURL = url
            self.state = .recording
            self.elapsed = 0
            self.levels = []
            startTimer()
            return true
        } catch {
            return false
        }
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
        try? AVAudioSession.sharedInstance().setActive(false)
        return (url, duration, waveform)
    }

    func cancel() {
        recorder?.stop()
        if let url = currentURL { try? FileManager.default.removeItem(at: url) }
        timer?.invalidate(); timer = nil
        recorder = nil; currentURL = nil
        state = .idle
        elapsed = 0
        levels = []
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
