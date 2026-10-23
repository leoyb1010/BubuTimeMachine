import SwiftUI
import AVKit

/// The photo pager over the shared stream: reads `feed`, so new pages and removals show up as they land.
struct OnlineTimelineFeedDetail: View {
    let client: BubuLearningClient
    let feed: OnlineTimelineFeed
    let initial: OnlineTimelineItem
    var onCurrentChange: (String) -> Void = { _ in }

    var body: some View {
        OnlineTimelineDetailPager(client: client, items: feed.items, initial: initial,
                                  loadMore: { await feed.loadMore() }, hasMore: feed.hasMore,
                                  onNotBubu: { id in feed.remove(id) }, onCurrentChange: onCurrentChange)
    }
}

/// Where the pager sits (global coordinates) and its safe-area insets.
private nonisolated struct OnlineDetailPagerGeometry: Equatable, Sendable {
    var frame: CGRect = .zero
    var insets = EdgeInsets()
}

/// Full-screen, swipe-through view of the loaded timeline items; loads the next page near the end.
/// Photos fill the screen on black with real pinch / double-tap zoom and pan; one tap hides the chrome;
/// the analysis and family comments open in a sheet so nothing scrolls against the pager.
/// Under a vertical fold (iPhone Duo half open like a book) a photo is never split: it fills the pane before the
/// fold and its analysis and comments sit in the pane after it.
struct OnlineTimelineDetailPager: View {
    let client: BubuLearningClient
    let items: [OnlineTimelineItem]
    let initial: OnlineTimelineItem
    let loadMore: () async -> Void
    let hasMore: Bool
    var onNotBubu: (String) -> Void
    /// Called with the id of the page in front whenever it changes, so the zoom-back lands on the photo being viewed.
    var onCurrentChange: (String) -> Void
    /// Shown in the pane after a book fold, beside the stream, instead of pushed full screen: no navigation bar of
    /// its own (a small bar over the photo instead), and a new `initial` (another photo tapped) turns to that page.
    var embedded = false
    /// Embedded only: the bar's close button, which clears the stream's selection.
    var onClose: () -> Void = {}
    @State private var state: OnlineDetailPagerState
    @State private var prefetches: [String: Task<Void, Never>] = [:]
    @State private var geometry = OnlineDetailPagerGeometry()
    @Environment(\.bubuLayout) private var screen
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(client: BubuLearningClient, items: [OnlineTimelineItem], initial: OnlineTimelineItem,
         loadMore: @escaping () async -> Void, hasMore: Bool, onNotBubu: @escaping (String) -> Void = { _ in },
         onCurrentChange: @escaping (String) -> Void = { _ in }, embedded: Bool = false,
         onClose: @escaping () -> Void = {}) {
        self.client = client
        self.items = items
        self.initial = initial
        self.loadMore = loadMore
        self.hasMore = hasMore
        self.onNotBubu = onNotBubu
        self.onCurrentChange = onCurrentChange
        self.embedded = embedded
        self.onClose = onClose
        _state = State(initialValue: OnlineDetailPagerState(current: initial.id))
    }

    var body: some View {
        if embedded {
            pager
                .overlay(alignment: .topTrailing) { if state.chromeVisible { paneBar.transition(.opacity) } }
                .animation(BubuMotion.allowed(BubuMotion.quick, reduceMotion: reduceMotion), value: state.chromeVisible)
                .onChange(of: initial.id) { _, id in if state.current != id { state.current = id } }
        } else {
            pager
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Under a fold the analysis is already on screen beside the photo.
                    if state.split == nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button { state.infoID = state.current } label: { Label("解析与评论", systemImage: "info.circle") }
                                .accessibilityIdentifier("timeline.detail.info")
                        }
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarVisibility(state.chromeVisible ? .visible : .hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
                .statusBarHidden(!state.chromeVisible)
                .animation(BubuMotion.allowed(BubuMotion.quick, reduceMotion: reduceMotion), value: state.chromeVisible)
        }
    }

