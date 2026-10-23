import SwiftUI

// MARK: - 一组在线素材的网格（回忆、事件共用）
/// 按 id 分批（每批 60）拉取，点开进入与时光相同的详情翻页；在详情里标记「不是布布」后立即移出网格。
struct OnlineItemsGridView<Header: View>: View {
    let client: BubuLearningClient
    let ids: [String]
    let title: String
    @ViewBuilder var header: Header
    @State private var items: [OnlineTimelineItem] = []
    @State private var selected: OnlineTimelineItem?
    @State private var failure: LearningErrorKind?
    @State private var failureText = ""
    @State private var loaded = false
    @State private var attempt = 0
    /// Attempt already loaded: coming back from a photo doesn't fetch the whole group again.
    @State private var loadedAttempt: Int?
    /// Marked "not Bubu" here; kept out even if the server still serves a stale copy.
    @State private var removed: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoom
    /// Opened item id → id of the photo now in front, so going back zooms into that photo.
    @State private var zoomFollow: [String: String] = [:]

    init(client: BubuLearningClient, ids: [String], title: String, @ViewBuilder header: () -> Header) {
        self.client = client
        self.ids = ids
        self.title = title
        self.header = header()
    }

    var body: some View {
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
                    header
                    if let failure {
                        BubuStateView(BubuStateKind(failure), message: failureText) { attempt += 1 }
                    } else if !loaded {
                        BubuStateView(.loading, message: "正在从家里的服务器取照片…")
                    } else if items.isEmpty {
                        BubuStateView(.empty, title: "照片都移走了", message: "这组里的照片已经移出布布的时光了。")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            Button { selected = item } label: {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                                    .overlay { LearningRemoteImage(path: item.previewUrl, client: client, label: item.description, contentMode: .fill, diskCache: true) }
                                    .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
                                    .overlay(alignment: .bottomLeading) { if item.isVideo { OnlineVideoBadge() } }
                            }
                            .buttonStyle(BubuPressableStyle())
                            .matchedTransitionSource(id: item.id, in: zoom)
                            .entranceEffect(index: index)
                            .accessibilityLabel((item.isVideo ? "视频，" : "照片，") + (item.description.isEmpty ? "布布的时光" : item.description))
                            .accessibilityIdentifier("items-grid.item")
                        }
                    }
                }
                .padding(BubuTheme.Spacing.item)
                .bubuContentColumn(900)
            }
            .refreshable { await load() }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selected) { item in
            OnlineTimelineDetailPager(client: client, items: items, initial: item, loadMore: {}, hasMore: false,
                                      onNotBubu: { id in remove(id) },
                                      onCurrentChange: { id in zoomFollow = [item.id: id] })
                .navigationTransition(.zoom(sourceID: zoomFollow[item.id] ?? item.id, in: zoom))
        }
        .task(id: attempt) {
            guard loadedAttempt != attempt else { return }
            await load()
        }
    }

    private func remove(_ id: String) {
        removed.insert(id)
        withAnimation(BubuMotion.allowed(BubuMotion.gentle, reduceMotion: reduceMotion)) { items.removeAll { $0.id == id } }
        selected = nil
    }

    private func load() async {
        failure = nil
        do {
            let fetched = try await client.items(ids: ids)
            items = fetched.filter { !removed.contains($0.id) }
            loaded = true
            loadedAttempt = attempt
        } catch where isCancellation(error) {
        } catch {
            failure = LearningErrorKind(error)
            failureText = learningErrorText(error, fallback: "这组照片暂时打不开，请稍后再试。")
            loaded = true
        }
    }
}

/// Play badge on video thumbnails: fixed dark ink so it stays readable in dark mode.
struct OnlineVideoBadge: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(.white)
            .padding(6).background(BubuTheme.Color.paperInk.opacity(0.6), in: Circle()).padding(6)
            .accessibilityHidden(true)
    }
}

// MARK: - 事件（2.26）

