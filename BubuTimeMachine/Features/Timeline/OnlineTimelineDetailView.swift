import SwiftUI
import AVKit

/// 左右滑动浏览已加载的专属时光；滑到末尾时继续加载下一页。
struct OnlineTimelineDetailPager: View {
    let client: BubuLearningClient
    let items: [OnlineTimelineItem]
    let initial: OnlineTimelineItem
    let loadMore: () async -> Void
    let hasMore: Bool
    @State private var current: String = ""

    var body: some View {
        TabView(selection: $current) {
            ForEach(items) { item in
                OnlineTimelineDetailPage(client: client, item: item, isCurrent: current == item.id)
                    .tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(BubuThemedBackground().ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if current.isEmpty { current = initial.id } }
        .onChange(of: current) { _, id in
            if hasMore, let index = items.firstIndex(where: { $0.id == id }), index >= items.count - 3 {
                Task { await loadMore() }
            }
        }
        .accessibilityIdentifier("timeline.detail")
    }

    private var title: String {
        guard let item = items.first(where: { $0.id == current }) ?? Optional(initial),
              let date = item.capturedDate else { return "布布的时光" }
        return date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
    }
}

struct OnlineTimelineDetailPage: View {
    let client: BubuLearningClient
    let item: OnlineTimelineItem
    let isCurrent: Bool
    @State private var player: AVPlayer?
    @State private var videoError: String?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
                media
                    .frame(maxWidth: .infinity)
                    .frame(height: BubuAdaptive.value(sizeClass, compact: 380, regular: 560))
                    .background(BubuTheme.Color.softFill.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                info
            }
            .padding(BubuTheme.Spacing.item)
            .bubuContentColumn(900)
        }
        .onChange(of: isCurrent) { _, active in if !active { player?.pause() } }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var media: some View {
        if item.isVideo {
            ZStack {
                if let player {
                    VideoPlayer(player: player).accessibilityIdentifier("timeline.video")
                } else if let videoError {
                    VStack(spacing: BubuTheme.Spacing.s) {
                        Image(systemName: "exclamationmark.triangle").font(.title2)
                        Text(videoError).font(BubuTheme.Font.caption).multilineTextAlignment(.center)
                        Button("重试") { Task { await prepareVideo() } }.buttonStyle(.bordered)
                    }.foregroundStyle(BubuTheme.Color.secondaryText).padding()
                } else {
                    LearningRemoteImage(path: item.largeUrl, client: client, label: "视频封面", contentMode: .fit)
                    Button { Task { await prepareVideo(autoplay: true) } } label: {
                        Image(systemName: "play.circle.fill").font(.system(size: 64))
                            .symbolRenderingMode(.palette).foregroundStyle(.white, BubuTheme.Color.primary)
                            .shadow(radius: 6)
                    }
                    .accessibilityLabel("播放视频")
                    .accessibilityIdentifier("timeline.video.play")
                }
            }
        } else {
            LearningRemoteImage(path: item.largeUrl, client: client,
                                label: item.description.isEmpty ? "布布的照片" : item.description, contentMode: .fit)
                .accessibilityIdentifier("timeline.photo")
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
            HStack(spacing: BubuTheme.Spacing.s) {
                Image(systemName: item.isVideo ? "video.fill" : "photo.fill").foregroundStyle(BubuTheme.Color.deepRose)
                Text(item.capturedDate?.formatted(.dateTime.year().month().day().weekday().hour().minute().locale(Locale(identifier: "zh_CN"))) ?? "拍摄时间未知")
                    .font(BubuTheme.Font.body.weight(.semibold))
                Spacer(minLength: 0)
            }
            Label(item.labelProvenanceText, systemImage: "brain.head.profile")
                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            if !item.description.isEmpty {
                section("画面解析") { Text(item.description).font(BubuTheme.Font.body).textSelection(.enabled) }
            }
            if !item.tags.isEmpty {
                section("标签") {
                    OnlineTimelineTags(tags: item.tags)
                }
            }
            if !item.ocr.isEmpty {
                section("画面里的文字") { Text(item.ocr).font(BubuTheme.Font.body).textSelection(.enabled) }
            }
            if !item.segments.isEmpty {
                section("视频里说了什么") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(item.segments) { segment in
                            Button {
                                Task {
                                    if player == nil { await prepareVideo() }
                                    await player?.seek(to: CMTime(seconds: segment.start, preferredTimescale: 600))
                                    player?.play()
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text(Self.timecode(segment.start)).font(.caption.monospacedDigit())
                                        .foregroundStyle(BubuTheme.Color.deepRose)
                                    Text(segment.text).font(BubuTheme.Font.body).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Text("以上是第二大脑的机器解析，可能有误；以原片为准。")
                .font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .foregroundStyle(BubuTheme.Color.warmBrown)
        .padding(BubuTheme.Spacing.item)
        .background(BubuTheme.Color.card.opacity(0.92), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(BubuTheme.Color.deepRose)
            content()
        }
    }

    private func prepareVideo(autoplay: Bool = false) async {
        videoError = nil
        do {
            let asset = try await client.authorizedAsset(item.mediaUrl)
            guard try await asset.load(.isPlayable) else { throw LearningServiceError.unavailableMedia }
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            self.player = player
            if autoplay && isCurrent { player.play() }
        } catch {
            videoError = learningErrorText(error, fallback: "视频暂时无法播放，请检查网络后重试。")
        }
    }

    static func timecode(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct OnlineTimelineTags: View {
    let tags: [String]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { ForEach(tags, id: \.self, content: tag) }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(stride(from: 0, to: tags.count, by: 3)), id: \.self) { start in
                    HStack(spacing: 6) { ForEach(tags[start..<min(start + 3, tags.count)], id: \.self, content: tag) }
                }
            }
        }
    }
    private func tag(_ text: String) -> some View {
        Text(text).font(BubuTheme.Font.caption)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(BubuTheme.Color.pinkSurface, in: Capsule())
    }
}
