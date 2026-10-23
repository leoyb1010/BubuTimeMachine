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
/// Decoded at the displayed pixel size (bucketed) so a grid of thumbnails stays small in memory.
/// While loading it shows a soft fill, never a spinner,
/// and the picture fades in — a screen of per-cell spinners reads as "slow" and pops one by one.
struct LearningRemoteImage: View {
    let path: String
    let client: BubuLearningClient
    var label = "画面"
    var contentMode: ContentMode = .fit
    var diskCache = false
    var maxHeight: CGFloat? = nil
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var imagePath = ""
    @State private var failed = false
    @State private var retry = 0
    @State private var autoRetried = false
    /// Longest side in pixels; 0 until the first layout.
    @State private var bucket = 0

    private var key: String { LearningImagePipeline.key(scope: client.scope, path: path, bucket: bucket) }

    var body: some View {
        let shown = cached ?? (imagePath == path ? image : nil)
        ZStack {
            if shown == nil {
                BubuTheme.Color.softFill.opacity(0.6)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
            if let shown {
                Image(uiImage: shown).resizable().aspectRatio(contentMode: contentMode)
                    .accessibilityLabel(label)
                    .transition(.opacity)
            } else if failed {
                VStack(spacing: BubuTheme.Spacing.s) {
                    Image(systemName: "photo.badge.exclamationmark").font(.title3)
                    Button("重新加载") { retry += 1 }.font(BubuTheme.Font.caption).buttonStyle(.bordered)
                        .accessibilityIdentifier("remote-image.retry")
                }
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: maxHeight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: shown != nil)
        .onGeometryChange(for: CGFloat.self) { max($0.size.width, $0.size.height) } action: { side in
            guard side > 0 else { return }
            // Only grow: a smaller layout reuses the sharper image already decoded.
            let wanted = LearningImageDecoder.bucket(forPixels: side * displayScale)
            if wanted > bucket { bucket = wanted }
        }
        .task(id: "\(key)|\(retry)") {
            guard bucket > 0, cached == nil || retry > 0 else { return }
            failed = false
            do {
                let decoded = try await LearningImagePipeline.load(path, client: client, bucket: bucket, diskCache: diskCache)
                try Task.checkCancellation()
                image = decoded
                imagePath = path
            } catch where isCancellation(error) {
            } catch {
                // One quiet retry for a slow or dropped connection before showing the reload button.
                if !autoRetried {
                    autoRetried = true
                    try? await Task.sleep(for: .seconds(1.5))
                    if !Task.isCancelled { retry += 1 }
                    return
                }
                failed = true
            }
        }
    }

    /// Any already-decoded copy at this size or sharper.
    private var cached: UIImage? {
        guard bucket > 0 else { return nil }
        return LearningImagePipeline.cached(scope: client.scope, path: path, atLeast: bucket)
    }

    /// Warms disk and memory for cells about to scroll into view (call from a row's `onAppear`).
    /// `pointSize` is the cell's longest side.
    static func prefetch(_ path: String, client: BubuLearningClient, pointSize: CGFloat, displayScale: CGFloat) async {
        await LearningImagePipeline.prefetch(path, client: client,
                                             bucket: LearningImageDecoder.bucket(forPixels: pointSize * displayScale))
    }
}

/// One thing to say during a lesson. Teacher clips still go through `NativeLearningPlaybackPolicy`;
/// narrator lines (greeting, praise, …) and choice names are explicit server lines, so they are always allowed.
/// A cue without audio is simply never created: its text is already on screen.
nonisolated struct NativeLearningCue: Sendable, Hashable {
    enum Kind: Sendable, Hashable { case prompt, answer, line, choice(String) }
    let path: String
    let kind: Kind

    static func clip(_ clip: LearningClipDTO?, activityKind: String, isAnswer: Bool) -> NativeLearningCue? {
        guard let clip,
              NativeLearningPlaybackPolicy.permits(role: clip.role, activityKind: activityKind, isAnswer: isAnswer),
              let path = clip.audioUrl, !path.isEmpty else { return nil }
        return NativeLearningCue(path: path, kind: isAnswer ? .answer : .prompt)
    }

    static func line(_ line: LearningLineDTO?) -> NativeLearningCue? {
        guard let path = line?.audioUrl, !path.isEmpty else { return nil }
        return NativeLearningCue(path: path, kind: .line)
    }

    static func choice(_ choice: LearningChoiceDTO) -> NativeLearningCue? {
        guard let path = choice.audioUrl, !path.isEmpty else { return nil }
        return NativeLearningCue(path: path, kind: .choice(choice.id))
    }
}

/// The single voice of a lesson: plays cues one after another through one AVPlayer.
/// A new request always stops the previous one (and any other learning player), so sounds never overlap.
/// Uses `.playback` — a lesson is something a parent starts on purpose, so it plays with the ring switch off.
@Observable @MainActor
final class NativeLearningAudioPlayer {
    private(set) var isLoading = false
    private(set) var isPlaying = false
    /// What is speaking right now (nil when silent).
    private(set) var current: NativeLearningCue.Kind?
    private(set) var progress = 0.0
    private(set) var errorText: String?
    private var player: AVPlayer?
    private var loadTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var itemObservers: [NSObjectProtocol] = []
    private var interruptionObserver: NSObjectProtocol?
    private var ending: CheckedContinuation<Bool, Never>?
    private var audioFile: URL?
    private var sessionActive = false
    private var generation = UUID()
    private static weak var active: NativeLearningAudioPlayer?

    var playingAnswer: Bool { current == .answer }
    var playingPrompt: Bool { current == .prompt }
    var playingLine: Bool { current == .line }
    var playingChoiceID: String? {
        if case .choice(let id) = current { return id }
        return nil
    }
    var isBusy: Bool { isLoading || isPlaying }

    /// One teacher clip; says so when the clip may not be played (parent review relies on this message).
    func play(clip: LearningClipDTO?, activityKind: String, isAnswer: Bool,
              client: BubuLearningClient) {
        guard let cue = NativeLearningCue.clip(clip, activityKind: activityKind, isAnswer: isAnswer) else {
            stop()
            errorText = "这段原声还不能播放，请让家长核对素材。"
            return
        }
        play([cue], client: client)
    }

    /// Plays the cues in order. A cue that fails to load is skipped so the lesson keeps going.
    func play(_ cues: [NativeLearningCue?], client: BubuLearningClient) {
        stop()
        errorText = nil
        let queue = cues.compactMap { $0 }
        guard !queue.isEmpty else { return }
        if let other = Self.active, other !== self { other.stop() }
        Self.active = self
        let attempt = UUID()
        generation = attempt
        isLoading = true
        loadTask = Task { [weak self] in
            var failed = false
            for cue in queue {
                guard let self, self.generation == attempt else { return }
                do {
                    try await self.playOne(cue, attempt: attempt, client: client)
                } catch {
                    guard self.generation == attempt, !isCancellation(error) else { return }
                    failed = true
                }
            }
            guard let self, self.generation == attempt else { return }
            self.stop()
            if failed { self.errorText = "有一句声音没放出来，可以再点一次试试。" }
        }
    }

    func stop() {
        generation = UUID()
        loadTask?.cancel(); loadTask = nil
        ending?.resume(returning: false); ending = nil
        teardownCurrent()
        isPlaying = false; isLoading = false; progress = 0; current = nil
        if sessionActive {
            sessionActive = false
            if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
            interruptionObserver = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        if Self.active === self { Self.active = nil }
    }

    private func playOne(_ cue: NativeLearningCue, attempt: UUID, client: BubuLearningClient) async throws {
        defer { if generation == attempt { teardownCurrent() } }
        current = cue.kind
        isLoading = true; isPlaying = false; progress = 0
        // Lesson clips are small and replayed often ("再听一次"), so they use the scoped media cache.
        let data = try await client.mediaData(cue.path, cache: true)
        try Task.checkCancellation()
        guard generation == attempt else { throw CancellationError() }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("bubu-learning-\(UUID().uuidString).m4a")
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        audioFile = file
        let asset = AVURLAsset(url: file)
        guard try await asset.load(.isPlayable) else { throw NativeLearningPlaybackError.unplayable }
        try Task.checkCancellation()
        guard generation == attempt else { throw CancellationError() }
        try activateSession()
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        self.player = player
        itemObservers = [
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.endCurrent(finished: true, attempt: attempt) }
            },
            NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.endCurrent(finished: false, attempt: attempt) }
            },
        ]
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, self.generation == attempt else { return }
                let duration = self.player?.currentItem?.duration.seconds ?? 0
                self.progress = duration.isFinite && duration > 0 ? min(max(time.seconds / duration, 0), 1) : 0
            }
        }
        isLoading = false
        isPlaying = true
        let finished = await withCheckedContinuation { continuation in
            ending = continuation
            player.play()
        }
        guard generation == attempt else { throw CancellationError() }
        if !finished { throw NativeLearningPlaybackError.unplayable }
    }

    private func activateSession() throws {
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        sessionActive = true
        // A phone call or Siri ends the lesson's sound instead of resuming mid-sentence later.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            guard began else { return }
            Task { @MainActor in self?.stop() }
        }
    }

    private func endCurrent(finished: Bool, attempt: UUID) {
        guard generation == attempt else { return }
        ending?.resume(returning: finished)
        ending = nil
    }

    private func teardownCurrent() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        itemObservers.forEach { NotificationCenter.default.removeObserver($0) }
        itemObservers = []
        player?.replaceCurrentItem(with: nil); player = nil
        if let audioFile { try? FileManager.default.removeItem(at: audioFile) }
        audioFile = nil
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