/// `GET events`：至少 3 条布布素材的自动事件，按 `day` 倒序。
nonisolated struct OnlineTimelineEvent: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let story: String?
    let day: String
    let place: String?
    let count: Int
    let coverUrl: String?
    let itemIds: [String]
}

nonisolated struct OnlineTimelineEvents: Decodable, Sendable { let items: [OnlineTimelineEvent] }

/// Compact story card in the timeline stream: date and place, title, one line of story and a strip of
/// up to four of its photos. Those photos are left out of the grid around it, so nothing shows twice.
struct OnlineTimelineEventCard: View {
    let event: OnlineTimelineEvent
    /// The event's photos already loaded; empty falls back to the server's cover.
    var thumbs: [OnlineTimelineItem] = []
    let client: BubuLearningClient
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.bubuLayout) private var screen

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(OnlineTimelineEventCard.when(event), systemImage: "book.pages.fill")
                    .font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(BubuTheme.Color.deepRose)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    Text("看全部 \(event.count) 张")
                    Image(systemName: "chevron.right").imageScale(.small)
                }
                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                .fixedSize()
            }
            Text(event.title).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown).lineLimit(1)
            if let story = event.story, !story.isEmpty {
                Text(story).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText).lineLimit(1)
            }
            strip.padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.card.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("小故事，\(event.title)，\(OnlineTimelineEventCard.meta(event))")
        .accessibilityAddTraits(.isButton)
    }

    private var stripHeight: CGFloat { screen.bubuHeight(BubuAdaptive.value(sizeClass, compact: 84, regular: 128), short: 64) }

    @ViewBuilder
    private var strip: some View {
        if thumbs.isEmpty {
            Color.clear.frame(height: stripHeight).frame(maxWidth: .infinity)
                .overlay {
                    if let cover = event.coverUrl {
                        LearningRemoteImage(path: cover, client: client, label: event.title, contentMode: .fill, diskCache: true)
                    } else {
                        BubuTheme.Color.peachSurface
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
        } else {
            HStack(spacing: OnlineTimelineLayoutBuilder.spacing) {
                ForEach(0..<4, id: \.self) { index in
                    Color.clear.frame(height: stripHeight).frame(maxWidth: .infinity)
                        .overlay {
                            if index < thumbs.count {
                                LearningRemoteImage(path: thumbs[index].previewUrl, client: client, label: thumbs[index].description,
                                                    contentMode: .fill, diskCache: true)
                            }
                        }
                        .background(index < thumbs.count ? BubuTheme.Color.softFill : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
                        .overlay(alignment: .bottomLeading) { if index < thumbs.count, thumbs[index].isVideo { OnlineVideoBadge() } }
                }
            }
        }
    }

    /// "10月14日 · 曼海宁"
    static func when(_ event: OnlineTimelineEvent) -> String {
        var parts: [String] = []
        if let date = BubuLearningDates.day(event.day) { parts.append(BubuDateFormat.monthDay(date)) }
        if let place = event.place, !place.isEmpty { parts.append(place) }
        return parts.isEmpty ? "一段小故事" : parts.joined(separator: " · ")
    }

    static func meta(_ event: OnlineTimelineEvent) -> String {
        var parts: [String] = []
        if let date = BubuLearningDates.day(event.day) { parts.append(BubuDateFormat.monthDay(date)) }
        if let place = event.place, !place.isEmpty { parts.append(place) }
        parts.append("\(event.count) 张")
        return parts.joined(separator: " · ")
    }
}

/// Tapping an event: all of its photos as a grid.
struct OnlineTimelineEventView: View {
    let event: OnlineTimelineEvent
    let client: BubuLearningClient

    var body: some View {
        OnlineItemsGridView(client: client, ids: event.itemIds, title: "一段小故事") {
            VStack(alignment: .leading, spacing: 6) {
                Text(OnlineTimelineEventCard.meta(event)).font(BubuTheme.Font.caption.weight(.bold))
                    .foregroundStyle(BubuTheme.Color.deepRose)
                Text(event.title).font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
                if let story = event.story, !story.isEmpty {
                    Text(story).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
        }
    }
}
