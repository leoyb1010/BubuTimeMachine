import SwiftUI
import AVKit

/// 左右滑动浏览已加载的专属时光；滑到末尾时继续加载下一页。
struct OnlineTimelineDetailPager: View {
    let client: BubuLearningClient
    let items: [OnlineTimelineItem]
    let initial: OnlineTimelineItem
    let loadMore: () async -> Void
    let hasMore: Bool
    var onNotBubu: (String) -> Void = { _ in }
    @State private var current: String = ""

    var body: some View {
        TabView(selection: $current) {
            ForEach(items) { item in
                OnlineTimelineDetailPage(client: client, item: item, isCurrent: current == item.id, onNotBubu: onNotBubu)
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
        .sensoryFeedback(.selection, trigger: current)
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
    var onNotBubu: (String) -> Void = { _ in }
    @State private var player: AVPlayer?
    @State private var videoError: String?
    @State private var zoom: CGFloat = 1
    @State private var confirmNotBubu = false
    @State private var actionError: String?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
                media
                    .frame(maxWidth: .infinity)
                    .frame(height: mediaHeight)
                    .background(BubuTheme.Color.softFill.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                info
                TimelineSocialSection(client: client, itemID: item.id, active: isCurrent)
            }
            .padding(BubuTheme.Spacing.item)
            .bubuContentColumn(900)
        }
        .onChange(of: isCurrent) { _, active in if !active { player?.pause(); zoom = 1 } }
        .onDisappear {
            guard let player else { return }
            player.pause()
            // Let music or podcasts in other apps resume after a video.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        .confirmationDialog("这张里没有布布？", isPresented: $confirmNotBubu, titleVisibility: .visible) {
            Button("不是布布，移出时光", role: .destructive) { Task { await markNotBubu() } }
        } message: { Text("只会从布布的时光里移出，第二大脑的原片不受影响。") }
    }

    /// Portrait photos get more height instead of a wide empty frame.
    private var mediaHeight: CGFloat {
        let base: CGFloat = BubuAdaptive.value(sizeClass, compact: 380, regular: 560)
        return item.layoutAspect < 0.9 ? base * 1.25 : base
    }

    @ViewBuilder
    private var media: some View {
        if item.isVideo {
            ZStack {
                if let player {
                    VideoPlayer(player: player)
                        .accessibilityLabel(item.description.isEmpty ? "布布的视频" : "视频：\(item.description)")
                        .accessibilityIdentifier("timeline.video")
                } else if let videoError {
                    VStack(spacing: BubuTheme.Spacing.s) {
                        Image(systemName: "exclamationmark.triangle").font(BubuTheme.Font.headline)
                        Text(videoError).font(BubuTheme.Font.caption).multilineTextAlignment(.center)
                        Button("重试") { Task { await prepareVideo() } }.buttonStyle(.bordered)
                    }.foregroundStyle(BubuTheme.Color.secondaryText).padding()
                } else {
                    LearningRemoteImage(path: item.largeUrl, client: client,
                                        label: item.description.isEmpty ? "视频封面" : "视频封面：\(item.description)", contentMode: .fit)
                    Button { Task { await prepareVideo(autoplay: true) } } label: {
                        Image(systemName: "play.circle.fill").font(.system(size: 64, design: .rounded))
                            .symbolRenderingMode(.palette).foregroundStyle(.white, BubuTheme.Color.primary)
                            .shadow(color: BubuTheme.Color.deepRose.opacity(0.3), radius: 8)
                    }
                    .buttonStyle(BubuPressableStyle(scale: 0.9))
                    .accessibilityLabel("播放视频")
                    .accessibilityIdentifier("timeline.video.play")
                }
            }
        } else {
            LearningRemoteImage(path: item.largeUrl, client: client,
                                label: item.description.isEmpty ? "布布的照片" : item.description, contentMode: .fit)
                .scaleEffect(zoom)
                .gesture(MagnifyGesture()
                    .onChanged { zoom = min(max($0.magnification, 1), 4) }
                    .onEnded { _ in withAnimation(reduceMotion ? nil : BubuMotion.gentle) { zoom = 1 } })
                .onTapGesture(count: 2) { withAnimation(reduceMotion ? nil : BubuMotion.gentle) { zoom = zoom > 1 ? 1 : 2 } }
                .accessibilityAddTraits(.isImage)
                .accessibilityHint("双指捏合或轻点两下可以放大")
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
            HStack(spacing: BubuTheme.Spacing.s) {
                if let place = item.place, !place.isEmpty {
                    Label(place, systemImage: "mappin.and.ellipse")
                }
                if let people = item.people, !people.isEmpty {
                    Label("和" + people.joined(separator: "、"), systemImage: "person.2.fill")
                }
            }
            .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            Label(item.confirmedByFamily == true ? "家人在「认一认」里确认过" : item.labelProvenanceText, systemImage: "brain.head.profile")
                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            if !item.description.isEmpty {
                section("画面解析") { Text(item.description).font(BubuTheme.Font.body).textSelection(.enabled) }
            }
            if !item.tags.isEmpty {
                section("标签") { OnlineTimelineTags(tags: item.tags) }
            }
            if !item.ocr.isEmpty {
                section("画面里的文字") { Text(item.ocr).font(BubuTheme.Font.body).textSelection(.enabled) }
            }
            if !item.segments.isEmpty || (item.transcriptHidden ?? 0) > 0 {
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
                                    Text(Self.timecode(segment.start)).font(BubuTheme.Font.caption.monospacedDigit())
                                        .foregroundStyle(BubuTheme.Color.deepRose)
                                    Text(segment.text).font(BubuTheme.Font.body).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .buttonStyle(BubuPressableStyle())
                            .accessibilityLabel("\(Self.timecode(segment.start))，\(segment.text)")
                            .accessibilityHint("从这里播放视频")
                        }
                        if let hidden = item.transcriptHidden, hidden > 0 {
                            Text("另有 \(hidden) 段听不清（多半是童言童语或英文），先不显示。")
                                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                    }
                }
            }
            HStack {
                Text("以上是第二大脑的机器解析，可能有误；以原片为准。")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                Spacer(minLength: 8)
                Button("不是布布？") { confirmNotBubu = true }
                    .font(BubuTheme.Font.caption.weight(.semibold)).tint(BubuTheme.Color.deepRose)
                    .accessibilityHint("把这张从布布的时光里移出")
                    .accessibilityIdentifier("timeline.not-bubu")
            }
            if let actionError {
                Text(actionError).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.danger)
            }
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

    private nonisolated struct Decision: Encodable, Sendable { let decision: String }
    private nonisolated struct Decided: Decodable, Sendable {}

    private func markNotBubu() async {
        actionError = nil
        do {
            _ = try await client.send("POST", "api/recognition/\(item.id)", body: Decision(decision: "no"), as: Decided.self)
            BubuHaptics.success()
            onNotBubu(item.id)
        } catch {
            actionError = learningErrorText(error, fallback: "没有移出成功，请稍后再试（需要家长账号）。")
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

struct OnlineTimelineTags: View {
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
