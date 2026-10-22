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
    @Namespace private var zoom

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
                                      onNotBubu: { id in remove(id) })
                .navigationTransition(.zoom(sourceID: item.id, in: zoom))
        }
        .task(id: attempt) { await load() }
    }

    private func remove(_ id: String) {
        withAnimation(BubuMotion.gentle) { items.removeAll { $0.id == id } }
        selected = nil
    }

    private func load() async {
        failure = nil
        do {
            items = try await client.items(ids: ids)
            loaded = true
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

/// Big card in the timeline stream: cover, title, two lines of story, place and count.
struct OnlineTimelineEventCard: View {
    let event: OnlineTimelineEvent
    let client: BubuLearningClient

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 190)
                .overlay {
                    if let cover = event.coverUrl {
                        LearningRemoteImage(path: cover, client: client, label: event.title, contentMode: .fill, diskCache: true)
                    } else {
                        BubuTheme.Color.peachSurface
                    }
                }
                .clipped()
                .overlay(alignment: .topLeading) {
                    Label("一段小故事", systemImage: "book.pages.fill")
                        .font(BubuTheme.Font.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.88), in: Capsule())
                        .foregroundStyle(BubuTheme.Color.paperInk)
                        .padding(BubuTheme.Spacing.m)
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown).lineLimit(2)
                if let story = event.story, !story.isEmpty {
                    Text(story).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText).lineLimit(2)
                }
                Text(OnlineTimelineEventCard.meta(event))
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.deepRose).lineLimit(1)
            }
            .padding(BubuTheme.Spacing.item)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BubuTheme.Color.card.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .shadow(color: BubuTheme.Color.deepRose.opacity(0.12), radius: 10, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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