    /// The pane's own bar (it sits under the stream's navigation bar, so it has none): analysis and comments, close.
    private var paneBar: some View {
        HStack(spacing: BubuTheme.Spacing.s) {
            // Under a fold inside the pane the analysis is already on screen beside the photo.
            if state.split == nil {
                Button("解析与评论", systemImage: "info.circle") { state.infoID = state.current }
                    .accessibilityIdentifier("timeline.detail.info")
            }
            Button(role: .close) { onClose() }
                .accessibilityLabel("关闭")
                .accessibilityIdentifier("timeline.detail.close")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .padding(BubuTheme.Spacing.s)
    }

    private var pager: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            OnlineDetailPageController(items: items, state: state) { item in
                // Hosted pages sit outside this view's environment; hand over what they read.
                AnyView(OnlineDetailPageHost(client: client, item: item, state: state, onNotBubu: onNotBubu)
                    .environment(env)
                    .environment(\.locale, locale))
            }
            .ignoresSafeArea()
        }
        .onGeometryChange(for: OnlineDetailPagerGeometry.self) { proxy in
            OnlineDetailPagerGeometry(frame: proxy.frame(in: .global), insets: proxy.safeAreaInsets)
        } action: { geometry = $0 }
        // Pages are hosted outside this view's environment: what they lay out by goes through the shared state.
        .onChange(of: foldSplit, initial: true) { _, split in state.split = split }
        .bubuOnToolbarVerticalEdgeChange { edge in state.extendsUnderBar = edge != nil && !embedded }
        .task(id: "\(state.current)|\(pageSide > 0)") {
            prefetchNeighbours()
            if hasMore, let index = items.firstIndex(where: { $0.id == state.current }), index >= items.count - 3 {
                await loadMore()
            }
        }
        .onChange(of: items.map(\.id)) { old, ids in
            guard !ids.contains(state.current) else { return }
            // The page in front was removed ("不是布布"): show its neighbour, or leave when nothing is left.
            guard !ids.isEmpty else { if !embedded { dismiss() }; return }
            let index = old.firstIndex(of: state.current) ?? 0
            state.current = ids[min(index, ids.count - 1)]
        }
        .onChange(of: state.current) { _, id in onCurrentChange(id) }
        .onDisappear { prefetches.values.forEach { $0.cancel() } }
        .accessibilityIdentifier("timeline.detail")
    }

    /// Longest side of the full-screen page in points, for prefetching at the size the page will decode.
    private var pageSide: CGFloat {
        let size = geometry.frame.size, insets = geometry.insets
        return max(size.width + insets.leading + insets.trailing, size.height + insets.top + insets.bottom)
    }

    /// A vertical fold crossing the page (safe-area coordinates, which is how pages lay out).
    private var foldSplit: BubuLayout.ColumnSplit? {
        let frame = screen.rootRect(fromGlobal: geometry.frame)
        return screen.columnSplit(minX: frame.minX, width: frame.width, margin: 0, minPane: 200)
    }

    private var title: String {
        let item = items.first(where: { $0.id == state.current }) ?? initial
        guard let date = item.capturedDate else { return "布布的时光" }
        return date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
    }

    /// The pages either side get their thumbnail and large image ready, so a swipe lands on a picture.
    private func prefetchNeighbours() {
        guard pageSide > 0, let index = items.firstIndex(where: { $0.id == state.current }) else { return }
        let bucket = LearningImageDecoder.bucket(forPixels: pageSide * displayScale)
        let wanted = [index - 1, index + 1].filter(items.indices.contains).map { items[$0] }
        let wantedIDs = Set(wanted.map(\.id))
        for (id, task) in prefetches where !wantedIDs.contains(id) { task.cancel() }
        prefetches = prefetches.filter { wantedIDs.contains($0.key) }
        for item in wanted where prefetches[item.id] == nil {
            let client = client
            prefetches[item.id] = Task {
                if LearningImagePipeline.anyCached(scope: client.scope, path: item.previewUrl) == nil {
                    await LearningImagePipeline.prefetch(item.previewUrl, client: client, bucket: 512)
                }
                await LearningImagePipeline.prefetch(item.largeUrl, client: client, bucket: bucket)
            }
        }
    }
}

/// Bridges the shared pager state into one page.
private struct OnlineDetailPageHost: View {
    let client: BubuLearningClient
    let item: OnlineTimelineItem
    let state: OnlineDetailPagerState
    let onNotBubu: (String) -> Void

    var body: some View {
        OnlineTimelineDetailPage(
            client: client, item: item, isCurrent: state.current == item.id,
            chromeVisible: state.chromeVisible, split: state.split, extendsUnderBar: state.extendsUnderBar,
            showInfo: Binding(get: { state.infoID == item.id },
                              set: { open in
                                  if open { state.infoID = item.id } else if state.infoID == item.id { state.infoID = nil }
                              }),
            onToggleChrome: { state.chromeVisible.toggle() },
            onNotBubu: onNotBubu)
    }
}

struct OnlineTimelineDetailPage: View {
    let client: BubuLearningClient
    let item: OnlineTimelineItem
    let isCurrent: Bool
    var chromeVisible = true
    /// A vertical fold across the page: the photo goes before it, the analysis and comments after it.
    var split: BubuLayout.ColumnSplit? = nil
    /// Bars stand vertically at the side (iPhone Duo): the photo stays clear of them and extends under them.
    var extendsUnderBar = false
    @Binding var showInfo: Bool
    var onToggleChrome: () -> Void = {}
    var onNotBubu: (String) -> Void = { _ in }
    @State private var player: AVPlayer?
    @State private var videoError: String?
    @State private var confirmNotBubu = false
    @State private var actionError: String?

