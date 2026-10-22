import SwiftUI
import AVFoundation
import Observation

/// Plays one protected voice clip (`voices/{id}/audio`) at a time. Errors are kept on the
/// player so a screen can show them whether or not its list is empty.
@Observable @MainActor
final class SecondBrainVoicePlayer {
    private(set) var playing: String?
    private(set) var loading: String?
    var errorText: String?
    private var player: AVPlayer?
    private var generation = UUID()

    static func audioPath(voiceID: String) -> String { "api/voices/\(voiceID)/audio" }

    func toggle(id: String, path: String, client: BubuLearningClient, duration: Double? = nil) async {
        if playing == id || loading == id { stop(); return }
        stop()
        let token = UUID()
        generation = token
        loading = id
        errorText = nil
        do {
            let data = try await client.mediaData(path, cache: true)
            guard generation == token else { return }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("bubu-voice-\(String(id.filter { $0.isLetter || $0.isNumber }.prefix(40))).m4a")
            try data.write(to: file, options: .atomic)
            let asset = AVURLAsset(url: file)
            var length = duration ?? 0
            if duration == nil { length = try await asset.load(.duration).seconds }
            guard generation == token else { return }
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            self.player = player
            loading = nil
            playing = id
            player.play()
            BubuHaptics.tapLight()
            let seconds = length.isFinite && length > 0 ? length : 3
            try? await Task.sleep(for: .seconds(seconds + 0.4))
            if generation == token { stop() }
        } catch {
            guard generation == token else { return }
            loading = nil
            errorText = learningErrorText(error, fallback: "这段声音暂时放不出来，请稍后再试。")
        }
    }

    func stop() {
        generation = UUID()
        let wasActive = player != nil
        player?.pause()
        player = nil
        playing = nil
        loading = nil
        if wasActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}

/// Small dismissible error line used across the 2.26 screens.
struct SecondBrainErrorBanner: View {
    let text: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: BubuTheme.Spacing.s) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(BubuTheme.Color.danger)
            Text(text).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.warmBrown)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark").font(BubuTheme.Font.caption.weight(.bold)) }
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .accessibilityLabel("关闭提示")
            }
        }
        .padding(BubuTheme.Spacing.m)
        .background(BubuTheme.Color.pinkSurface, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Shown when the family service isn't connected (2.26 screens).
struct SecondBrainNotConnected: View {
    let title: String
    var body: some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            BubuEmptyIllustration(assetName: "BubuEmptyTimeline", size: 130)
            Text("连接家庭服务后才能看「\(title)」。").font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }
}

/// Opening the shared pager from a strip of items.
nonisolated struct TimelinePagerRoute: Hashable, Identifiable, Sendable {
    let items: [OnlineTimelineItem]
    let initial: OnlineTimelineItem
    var id: String { initial.id + "|" + String(items.count) }
}

/// Square thumbnail button used by the 2.26 grids and strips.
struct SecondBrainThumb: View {
    let item: OnlineTimelineItem
    let client: BubuLearningClient
    var width: CGFloat? = nil
    var height: CGFloat = 120

    var body: some View {
        Color.clear
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .overlay {
                LearningRemoteImage(path: item.previewUrl, client: client,
                                    label: item.description.isEmpty ? "布布的照片" : item.description,
                                    contentMode: .fill, diskCache: true)
            }
            .overlay(alignment: .bottomTrailing) {
                if item.isVideo {
                    Image(systemName: "play.circle.fill").font(BubuTheme.Font.headline)
                        .symbolRenderingMode(.palette).foregroundStyle(.white, BubuTheme.Color.actionFill)
                        .padding(6).accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((item.isVideo ? "视频：" : "照片：") + (item.description.isEmpty ? "布布的时光" : item.description))
            .accessibilityAddTraits(.isButton)
    }
}
