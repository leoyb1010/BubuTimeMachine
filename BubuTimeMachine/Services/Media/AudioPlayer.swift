import Foundation
import AVFoundation
import Observation

// MARK: - 录音播放器
/// 播放沙盒中的语音文件，发布播放进度供 UI 波形高亮。
@Observable
@MainActor
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    private(set) var progress: Double = 0       // 0...1
    private(set) var playingURL: URL?

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(url: URL) {
        if isPlaying && playingURL == url {
            stop()
        } else {
            play(url: url)
        }
    }

    func play(url: URL) {
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            self.player = p
            self.playingURL = url
            self.isPlaying = true
            startTimer()
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        let wasActive = player != nil
        player?.stop()
        player = nil
        timer?.invalidate(); timer = nil
        isPlaying = false
        progress = 0
        playingURL = nil
        // 播放语音会用 .playback 抢占音频会话；结束时必须归还，
        // 否则用户原本在放的音乐/播客会被永久掐断。notifyOthersOnDeactivation 让别的音频恢复。
        if wasActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let player, player.duration > 0 else { return }
        progress = player.currentTime / player.duration
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
