import SwiftUI
import AVFoundation
import Observation
import UIKit

/// Only the server-provided question/cue may be used as a prompt. Answers need an explicit action.
nonisolated enum NativeLearningPlaybackPolicy {
    static func permits(role: String, activityKind: String, isAnswer: Bool) -> Bool {
        if isAnswer { return role == "answer" }
        return activityKind == "music" ? role == "context" : ["question", "cue"].contains(role)
    }
}

/// Authenticated media is loaded through the client, never through an unauthenticated AsyncImage URL.
struct LearningRemoteImage: View {
    let path: String
    let client: BubuLearningClient
    var label = "画面"
    var contentMode: ContentMode = .fit
    var diskCache = false
    var maxHeight: CGFloat? = nil
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retry = 0

    private var key: String { client.scope + "|" + path }

    var body: some View {
        ZStack {
            if let image = image ?? LearningImageMemory.shared.image(key) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                    .accessibilityLabel(label)
            } else if failed {
                VStack(spacing: BubuTheme.Spacing.s) {
                    Image(systemName: "photo.badge.exclamationmark").font(.title3)
                    Button("重新加载") { retry += 1 }.font(BubuTheme.Font.caption).buttonStyle(.bordered)
                }
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: maxHeight)
        .task(id: "\(key)|\(retry)") {
            guard LearningImageMemory.shared.image(key) == nil || retry > 0 else { return }
            failed = false
            do {
                let data = try await client.mediaData(path, cache: diskCache)
                try Task.checkCancellation()
                guard let decoded = await Self.decode(data) else { failed = true; return }
                LearningImageMemory.shared.store(decoded, for: key)
                image = decoded
            } catch is CancellationError {} catch { failed = true }
        }
    }

    @concurrent
    private static func decode(_ data: Data) async -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        return await image.byPreparingForDisplay() ?? image
    }
}

/// A single AVPlayer owns the current short original clip. No TTS or automatic answer playback.
@Observable @MainActor
final class NativeLearningAudioPlayer {
    private(set) var isLoading = false
    private(set) var isPlaying = false
    private(set) var playingAnswer = false
    private(set) var progress = 0.0
    private(set) var errorText: String?
    private var player: AVPlayer?
    private var loadTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var endedObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var audioFile: URL?
    private var generation = UUID()
    private static weak var active: NativeLearningAudioPlayer?

    func play(clip: LearningClipDTO?, activityKind: String, isAnswer: Bool,
              client: BubuLearningClient) {
        stop()
        guard let clip,
              NativeLearningPlaybackPolicy.permits(role: clip.role, activityKind: activityKind, isAnswer: isAnswer),
              let path = clip.audioUrl, !path.isEmpty else {
            errorText = "这段原声还不能播放，请让家长核对素材。"
            return
        }
        if let other = Self.active, other !== self { other.stop() }
        Self.active = self
        let attempt = UUID()
        generation = attempt
        playingAnswer = isAnswer
        isLoading = true
        errorText = nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            var temporary: URL?
            do {
                let data = try await client.mediaData(path)
                try Task.checkCancellation()
                guard self.generation == attempt else { return }
                let file = FileManager.default.temporaryDirectory
                    .appendingPathComponent("bubu-learning-\(UUID().uuidString).m4a")
                temporary = file
                try data.write(to: file, options: [.atomic, .completeFileProtection])
                let asset = AVURLAsset(url: file)
                guard try await asset.load(.isPlayable) else { throw NativeLearningPlaybackError.unplayable }
                try Task.checkCancellation()
                guard self.generation == attempt else {
                    try? FileManager.default.removeItem(at: file)
                    return
                }
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio)
                try session.setActive(true)
                let item = AVPlayerItem(asset: asset)
                let player = AVPlayer(playerItem: item)
                self.audioFile = file
                self.player = player
                self.endedObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
                ) { [weak self] _ in Task { @MainActor in self?.finish(generation: attempt) } }
                self.failedObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        guard self?.generation == attempt else { return }
                        self?.stop()
                        self?.errorText = "这段原声没有播放完成，请再试一次。"
                    }
                }
                self.timeObserver = player.addPeriodicTimeObserver(
                    forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
                ) { [weak self] time in
                    Task { @MainActor in
                        guard let self, self.generation == attempt else { return }
                        let duration = self.player?.currentItem?.duration.seconds ?? 0
                        self.progress = duration.isFinite && duration > 0 ? min(max(time.seconds / duration, 0), 1) : 0
                    }
                }
                self.isLoading = false
                self.isPlaying = true
                player.play()
            } catch {
                if let temporary { try? FileManager.default.removeItem(at: temporary) }
                guard self.generation == attempt else { return }
                self.stop()
                if !(error is CancellationError) {
                    self.errorText = "原声暂时无法播放，请检查连接后重试。"
                }
            }
        }
    }

    func stop() {
        generation = UUID()
        loadTask?.cancel(); loadTask = nil
        let hadPlayer = player != nil
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endedObserver { NotificationCenter.default.removeObserver(endedObserver) }
        if let failedObserver { NotificationCenter.default.removeObserver(failedObserver) }
        endedObserver = nil; failedObserver = nil
        player?.replaceCurrentItem(with: nil); player = nil
        if let audioFile { try? FileManager.default.removeItem(at: audioFile) }
        audioFile = nil
        isPlaying = false; isLoading = false; progress = 0
        if hadPlayer {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        if Self.active === self { Self.active = nil }
    }

    private func finish(generation: UUID) {
        guard self.generation == generation else { return }
        stop()
    }
}

private enum NativeLearningPlaybackError: Error { case unplayable }


/// Section card for learning screens: BubuTheme fonts (follows Dynamic Type), warm surfaces, dark-mode aware.
struct LearningPanel<Content: View>: View {
    let title: String
    let symbol: String
    var subtitle = ""
    var accent: Color = BubuTheme.Color.deepRose
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.s) {
            HStack(spacing: BubuTheme.Spacing.s) {
                Image(systemName: symbol).font(BubuTheme.Font.headline).foregroundStyle(accent)
                Text(title).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer(minLength: 0)
                if !subtitle.isEmpty {
                    Text(subtitle).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText).lineLimit(1)
                }
            }
            content
        }
        .padding(BubuTheme.Spacing.item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.card.opacity(0.92), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }
}