    var body: some View {
        // One structure with or without a fold, so the photo keeps its zoom and image when the fold appears.
        HStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                media.ignoresSafeArea(edges: split != nil || extendsUnderBar ? .vertical : .all)
                if split == nil && chromeVisible && player == nil {
                    caption.transition(.opacity)
                }
            }
            .frame(width: split?.leading)
            if let split {
                Color.clear.frame(width: split.gutter)
                infoContent
                    .background(BubuThemedBackground().ignoresSafeArea())
                    .frame(width: split.trailing)
            }
        }
        .onChange(of: split != nil) { _, folded in if folded { showInfo = false } }
        .onChange(of: isCurrent) { _, active in if !active { player?.pause() } }
        .onDisappear {
            guard let player else { return }
            player.pause()
            // Let music or podcasts in other apps resume after a video.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        .sheet(isPresented: split == nil ? $showInfo : .constant(false)) { infoSheet }
    }

    @ViewBuilder
    private var media: some View {
        if item.isVideo {
            ZStack {
                if let player {
                    VideoPlayer(player: player)
                        .accessibilityLabel(item.description.isEmpty ? "布布的视频" : "视频：\(item.description)")
                        .accessibilityIdentifier("timeline.video")
                } else {
                    OnlineDetailPhoto(item: item, client: client, isActive: isCurrent, onSingleTap: onToggleChrome,
                                      extendsUnderBars: extendsUnderBar)
                        .accessibilityLabel(item.description.isEmpty ? "视频封面" : "视频封面：\(item.description)")
                    if let videoError {
                        VStack(spacing: BubuTheme.Spacing.s) {
                            Image(systemName: "exclamationmark.triangle").font(BubuTheme.Font.headline)
                            Text(videoError).font(BubuTheme.Font.caption).multilineTextAlignment(.center)
                            Button("重试") { Task { await prepareVideo() } }.buttonStyle(.bordered).tint(.white)
                        }
                        .foregroundStyle(.white)
                        .padding()
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
                        .padding()
                    } else {
                        Button { Task { await prepareVideo(autoplay: true) } } label: {
                            Image(systemName: "play.circle.fill").font(.system(size: 64, design: .rounded))
                                .symbolRenderingMode(.palette).foregroundStyle(.white, BubuTheme.Color.actionFill)
                                .shadow(color: BubuTheme.Color.deepRose.opacity(0.3), radius: 8)
                        }
                        .buttonStyle(BubuPressableStyle(scale: 0.9))
                        .accessibilityLabel("播放视频")
                        .accessibilityIdentifier("timeline.video.play")
                    }
                }
            }
        } else {
            OnlineDetailPhoto(item: item, client: client, isActive: isCurrent, onSingleTap: onToggleChrome,
                              extendsUnderBars: extendsUnderBar)
        }
    }

    /// Date, place and the first lines of the analysis over a soft gradient; tap for the full sheet.
    private var caption: some View {
        Button { showInfo = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: BubuTheme.Spacing.s) {
                    Text(item.capturedDate?.formatted(.dateTime.month().day().weekday().hour().minute().locale(Locale(identifier: "zh_CN"))) ?? "拍摄时间未知")
                        .font(BubuTheme.Font.caption.weight(.semibold))
                    if let place = item.place, !place.isEmpty {
                        Label(place, systemImage: "mappin.and.ellipse").font(BubuTheme.Font.caption).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up").font(BubuTheme.Font.caption.weight(.bold))
                }
                if !item.description.isEmpty {
                    Text(item.description).font(BubuTheme.Font.caption).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, BubuTheme.Spacing.item)
            .padding(.top, 28)
            .padding(.bottom, BubuTheme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看画面解析、标签和家人评论")
        .accessibilityIdentifier("timeline.detail.caption")
    }

    /// Analysis, tags and family comments: in a sheet, or in the pane after a vertical fold.
    private var infoContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
                info
                TimelineSocialSection(client: client, itemID: item.id, active: split == nil ? showInfo : isCurrent)
            }
            .padding(BubuTheme.Spacing.item)
            .bubuContentColumn(900)
        }
        .confirmationDialog("这张里没有布布？", isPresented: $confirmNotBubu, titleVisibility: .visible) {
            Button("不是布布，移出时光", role: .destructive) { Task { await markNotBubu() } }
            Button("取消", role: .cancel) {}
        } message: { Text("只会从布布的时光里移出，第二大脑的原片不受影响。") }
    }

    private var infoSheet: some View {
        NavigationStack {
            infoContent
                .background(BubuThemedBackground().ignoresSafeArea())
                .navigationTitle("解析与评论")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成", systemImage: "checkmark", role: .confirm) { showInfo = false }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .bubuLayoutRoot()
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
            showInfo = false
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
