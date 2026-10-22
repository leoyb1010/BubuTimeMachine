import SwiftUI
import SwiftData

// MARK: - 布布的时光（合成流）
/// 一条时光，两种来源：家里的相册（第二大脑）整理的布布专属照片/视频（在线、鉴权），
/// 以及家人用「记录此刻」留下的记录（本机 SwiftData，离线可用）。
/// 未连接家庭服务时只显示家人记录，并给出去设置的入口。
struct OnlineTimelineView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if let client = BubuLearningClient(env: env) {
                OnlineTimelineBrowser(client: client).id(client.scope)
            } else {
                OnlineTimelineBrowser(client: nil)
            }
        }
        .navigationTitle("时光")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension OnlineTimelineView {
    /// UI tests drive the real flows; the consent sheet is covered by its own check.
    static var skipsConsentForUITest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uitest-skip-consent")
        #else
        false
        #endif
    }
}

nonisolated enum OnlineTimelineKind: String, CaseIterable, Identifiable, Sendable {
    case all, photo, video
    var id: String { rawValue }
    var label: String { switch self { case .all: "全部"; case .photo: "照片"; case .video: "视频" } }
    var symbol: String { switch self { case .all: "square.grid.2x2"; case .photo: "photo"; case .video: "video" } }
    var menuLabel: String { switch self { case .all: "不限类型"; case .photo: "只看照片"; case .video: "只看视频" } }
}

nonisolated enum OnlineTimelineSource: String, CaseIterable, Identifiable, Sendable {
    case merged, brain, family
    var id: String { rawValue }
    var label: String { switch self { case .merged: "全部"; case .brain: "照片视频"; case .family: "家人写的" } }
}

nonisolated enum OnlineTimelineRange: Hashable, Sendable {
    case all, last7, last30, thisYear, custom(Date, Date)
    var label: String {
        let zh = Locale(identifier: "zh_CN")
        switch self {
        case .all: return "全部时间"
        case .last7: return "近 7 天"
        case .last30: return "近 30 天"
        case .thisYear: return "今年"
        case .custom(let start, let end):
            return "\(start.formatted(.dateTime.year().month().day().locale(zh))) – \(end.formatted(.dateTime.month().day().locale(zh)))"
        }
    }
    /// Day strings in Asia/Shanghai, matching the server's day keys.
    func bounds(now: Date = .now) -> (String?, String?) {
        let calendar = BubuLearningDates.calendar
        switch self {
        case .all: return (nil, nil)
        case .last7: return (BubuLearningDates.dayString(calendar.date(byAdding: .day, value: -6, to: now)!), nil)
        case .last30: return (BubuLearningDates.dayString(calendar.date(byAdding: .day, value: -29, to: now)!), nil)
        case .thisYear: return ("\(calendar.component(.year, from: now))-01-01", nil)
        case .custom(let start, let end):
            return (BubuLearningDates.dayString(min(start, end)), BubuLearningDates.dayString(max(start, end)))
        }
    }
}

/// Everything the stream layout depends on; changing any of these rebuilds it off the main actor.
private struct OnlineTimelineLayoutKey: Equatable {
    var itemsRevision: Int
    var familyRevision: Int
    var eventsRevision: Int
    var query: OnlineTimelineQuery
    var source: OnlineTimelineSource
    var hasMore: Bool
    var showsEvents: Bool
    var width: CGFloat
    var regular: Bool
}

struct OnlineTimelineBrowser: View {
    let client: BubuLearningClient?
    @Environment(AppEnvironment.self) private var env
    @Environment(BubuRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt, order: .reverse)
    private var entries: [Entry]
    @AppStorage("bubu.timeline.source") private var sourceRaw = OnlineTimelineSource.merged.rawValue
    @State private var searchText = ""
    @State private var query = OnlineTimelineQuery()
    @State private var items: [OnlineTimelineItem] = []
    @State private var itemsRevision = 0
    @State private var total = 0
    @State private var counts = (photos: 0, videos: 0)
    @State private var months: [OnlineTimelineMonthCount] = []
    @State private var people: [OnlineTimelinePerson] = []
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    /// A new query is on its way: the old content dims instead of jumping around.
    @State private var reloading = false
    /// Query whose first page is on screen; coming back to the page with the same query keeps everything.
    @State private var loadedQuery: OnlineTimelineQuery?
    @State private var lastFetch = Date.distantPast
    @State private var offline = false
    /// Shown above cached content when the failure isn't "no network" (e.g. server down).
    @State private var cacheNotice: String?
    @State private var errorText: String?
    @State private var errorKind = LearningErrorKind.other
    @State private var events: [OnlineTimelineEvent] = []
    @State private var eventsRange: OnlineTimelineRange?
    @State private var eventsRevision = 0
    @State private var family: [OnlineTimelineFamilyRef] = []
    @State private var entriesByID: [UUID: Entry] = [:]
    @State private var familyRevision = 0
    @State private var layout = OnlineTimelineLayout()
    @State private var builtKey: OnlineTimelineLayoutKey?
    @State private var layoutTask: Task<Void, Never>?
    @State private var toast: BubuToastState?
    @State private var snapshot = ""
    @State private var generation = 0
    /// Marked "not Bubu" here; kept out of later pages even if the server still has them.
    @State private var removedIDs: Set<String> = []
    /// New photos found when coming back while the reader is deep in the list.
    @State private var freshItems: [OnlineTimelineItem] = []
    @State private var selected: OnlineTimelineItem?
    @State private var selectedEntry: Entry?
    @State private var selectedEvent: OnlineTimelineEvent?
    @State private var customRange = false
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var width: CGFloat = 360
    @State private var position = ScrollPosition(idType: String.self)
    @State private var currentMonth: String?
    @State private var nearTop = true
    @State private var scrolling = false
    @State private var scrubberAwake = false
    /// Month under the finger while dragging the scrubber thumb.
    @State private var scrubbing: String?
    @State private var scrubStart: String?
    @State private var scrubY: CGFloat = 0
    @State private var scrubTick = 0
    /// Month being paged in for a jump.
    @State private var jumping: String?
    @State private var deepLinkDay: String?
    @Namespace private var zoom
    /// Opened item id → element id of the photo now in front, so going back zooms into that photo (audit D3-03).
    @State private var zoomFollow: [String: String] = [:]

    /// Pages fetched to scroll into an older month; farther jumps become a date filter.
    private static let fillCap = 8
    private static let scrubberSpace = "timeline.scrubber.track"

    private var source: OnlineTimelineSource {
        client == nil ? .family : OnlineTimelineSource(rawValue: sourceRaw) ?? .merged
    }

    var body: some View {
        ScrollView {
            // Spacing 0: every photo row is a direct lazy child; rows add their own 4pt gap.
            LazyVStack(alignment: .leading, spacing: 0) {
                controls.id("timeline.top")
                content
            }
            .scrollTargetLayout()
            .padding(.horizontal, BubuTheme.Spacing.item)
            .padding(.bottom, 32)
            .bubuContentColumn(1100)
        }
        .scrollPosition($position)
        .onScrollTargetVisibilityChange(idType: String.self) { ids in track(visible: ids) }
        .onScrollPhaseChange { _, phase in
            if phase.isScrolling != scrolling { scrolling = phase.isScrolling }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            statusBar.animation(BubuMotion.allowed(BubuMotion.gentle, reduceMotion: reduceMotion), value: statusKey)
        }
        // Drawn over the content, never padding it: margins stay 16pt on both sides.
        .overlay(alignment: .trailing) { if showsScrubber { scrubber } }
        .background { BubuThemedBackground().ignoresSafeArea() }
        .refreshable { await reload(useCache: false) }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: client == nil ? "找家人记下的话" : "搜画面、文字、视频里的话，如“荡秋千”")
        .navigationSubtitle(Text(headerSubtitle))
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if text != query.text { query.text = text; query.anchor = nil }
        }
        .task(id: query) { await load() }
        .task { await loadPeople() }
        .task(id: showsEvents ? query.range : nil) { await loadEvents() }
        .task(id: router.pendingOnlineID) { await openPendingOnlineItem() }
        .task(id: router.pendingTimelineDay) {
            // Handed to a task of its own: clearing the router here would cancel a running jump.
            guard let day = router.pendingTimelineDay else { return }
            deepLinkDay = day
            router.pendingTimelineDay = nil
        }
        .task(id: deepLinkDay) {
            guard let day = deepLinkDay else { return }
            await jump(month: String(day.prefix(7)), day: day, resetOrder: true)
            deepLinkDay = nil
        }
        .task(id: scrolling || scrubbing != nil) {
            // The scrubber wakes while scrolling and fades 1.5s after the list rests.
            if scrolling || scrubbing != nil {
                if !scrubberAwake { withAnimation(BubuMotion.allowed(BubuMotion.quick, reduceMotion: reduceMotion)) { scrubberAwake = true } }
                return
            }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(BubuMotion.allowed(BubuMotion.gentle, reduceMotion: reduceMotion)) { scrubberAwake = false }
        }
        .onChange(of: entries, initial: true) { _, entries in
            family = entries.map(OnlineTimelineFamilyRef.init)
            entriesByID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            familyRevision += 1
        }
        .onChange(of: layoutKey, initial: true) { _, _ in scheduleLayout() }
        .navigationDestination(item: $selected) { item in
            OnlineTimelineDetailPager(client: client!, items: items, initial: item,
                                      loadMore: { await loadNextPage() }, hasMore: hasMore,
                                      onNotBubu: { id in removeItem(id) },
                                      onCurrentChange: { id in followPager(opened: item.id, current: id) })
                .navigationTransition(.zoom(sourceID: zoomFollow[item.id] ?? "o-" + item.id, in: zoom))
        }
        .navigationDestination(item: $selectedEvent) { event in
            OnlineTimelineEventView(event: event, client: client!)
                .navigationTransition(.zoom(sourceID: "e-" + event.id, in: zoom))
        }
        .navigationDestination(item: $selectedEntry) { entry in
            TimelineEntryDestination(entryID: entry.id)
                .navigationTransition(.zoom(sourceID: "f-" + entry.id.uuidString, in: zoom))
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    NavigationLink { FamilyFeedView() } label: { Label("家人动态", systemImage: "bubble.left.and.text.bubble.right") }
                    if client != nil {
                        NavigationLink { AskBubuView() } label: { Label("布布问答", systemImage: "questionmark.bubble") }
                        NavigationLink { RecognitionView() } label: { Label("认一认", systemImage: "person.crop.square.badge.camera") }
                        NavigationLink { MonthlyReportView() } label: { Label("成长小报", systemImage: "calendar.badge.plus") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityIdentifier("timeline.menu")
            }
        }
        .sheet(isPresented: $customRange) { customRangeSheet }
        .bubuToast($toast)
    }

    // MARK: Header & controls

    /// Counts live in the navigation subtitle, so the first screen is photos, not a header card.
    private var headerSubtitle: String {
        if client == nil { return "家人记录 \(entries.count) 条 · 未连接家里的服务器" }
        if source == .family { return "家人记录 \(layout.familyCount) 条" }
        if loading && items.isEmpty { return "正在读取…" }
        var parts = ["照片 \(counts.photos)", "视频 \(counts.videos)"]
        if source == .merged && query.person == nil { parts.append("家人记录 \(layout.familyCount)") }
        return parts.joined(separator: " · ")
    }

    /// One row of chips that scrolls away with the content.
    private var controls: some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.s) {
            filterRow
            if offline { offlineBanner }
            if let cacheNotice { noticeBanner(cacheNotice) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Measure the row width inside all paddings so justified rows never overflow.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .padding(.top, BubuTheme.Spacing.xs)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BubuTheme.Spacing.s) {
                filterMenu
                Menu {
                    Picker("日期", selection: Binding(get: { rangeTag }, set: { applyRange($0) })) {
                        Text("全部时间").tag("all")
                        Text("近 7 天").tag("last7")
                        Text("近 30 天").tag("last30")
                        Text("今年").tag("thisYear")
                        Text("选择日期范围…").tag("custom")
                    }
                } label: { chipLabel(query.range == .all ? "日期" : query.range.label, symbol: "calendar", active: query.range != .all) }
                    .accessibilityIdentifier("timeline.range")
                chip(query.newestFirst ? "最新在前" : "最早在前", symbol: "arrow.up.arrow.down", active: !query.newestFirst) {
                    query.newestFirst.toggle(); query.anchor = nil
                }
                .accessibilityIdentifier("timeline.order")
                if source != .family, !people.isEmpty { personMenu }
            }
            .padding(.vertical, 2)
        }
        .bubuSensoryFeedback(.selection, trigger: filterSignature)
    }

    /// Source and type in one menu, in plain words.
    private var filterMenu: some View {
        Menu {
            if client != nil {
                Picker("看哪些", selection: $sourceRaw) {
                    ForEach(OnlineTimelineSource.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                            .accessibilityIdentifier("timeline.source.\(option.rawValue)")
                    }
                }
                .pickerStyle(.inline)
            }
            Picker("类型", selection: $query.kind) {
                ForEach(OnlineTimelineKind.allCases) { kind in
                    Label(kind.menuLabel, systemImage: kind.symbol).tag(kind)
                        .accessibilityIdentifier("timeline.kind.\(kind.rawValue)")
                }
            }
            .pickerStyle(.inline)
        } label: { chipLabel(filterTitle, symbol: "line.3.horizontal.decrease", active: filterActive) }
            .accessibilityIdentifier("timeline.filter")
    }

    private var personMenu: some View {
        Menu {
            Picker("和谁在一起", selection: Binding(get: { query.person ?? "" }, set: { query.person = $0.isEmpty ? nil : $0 })) {
                Text("不限").tag("")
                ForEach(people.prefix(10), id: \.name) { person in Text("和\(person.display)").tag(person.name) }
            }
            .pickerStyle(.inline)
        } label: { chipLabel(personTitle, symbol: "person.2.fill", active: query.person != nil) }
            .accessibilityIdentifier("timeline.person")
    }

    private var filterTitle: String {
        var parts: [String] = []
        if client != nil, source != .merged { parts.append(source.label) }
        if query.kind != .all { parts.append(query.kind.label) }
        return parts.isEmpty ? "筛选" : parts.joined(separator: " · ")
    }

    private var filterActive: Bool { (client != nil && source != .merged) || query.kind != .all }

    private var personTitle: String {
        guard let name = query.person else { return "人物" }
        return "和" + (people.first { $0.name == name }?.display ?? name)
    }

    /// Picks the family makes by hand; typing a search or jumping months doesn't tick.
    private var filterSignature: String {
        "\(sourceRaw)|\(query.kind.rawValue)|\(rangeTag)|\(query.person ?? "")|\(query.newestFirst)"
    }

    private var offlineBanner: some View {
        Label("离线中 · 显示上次加载的内容，家人记录照常可看", systemImage: "wifi.slash")
            .font(BubuTheme.Font.caption)
            .foregroundStyle(BubuTheme.Color.warmBrown)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BubuTheme.Color.butterSurface, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))
            .transition(.opacity)
            .accessibilityIdentifier("timeline.offline")
    }

    private func noticeBanner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.icloud")
            .font(BubuTheme.Font.caption)
            .foregroundStyle(BubuTheme.Color.warmBrown)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BubuTheme.Color.peachSurface, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))
            .transition(.opacity)
            .accessibilityIdentifier("timeline.cache-notice")
    }

    // MARK: Pinned status (jump, anchor, new photos)

    private var statusKey: String { "\(jumping ?? "")|\(query.anchor ?? "")|\(freshItems.count)" }

    @ViewBuilder
    private var statusBar: some View {
        if let jumping {
            statusCapsule {
                ProgressView().controlSize(.small)
                Text("正在翻到 \(Self.monthTitle(jumping))…")
            }
        } else if let anchor = query.anchor {
            statusCapsule {
                Text("正在看 \(OnlineTimelineLayoutBuilder.anchorTitle(anchor)) 及以前").lineLimit(1)
                Button("回到最新") { backToLatest() }
                    .font(BubuTheme.Font.caption.weight(.bold))
                    .foregroundStyle(BubuTheme.Color.primaryInk)
                    .accessibilityIdentifier("timeline.back-to-latest")
            }
        } else if !freshItems.isEmpty {
            Button { showFresh() } label: {
                statusCapsule {
                    Image(systemName: "arrow.up")
                    Text("有 \(freshItems.count) 份新时光")
                }
            }
            .buttonStyle(BubuPressableStyle())
            .accessibilityIdentifier("timeline.fresh")
        }
    }

    private func statusCapsule<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: BubuTheme.Spacing.s) { content() }
            .font(BubuTheme.Font.caption)
            .foregroundStyle(BubuTheme.Color.warmBrown)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(BubuTheme.Color.hairline, lineWidth: 1))
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if client == nil && entries.isEmpty {
            notConnected.padding(.top, BubuTheme.Spacing.m)
        } else if builtKey == nil || (layout.isEmpty && (loading || builtKey != layoutKey)) {
            skeleton
        } else if layout.isEmpty, let errorText {
            BubuStateView(BubuStateKind(errorKind), message: errorText) {
                VStack(spacing: BubuTheme.Spacing.s) {
                    BubuStateRetryButton(title: "重新加载") { Task { await reload(useCache: false) } }
                    if BubuStateKind(errorKind) == .serverDown {
                        NavigationLink { ServerStatusView() } label: {
                            Text("看看家里服务器的状态").font(BubuTheme.Font.caption.weight(.semibold))
                                .foregroundStyle(BubuTheme.Color.deepRose)
                        }
                        .accessibilityIdentifier("timeline.server-status")
                    }
                }
            }
            .padding(.top, BubuTheme.Spacing.m)
        } else if layout.isEmpty {
            emptyState.padding(.top, BubuTheme.Spacing.m)
        } else {
            if query.isFiltered {
                Text("找到 \(source == .family ? layout.elementCount : total) 份")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    .padding(.top, BubuTheme.Spacing.s)
                    .accessibilityIdentifier("timeline.online.total")
            }
            Group {
                ForEach(layout.rows) { row in
                    rowView(row)
                        .onAppear {
                            // Page when the reader actually nears the bottom, not when a month is built.
                            if source != .family, jumping == nil, row.index >= layout.rows.count - 6 { Task { await loadNextPage() } }
                            prefetch(after: row.index)
                        }
                }
            }
            .opacity(reloading ? 0.45 : 1)
            .allowsHitTesting(!reloading)
            .animation(BubuMotion.allowed(BubuMotion.quick, reduceMotion: reduceMotion), value: reloading)
            footer
        }
    }

    /// Says why the list is empty, and offers the way back when a filter or jump caused it.
    private var emptyState: some View {
        let message: String
        if let anchor = query.anchor {
            let title = OnlineTimelineLayoutBuilder.anchorTitle(anchor)
            message = source == .family ? "\(title)及以前还没有家人记录" : "\(title)及以前没有找到时光"
        } else if query.isFiltered {
            message = "没有找到符合条件的时光，换个说法试试"
        } else if source == .family {
            message = "还没有家人记录，点「记录此刻」留下第一条吧"
        } else {
            message = "这里还空空的，家里的相册整理好就会出现"
        }
        return BubuStateView(.empty, message: message) {
            if query.anchor != nil {
                BubuStateRetryButton(title: "回到最新") { backToLatest() }
            } else if query.isFiltered {
                BubuStateRetryButton(title: "清除筛选") { clearFilters() }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: OnlineTimelineDisplayRow) -> some View {
        switch row.content {
        case .header(_, let title, let subtitle):
            HStack(alignment: .firstTextBaseline, spacing: BubuTheme.Spacing.s) {
                Text(title).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                    .layoutPriority(1)
                Text(subtitle).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.top, row.index == 0 ? BubuTheme.Spacing.s : BubuTheme.Spacing.l)
            .padding(.bottom, 4)
        case .cells(let cells):
            HStack(spacing: OnlineTimelineLayoutBuilder.spacing) {
                ForEach(cells.cells, id: \.element.id) { cell in
                    cellView(cell.element)
                        .frame(width: cell.width, height: cells.height)
                }
            }
            .padding(.bottom, OnlineTimelineLayoutBuilder.spacing)
        case .event(let event, let thumbs):
            if let client {
                Button { selectedEvent = event } label: { OnlineTimelineEventCard(event: event, thumbs: thumbs, client: client) }
                    .buttonStyle(BubuPressableStyle())
                    .matchedTransitionSource(id: "e-" + event.id, in: zoom)
                    .padding(.vertical, BubuTheme.Spacing.s)
                    .accessibilityIdentifier("timeline.event")
            }
        }
    }

    @ViewBuilder
    private func cellView(_ element: OnlineTimelineElement) -> some View {
        switch element {
        case .online(let item, _, _):
            Button { selected = item } label: { OnlineTimelineCell(item: item, client: client!) }
                .buttonStyle(BubuPressableStyle())
                .matchedTransitionSource(id: element.id, in: zoom)
                .accessibilityIdentifier("timeline.item")
        case .family(let record):
            if let entry = entriesByID[record.id] {
                Button { selectedEntry = entry } label: { FamilyRecordCell(entry: entry) }
                    .buttonStyle(BubuPressableStyle())
                    .matchedTransitionSource(id: element.id, in: zoom)
                    .accessibilityIdentifier("timeline.family")
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if source != .family && loading && !reloading {
            ProgressView().frame(maxWidth: .infinity).padding()
        } else if source != .family, let errorText, !items.isEmpty {
            Button("加载失败，点这里重试") { Task { await loadNextPage() } }
                .font(BubuTheme.Font.caption).frame(maxWidth: .infinity).padding()
                .accessibilityHint(errorText)
                .accessibilityIdentifier("timeline.retry-page")
        } else if source == .family || !hasMore {
            Text("已经到最早的时光啦").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                .frame(maxWidth: .infinity).padding()
        }
    }

    /// Same row breaks as square photos in the real grid, so nothing reflows when content lands.
    private var skeleton: some View {
        let rows = OnlineTimelineLayoutBuilder.placeholderRows(width: width.rounded(), target: rowTarget, rows: 5)
        return VStack(alignment: .leading, spacing: OnlineTimelineLayoutBuilder.spacing) {
            BubuSkeletonBlock(cornerRadius: 10, height: 20).frame(width: 120)
                .padding(.top, BubuTheme.Spacing.s).padding(.bottom, 4)
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: OnlineTimelineLayoutBuilder.spacing) {
                    ForEach(0..<rows[index].count, id: \.self) { _ in
                        BubuSkeletonBlock(cornerRadius: BubuTheme.Radius.xs, height: rows[index].height)
                            .frame(width: rows[index].height)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在读取")
    }

    private var notConnected: some View {
        BubuStateView(.empty, title: "还没连接家里的服务器",
                      message: "连接家庭服务后，这里会出现家里相册整理好的布布照片和视频；家人记下的时光也会合在一起。") {
            NavigationLink { SettingsView() } label: {
                Label("去设置连接", systemImage: "gearshape")
                    .font(BubuTheme.Font.body.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 11)
                    .background(BubuTheme.Color.actionFill, in: Capsule())
            }
            .buttonStyle(BubuPressableStyle())
            .accessibilityIdentifier("timeline.open-settings")
        }
    }

    // MARK: Scrubber (month jump)

    private var showsScrubber: Bool {
        source != .family && query.text.isEmpty && query.newestFirst && months.count >= 6 && !layout.isEmpty
    }

    /// A thumb that follows the month on screen. Only a drag that starts on the thumb scrubs;
    /// swipes elsewhere on the edge scroll the list, and a tap never jumps.
    private var scrubber: some View {
        GeometryReader { geometry in
            let height = max(geometry.size.height - 2 * BubuTheme.Spacing.m, 120)
            let scale = OnlineTimelineScrubberScale(months: months, height: height)
            let shown = scrubbing ?? currentMonth ?? months.first?.month ?? ""
            let awake = scrubberAwake || scrubbing != nil
            let thumbY = scrubbing != nil ? scrubY : (scale.center(of: shown) ?? 0)
            ZStack(alignment: .topTrailing) {
                Capsule().fill(BubuTheme.Color.hairline)
                    .frame(width: 2, height: height)
                    .padding(.trailing, 8)
                    .opacity(awake ? 1 : 0)
                    .allowsHitTesting(false)
                if awake {
                    ForEach(scale.yearMarks, id: \.year) { mark in
                        Text(mark.year)
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.regularMaterial, in: Capsule())
                            .offset(x: -16, y: mark.offset - 8)
                            .allowsHitTesting(false)
                    }
                    .transition(.opacity)
                }
                scrubberThumb(title: awake ? Self.monthTitle(shown) : nil, height: height, scale: scale)
                    .offset(y: thumbY - 22)
            }
            .frame(width: geometry.size.width, height: height, alignment: .topTrailing)
            .coordinateSpace(.named(Self.scrubberSpace))
            .padding(.vertical, BubuTheme.Spacing.m)
            .animation(scrubbing == nil ? BubuMotion.allowed(BubuMotion.quick, reduceMotion: reduceMotion) : nil, value: currentMonth)
        }
        .frame(width: 150)
        .bubuSensoryFeedback(.selection, trigger: scrubTick)
    }

    private func scrubberThumb(title: String?, height: CGFloat, scale: OnlineTimelineScrubberScale) -> some View {
        HStack(spacing: 4) {
            if let title {
                Text(title).font(BubuTheme.Font.caption.weight(.bold)).fixedSize()
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, title == nil ? 0 : 12)
        .frame(width: title == nil ? 6 : nil, height: title == nil ? 34 : 32)
        .background(BubuTheme.Color.actionFill.opacity(title == nil ? 0.8 : 1), in: Capsule())
        .shadow(color: .black.opacity(title == nil ? 0 : 0.15), radius: 6, y: 2)
        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
        .padding(.trailing, 6)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.scrubberSpace))
            .onChanged { value in scrub(to: value.location.y, height: height, scale: scale) }
            .onEnded { value in endScrub(moved: abs(value.translation.height) > 6) })
        .accessibilityElement()
        .accessibilityLabel("按月份跳转")
        .accessibilityValue(Self.monthTitle(currentMonth ?? months.first?.month ?? ""))
        .accessibilityAdjustableAction { direction in stepMonth(direction == .increment ? 1 : -1) }
        .accessibilityIdentifier("timeline.scrubber")
    }

    /// Warms thumbnails of the next two photo rows while this one comes into view.
    private func prefetch(after index: Int) {
        guard let client else { return }
        let scale = displayScale
        for row in layout.rows.dropFirst(index + 1).prefix(2) {
            guard case .cells(let cells) = row.content else { continue }
            for cell in cells.cells {
                guard let item = cell.element.onlineItem else { continue }
                let side = max(cell.width, cells.height)
                Task { await LearningRemoteImage.prefetch(item.previewUrl, client: client, pointSize: side, displayScale: scale) }
            }
        }
    }

    private func scrub(to y: CGFloat, height: CGFloat, scale: OnlineTimelineScrubberScale) {
        if scrubbing == nil { scrubStart = currentMonth ?? months.first?.month }
        scrubY = min(max(y, 0), height)
        let month = scale.month(at: scrubY)
        guard month != scrubbing else { return }
        if scrubbing != nil { scrubTick += 1 }   // one tick per month crossed, none on touch-down
        scrubbing = month
    }

    private func endScrub(moved: Bool) {
        let target = scrubbing
        scrubbing = nil
        guard moved, let target, target != scrubStart else { return }
        Task { await jump(month: target, day: nil) }
    }

    private func stepMonth(_ step: Int) {
        guard !months.isEmpty else { return }
        let current = currentMonth ?? months.first?.month
        let index = months.firstIndex { $0.month <= (current ?? "") } ?? 0
        let next = min(max(index + step, 0), months.count - 1)
        guard next != index else { return }
        Task { await jump(month: months[next].month, day: nil) }
    }

    /// Keeps the zoom-back source on the photo being viewed and its row on screen, so going back lands there.
    private func followPager(opened: String, current: String) {
        let elementID = "o-" + current
        zoomFollow = [opened: elementID]
        let row = layout.rows.first { row in
            if case .cells(let cells) = row.content { return cells.cells.contains { $0.element.id == elementID } }
            return false
        }
        if let row { position.scrollTo(id: row.id, anchor: .center) }
    }

    private func track(visible ids: [String]) {
        let top = ids.compactMap { id in layout.rowIndex[id].map { (index: $0, id: id) } }.min { $0.index < $1.index }
        let atTop = ids.contains("timeline.top") || (top?.index ?? 0) <= 1
        if atTop != nearTop { nearTop = atTop }
        if let top, let month = layout.monthOfRow[top.id], month != currentMonth { currentMonth = month }
    }

    // MARK: Jumping

    /// Scrubber, VoiceOver and deep links land here. When the month is loaded, or a few pages away,
    /// the list scrolls there and newer months stay reachable above; only a far jump becomes a date filter.
    private func jump(month: String, day: String?, resetOrder: Bool = false) async {
        defer { jumping = nil }
        await waitUntilSettled()
        if resetOrder, !query.newestFirst || !query.text.isEmpty {
            searchText = ""
            query.text = ""
            query.newestFirst = true
            await waitUntilSettled()
        }
        if let anchorEnd = query.anchorEndDay, (day ?? OnlineTimelineQuery.endDay(month)) > anchorEnd {
            query.anchor = nil
            await waitUntilSettled()
        }
        if source != .family, client != nil, !loadedThrough(month) {
            let needed = pagesNeeded(through: month)
            if hasMore, needed <= Self.fillCap {
                jumping = month
                await loadPages(needed)
                var extra = 0
                // Month counts are an estimate; a couple more pages cover the gap.
                while hasMore, !loadedThrough(month), errorText == nil, extra < 3 {
                    await loadPages(1)
                    extra += 1
                }
                jumping = nil
                await waitUntilSettled()
            }
            if !loadedThrough(month) {
                query.anchor = day ?? month
                await waitUntilSettled()
                position.scrollTo(edge: .top)
            }
        }
        guard !Task.isCancelled else { return }
        scroll(month: month, day: day)
    }

    private func scroll(month: String, day: String?) {
        var target = layout.monthRowID(month)
        if let day, let hit = layout.anchor(forDay: day) {
            target = hit.rowID
            if !hit.exact {
                toast = BubuToastState(message: "那天没有记录，给你看最近的一天", systemImage: "calendar")
            }
        }
        guard let target else { return }
        let from = currentMonth.flatMap { layout.rowIndex["m-" + $0] } ?? 0
        if reduceMotion || abs((layout.rowIndex[target] ?? 0) - from) > 60 {
            position.scrollTo(id: target, anchor: .top)
        } else {
            withAnimation(BubuMotion.gentle) { position.scrollTo(id: target, anchor: .top) }
        }
    }

    /// Newest first: everything down to `month` is loaded once the oldest loaded item reaches it.
    private func loadedThrough(_ month: String) -> Bool {
        guard source != .family, hasMore else { return true }
        guard let last = items.last else { return false }
        let oldest = OnlineTimelineElement(last).monthKey
        return !oldest.isEmpty && oldest <= month
    }

    private func pagesNeeded(through month: String) -> Int {
        guard !months.isEmpty, query.anchor == nil else { return .max }
        let upTo = months.filter { $0.month >= month }.reduce(0) { $0 + $1.count }
        return max(1, Int((Double(upTo - items.count) / Double(OnlineTimelineQuery.pageSize)).rounded(.up)))
    }

    /// Waits until the current query's first page and its layout are on screen.
    private func waitUntilSettled() async {
        for _ in 0..<200 {
            let loaded = client == nil || (loadedQuery == query && !loading)
            if loaded && builtKey == layoutKey { return }
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
        }
    }

    private func backToLatest() {
        Task {
            query.anchor = nil
            await waitUntilSettled()
            position.scrollTo(edge: .top)
        }
    }

    private func clearFilters() {
        searchText = ""
        query = OnlineTimelineQuery(newestFirst: query.newestFirst)
    }

    private func showFresh() {
        prepend(freshItems)
        if reduceMotion { position.scrollTo(edge: .top) } else { withAnimation(BubuMotion.gentle) { position.scrollTo(edge: .top) } }
    }

    private func prepend(_ fresh: [OnlineTimelineItem]) {
        let known = Set(items.map(\.id))
        items.insert(contentsOf: fresh.filter { !known.contains($0.id) }, at: 0)
        itemsRevision += 1
        freshItems = []
    }

    // MARK: Layout

    /// Event cards only belong in the plain browsing stream, never under a search or filter.
    private var showsEvents: Bool {
        client != nil && source != .family && query.text.isEmpty && query.person == nil && query.kind == .all
    }

    private var rowTarget: CGFloat { sizeClass == .regular ? 176 : 118 }

    private var layoutKey: OnlineTimelineLayoutKey {
        OnlineTimelineLayoutKey(itemsRevision: itemsRevision, familyRevision: familyRevision, eventsRevision: eventsRevision,
                                query: query, source: source, hasMore: hasMore, showsEvents: showsEvents,
                                width: width.rounded(), regular: sizeClass == .regular)
    }

    /// Builds on a background thread from value snapshots; a newer build cancels an older one.
    private func scheduleLayout() {
        let key = layoutKey
        let items = items, family = family, events = showsEvents ? events : []
        let query = query, source = source, hasMore = hasMore, width = key.width, target = rowTarget
        layoutTask?.cancel()
        layoutTask = Task {
            let built = await Task.detached(priority: .userInitiated) {
                OnlineTimelineLayoutBuilder.build(items: items, family: family, events: events, query: query,
                                                  source: source, hasMore: hasMore, width: width, target: target)
            }.value
            guard !Task.isCancelled else { return }
            layout = built
            builtKey = key
        }
    }

    static func monthTitle(_ key: String) -> String { OnlineTimelineLayoutBuilder.monthTitle(key) }

    // MARK: Helpers

    private var rangeTag: String {
        switch query.range {
        case .all: "all"
        case .last7: "last7"
        case .last30: "last30"
        case .thisYear: "thisYear"
        case .custom: "custom"
        }
    }

    private func applyRange(_ tag: String) {
        query.anchor = nil
        switch tag {
        case "last7": query.range = .last7
        case "last30": query.range = .last30
        case "thisYear": query.range = .thisYear
        case "custom": customRange = true
        default: query.range = .all
        }
    }

    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("开始", selection: $customStart, displayedComponents: .date)
                DatePicker("结束", selection: $customEnd, in: ...Date.now, displayedComponents: .date)
            }
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .environment(\.timeZone, BubuLearningDates.timeZone)
            .navigationTitle("选择日期范围")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { customRange = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { query.range = .custom(customStart, customEnd); customRange = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func chip(_ title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, symbol: symbol, active: active) }.buttonStyle(BubuPressableStyle())
    }

    private func chipLabel(_ title: String, symbol: String, active: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font(BubuTheme.Font.caption)
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(active ? Color.white : BubuTheme.Color.warmBrown)
            .background(active ? BubuTheme.Color.actionFill : BubuTheme.Color.card.opacity(0.92), in: Capsule())
            .overlay(Capsule().stroke(BubuTheme.Color.hairline, lineWidth: active ? 0 : 1))
            .animation(BubuMotion.allowed(BubuMotion.quick, reduceMotion: reduceMotion), value: active)
    }

    private func removeItem(_ id: String) {
        selected = nil
        removedIDs.insert(id)
        guard let removed = items.first(where: { $0.id == id }) else { return }
        withAnimation(BubuMotion.allowed(BubuMotion.gentle, reduceMotion: reduceMotion)) { items.removeAll { $0.id == id } }
        itemsRevision += 1
        total = max(0, total - 1)
        if removed.isVideo { counts.videos = max(0, counts.videos - 1) } else { counts.photos = max(0, counts.photos - 1) }
        let month = OnlineTimelineElement(removed).monthKey
        if let index = months.firstIndex(where: { $0.month == month }) {
            months[index] = OnlineTimelineMonthCount(month: months[index].month, count: max(0, months[index].count - 1))
        }
        // Keep the offline copy honest too: the current view and the default view are the ones reopened.
        if let client {
            let keys = Set([cacheKey(query), cacheKey(OnlineTimelineQuery())]), scope = client.scope, isVideo = removed.isVideo
            Task.detached(priority: .utility) {
                for key in keys { OnlineTimelineFeedCache.remove(id, isVideo: isVideo, scope: scope, key: key) }
            }
        }
    }

    // MARK: Data

    private func loadPeople() async {
        guard let client, people.isEmpty else { return }
        people = (try? await client.get("api/online-timeline/people", as: OnlineTimelinePeople.self))?.items ?? []
    }

    /// Widget / Watch picks deep link. The id is cleared only after the request finishes:
    /// clearing it first changed the task id and cancelled this very request on cold start.
    private func openPendingOnlineItem() async {
        guard let client, let id = router.pendingOnlineID else { return }
        if let found = items.first(where: { $0.id == id }) {
            router.pendingOnlineID = nil
            selected = found
            return
        }
        do {
            let item = try await client.items(ids: [id]).first
            guard router.pendingOnlineID == id else { return }   // a newer link took over
            router.pendingOnlineID = nil
            guard let item else {
                toast = BubuToastState(message: "这张已经不在布布的时光里了", systemImage: "photo.badge.exclamationmark")
                return
            }
            if !items.contains(where: { $0.id == item.id }) { items.insert(item, at: 0); itemsRevision += 1 }
            selected = item
        } catch where isCancellation(error) {
            // Left pending: the task runs again when the view comes back.
        } catch {
            guard router.pendingOnlineID == id else { return }
            router.pendingOnlineID = nil
            toast = BubuToastState(message: learningErrorText(error, fallback: "这张照片暂时打不开，请稍后再试。"),
                                   systemImage: "exclamationmark.icloud", duration: 3.5)
        }
    }

    /// Loaded once per date range; coming back to the page doesn't fetch them again.
    private func loadEvents() async {
        guard let client, showsEvents, eventsRange != query.range else { return }
        let range = query.range
        let (start, end) = range.bounds()
        var parameters: [URLQueryItem] = []
        if let start { parameters.append(URLQueryItem(name: "start", value: start)) }
        if let end { parameters.append(URLQueryItem(name: "end", value: end)) }
        do {
            events = try await client.get("api/events", query: parameters, as: OnlineTimelineEvents.self).items
            eventsRange = range
            eventsRevision += 1
        } catch where isCancellation(error) {
        } catch {
            // Older servers (404) or offline: the stream simply has no story cards.
            if !events.isEmpty { events = []; eventsRevision += 1 }
        }
    }

    /// Same query as what's on screen (back from a photo, tab switch): keep every loaded page and the
    /// scroll position, and only check quietly for new photos. A new query replaces the list.
    private func load() async {
        if loadedQuery == query, client == nil || !items.isEmpty {
            await revalidate()
        } else {
            await reload(useCache: true)
        }
    }

    /// First page for the current query. The last cached copy shows at once while the network catches up.
    private func reload(useCache: Bool) async {
        generation += 1
        let started = generation
        let request = query
        let wasLoaded = loadedQuery == request && !items.isEmpty
        errorText = nil
        freshItems = []
        guard let client else { loadedQuery = request; return }
        let key = cacheKey(request)
        var cachedAt: Date?
        if useCache, !wasLoaded, let cached = await cachedPage(key) {
            guard request == query, started == generation, !Task.isCancelled else { return }
            apply(cached.page, replacing: true)
            hasMore = false   // a cached page can't be paged; the live one replaces it
            cachedAt = cached.date ?? .distantPast
        }
        if cachedAt == nil, !wasLoaded, !items.isEmpty { reloading = true }
        loading = true
        defer { if started == generation { loading = false; reloading = false } }
        do {
            let parameters = parameters(request, page: 1)
            let result = try await onlineTimelineTimeout(seconds: 10) {
                try await client.get("api/online-timeline", query: parameters, as: OnlineTimelinePage.self)
            }
            guard request == query, started == generation, !Task.isCancelled else { return }
            apply(result, replacing: true)
            loadedQuery = request
            lastFetch = .now
            withAnimation(BubuMotion.allowed(BubuMotion.quick, reduceMotion: reduceMotion)) { offline = false; cacheNotice = nil }
            if request.text.isEmpty {   // searches aren't kept on disk
                let scope = client.scope
                Task.detached(priority: .utility) { OnlineTimelineFeedCache.save(result, scope: scope, key: key) }
            }
            if request.anchor != nil, months.isEmpty { await loadMonths() }
        } catch where isCancellation(error) {
        } catch {
            guard request == query, started == generation else { return }
            loadedQuery = request
            let kind = LearningErrorKind(error)
            let text = learningErrorText(error, fallback: "暂时读取不到家里的相册，请稍后重试。")
            if cachedAt == nil, !wasLoaded, let cached = await cachedPage(key) {
                guard request == query, started == generation else { return }
                apply(cached.page, replacing: true)
                hasMore = false
                cachedAt = cached.date ?? .distantPast
            }
            if cachedAt != nil || wasLoaded {
                // "离线中" only when the phone really has no network; otherwise say what happened.
                let when = cachedAt.flatMap { $0 == .distantPast ? nil : $0 }
                    .map { "上次（\($0.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "zh_CN"))))）" } ?? "上次"
                withAnimation(BubuMotion.allowed(BubuMotion.quick, reduceMotion: reduceMotion)) {
                    offline = kind == .offline
                    cacheNotice = kind == .offline ? nil : "先显示\(when)加载的内容。" + text
                }
                errorText = nil
                return
            }
            items = []; itemsRevision += 1; total = 0; hasMore = false
            errorKind = kind
            errorText = text
        }
    }

    /// Quiet check when the page comes back (at most once a minute). New photos at the top slide in
    /// when the reader is at the top, otherwise wait behind a "有新时光" capsule.
    private func revalidate() async {
        guard let client, Date.now.timeIntervalSince(lastFetch) > 60, !loading else { return }
        let request = query, started = generation
        let parameters = parameters(request, page: 1)
        guard let result = try? await client.get("api/online-timeline", query: parameters, as: OnlineTimelinePage.self),
              request == query, started == generation, !Task.isCancelled else { return }
        lastFetch = .now
        total = result.total
        counts = (result.photos, result.videos)
        if let months = result.months, request.anchor == nil { self.months = months }
        guard result.snapshotId != snapshot else { return }
        snapshot = result.snapshotId
        guard request.newestFirst, request.anchor == nil, request.text.isEmpty else { return }
        let known = Set(items.map(\.id)).union(removedIDs)
        let newest = items.first.map { OnlineTimelineElement($0).date } ?? .distantPast
        let fresh = result.items.filter { !known.contains($0.id) && OnlineTimelineElement($0).date >= newest }
        guard !fresh.isEmpty else { return }
        if nearTop { prepend(fresh) } else { freshItems = fresh }
    }

    private func loadNextPage() async { await loadPages(1) }

    /// Appends `count` pages fetched together. If the list changed on the server meanwhile (a photo
    /// marked "not Bubu", new uploads), the page before is read again so nothing slips between pages —
    /// loaded pages and the scroll position are never thrown away.
    private func loadPages(_ count: Int) async {
        guard let client, hasMore, !loading, count > 0 else { return }
        let request = query, started = generation, first = page + 1
        loading = true
        defer { if request == query && started == generation { loading = false } }
        do {
            var pages = try await Self.fetchPages(client, (first..<first + count).map { parameters(request, page: $0) })
            guard request == query, started == generation, !Task.isCancelled else { return }
            if first > 1, pages.contains(where: { $0.snapshotId != snapshot }) {
                pages = try await Self.fetchPages(client, [parameters(request, page: first - 1)]) + pages
                guard request == query, started == generation, !Task.isCancelled else { return }
            }
            for result in pages {
                apply(result, replacing: false)
                if !result.hasMore { break }
            }
        } catch where isCancellation(error) {
        } catch {
            guard request == query, started == generation else { return }
            errorKind = LearningErrorKind(error)
            errorText = learningErrorText(error, fallback: "暂时读取不到家里的相册，请稍后重试。")
        }
    }

    nonisolated private static func fetchPages(_ client: BubuLearningClient,
                                               _ requests: [[URLQueryItem]]) async throws -> [OnlineTimelinePage] {
        try await withThrowingTaskGroup(of: (Int, OnlineTimelinePage).self) { group in
            for (index, parameters) in requests.enumerated() {
                group.addTask { (index, try await client.get("api/online-timeline", query: parameters, as: OnlineTimelinePage.self)) }
            }
            var pages: [(Int, OnlineTimelinePage)] = []
            for try await page in group { pages.append(page) }
            return pages.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Month counts for the scrubber come from the unanchored list, so a deep link still gets a scrubber.
    private func loadMonths() async {
        guard let client else { return }
        var request = query
        request.anchor = nil
        let parameters = parameters(request, page: 1, limit: 1)
        if let months = try? await client.get("api/online-timeline", query: parameters, as: OnlineTimelinePage.self).months {
            self.months = months
        }
    }

    private func cachedPage(_ key: String) async -> (page: OnlineTimelinePage, date: Date?)? {
        guard let client else { return nil }
        let scope = client.scope
        return await Task.detached(priority: .userInitiated) { OnlineTimelineFeedCache.load(scope: scope, key: key) }.value
    }

    private func parameters(_ request: OnlineTimelineQuery, page next: Int, limit: Int = OnlineTimelineQuery.pageSize) -> [URLQueryItem] {
        request.parameters(page: next, limit: limit)
    }

    private func cacheKey(_ request: OnlineTimelineQuery) -> String { request.cacheKey }

    private func apply(_ result: OnlineTimelinePage, replacing: Bool) {
        snapshot = result.snapshotId
        let incoming = removedIDs.isEmpty ? result.items : result.items.filter { !removedIDs.contains($0.id) }
        if replacing {
            items = incoming
        } else {
            let known = Set(items.map(\.id))
            items.append(contentsOf: incoming.filter { !known.contains($0.id) })
        }
        itemsRevision += 1
        total = result.total
        counts = (result.photos, result.videos)
        if let months = result.months, query.anchor == nil { self.months = months }
        page = result.page
        hasMore = result.hasMore
        errorText = nil
    }
}

/// First page gets 10s before the cached copy (or an error) takes over; the client's own limit is 30s.
nonisolated func onlineTimelineTimeout<T: Sendable>(seconds: Double,
                                                     _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw URLError(.timedOut)
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw URLError(.timedOut) }
        return first
    }
}


/// Last first page per query, per account, for offline viewing.
nonisolated enum OnlineTimelineFeedCache {
    static func save(_ page: OnlineTimelinePage, scope: String, key: String) {
        guard let file = LearningMediaCache.file(scope: scope, path: "feed?" + key),
              let data = try? JSONEncoder().encode(page) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// The cached page and when it was written.
    static func load(scope: String, key: String) -> (page: OnlineTimelinePage, date: Date?)? {
        guard let file = LearningMediaCache.file(scope: scope, path: "feed?" + key),
              let data = try? Data(contentsOf: file),
              let page = try? JSONDecoder().decode(OnlineTimelinePage.self, from: data) else { return nil }
        return (page, try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    }

    /// Drops one item (marked "not Bubu") from a cached page so offline viewing doesn't bring it back.
    static func remove(_ id: String, isVideo: Bool, scope: String, key: String) {
        guard let page = load(scope: scope, key: key)?.page, page.items.contains(where: { $0.id == id }) else { return }
        let updated = OnlineTimelinePage(items: page.items.filter { $0.id != id }, total: max(0, page.total - 1),
                                         page: page.page, hasMore: page.hasMore,
                                         photos: max(0, page.photos - (isVideo ? 0 : 1)),
                                         videos: max(0, page.videos - (isVideo ? 1 : 0)),
                                         snapshotId: page.snapshotId, months: page.months)
        save(updated, scope: scope, key: key)
    }
}

nonisolated extension OnlineTimelineQuery {
    static let pageSize = 60

    /// Request parameters for one page of the stream; shared by 时光 and the home page's 最近时光.
    func parameters(page next: Int, limit: Int = OnlineTimelineQuery.pageSize) -> [URLQueryItem] {
        var (start, end) = range.bounds()
        if let anchorEnd = anchorEndDay { end = end.map { min($0, anchorEnd) } ?? anchorEnd }
        var result = [URLQueryItem(name: "kind", value: kind.rawValue),
                      URLQueryItem(name: "order", value: newestFirst ? "desc" : "asc"),
                      URLQueryItem(name: "page", value: String(next)),
                      URLQueryItem(name: "limit", value: String(limit))]
        if !text.isEmpty { result.append(URLQueryItem(name: "query", value: text)) }
        if let person { result.append(URLQueryItem(name: "person", value: person)) }
        if let start { result.append(URLQueryItem(name: "start", value: start)) }
        if let end { result.append(URLQueryItem(name: "end", value: end)) }
        return result
    }

    /// Offline-cache key: the first page's parameters for this query.
    var cacheKey: String {
        parameters(page: 1).filter { $0.name != "page" }.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    }
}

struct OnlineTimelineCell: View {
    let item: OnlineTimelineItem
    let client: BubuLearningClient

    var body: some View {
        Color.clear
            .overlay {
                LearningRemoteImage(path: item.previewUrl, client: client, label: item.description,
                                    contentMode: .fill, diskCache: true)
            }
            .background(BubuTheme.Color.softFill)
            .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if item.isVideo { OnlineVideoBadge() }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((item.isVideo ? "视频，" : "照片，") + (item.description.isEmpty ? "布布的时光" : item.description))
            .accessibilityAddTraits(.isButton)
    }
}

/// A family record in the grid: its photo, or a soft quote card for words/voice.
struct FamilyRecordCell: View {
    let entry: Entry
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if let cover = entry.coverMedia {
                MediaThumbnail(media: cover, mediaStore: env.mediaStore, cornerRadius: BubuTheme.Radius.xs, size: .grid)
                    .overlay(alignment: .topLeading) { badge }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: entry.voiceNotes.isEmpty ? "quote.opening" : "waveform")
                        Text(entry.authorRole)
                    }
                    .font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(BubuTheme.Color.deepRose)
                    Text(entry.firstPersonNote ?? entry.note ?? entry.title ?? "一段声音")
                        .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
                        .lineLimit(4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(10)
                .background(BubuTheme.Color.peachSurface, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("家人记录，\(entry.authorRole)：\(entry.note ?? entry.title ?? "")")
        .accessibilityAddTraits(.isButton)
    }

    private var badge: some View {
        Image(systemName: "heart.fill")
            .font(BubuTheme.Font.caption).foregroundStyle(.white)
            .padding(5).background(BubuTheme.Color.primary.opacity(0.85), in: Circle()).padding(5)
            .accessibilityHidden(true)
    }
}
