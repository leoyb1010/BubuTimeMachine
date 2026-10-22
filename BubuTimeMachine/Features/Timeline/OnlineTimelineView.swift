import SwiftUI
import SwiftData

// MARK: - 布布的时光（合成流）
/// 一条时光，两种来源：第二大脑整理的布布专属照片/视频（在线、鉴权），
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
        .secondBrainConsent(active: BubuLearningClient(env: env) != nil && !Self.skipsConsentForUITest)
        .accessibilityIdentifier("timeline.online")
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
}

nonisolated enum OnlineTimelineSource: String, CaseIterable, Identifiable, Sendable {
    case merged, brain, family
    var id: String { rawValue }
    var label: String { switch self { case .merged: "全部"; case .brain: "第二大脑"; case .family: "家人记录" } }
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
    func bounds(now: Date = .now) -> (String?, String?) {
        let calendar = Calendar(identifier: .gregorian)
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

private struct OnlineTimelineQuery: Hashable {
    var text = ""
    var kind = OnlineTimelineKind.all
    var range = OnlineTimelineRange.all
    var newestFirst = true
    var person: String?
    /// Scrubber jump: show from the end of this month backwards.
    var anchorMonth: String?

    var isDefault: Bool { self == OnlineTimelineQuery() }
}

/// One cell of the merged stream.
private enum TimelineElement: Identifiable {
    case online(OnlineTimelineItem)
    case family(Entry)

    var id: String {
        switch self {
        case .online(let item): "o-" + item.id
        case .family(let entry): "f-" + entry.id.uuidString
        }
    }
    var date: Date {
        switch self {
        case .online(let item): item.capturedDate ?? .distantPast
        case .family(let entry): entry.happenedAt
        }
    }
    var aspect: Double {
        switch self {
        case .online(let item): item.layoutAspect
        case .family(let entry): entry.coverMedia == nil ? 1.25 : 1
        }
    }
    var monthKey: String {
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "Asia/Shanghai")!, from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }
}

private struct TimelineRow: Identifiable {
    let id: String
    let cells: [(element: TimelineElement, width: CGFloat)]
    let height: CGFloat
}

private struct TimelineMonthSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let rows: [TimelineRow]
}

struct OnlineTimelineBrowser: View {
    let client: BubuLearningClient?
    @Environment(AppEnvironment.self) private var env
    @Environment(BubuRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt, order: .reverse)
    private var entries: [Entry]
    @AppStorage("bubu.timeline.source") private var sourceRaw = OnlineTimelineSource.merged.rawValue
    @State private var searchText = ""
    @State private var query = OnlineTimelineQuery()
    @State private var items: [OnlineTimelineItem] = []
    @State private var total = 0
    @State private var counts = (photos: 0, videos: 0)
    @State private var months: [OnlineTimelineMonthCount] = []
    @State private var people: [OnlineTimelinePerson] = []
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var offline = false
    @State private var errorText: String?
    @State private var snapshot = ""
    @State private var generation = 0
    @State private var selected: OnlineTimelineItem?
    @State private var selectedEntry: Entry?
    @State private var customRange = false
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var width: CGFloat = 360
    @State private var scrubbing: String?
    @Namespace private var zoom

    private static let pageSize = 60
    private var source: OnlineTimelineSource {
        client == nil ? .family : OnlineTimelineSource(rawValue: sourceRaw) ?? .merged
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            BubuThemedBackground().ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
                        header.id("timeline.top")
                        if client != nil { sourcePicker }
                        if source != .family { filterBar }
                        if offline { offlineBanner }
                        content
                    }
                    .padding(.horizontal, BubuTheme.Spacing.item)
                    .padding(.trailing, showsScrubber ? 18 : 0)
                    .padding(.bottom, 32)
                    .bubuContentColumn(1100)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                }
                .refreshable { await reload() }
                .onChange(of: query.anchorMonth) { _, _ in proxy.scrollTo("timeline.top", anchor: .top) }
            }
            if showsScrubber { scrubber }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: client == nil ? "找家人记下的话" : "搜画面、文字、视频里的话，如“第一次吃西瓜”")
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if text != query.text { query.text = text; query.anchorMonth = nil }
        }
        .task(id: query) { await reload() }
        .task { await loadPeople() }
        .task(id: router.pendingOnlineID) { await openPendingOnlineItem() }
        .navigationDestination(item: $selected) { item in
            OnlineTimelineDetailPager(client: client!, items: items, initial: item,
                                      loadMore: { await loadNextPage() }, hasMore: hasMore,
                                      onNotBubu: { id in removeItem(id) })
                .navigationTransition(.zoom(sourceID: "o-" + item.id, in: zoom))
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
                        NavigationLink { RecognitionView() } label: { Label("认一认", systemImage: "person.crop.square.badge.camera") }
                        NavigationLink { MonthlyReportView() } label: { Label("每月成长小报", systemImage: "calendar.badge.plus") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityIdentifier("timeline.menu")
            }
        }
        .sheet(isPresented: $customRange) { customRangeSheet }
    }

    // MARK: Header & controls

    private var header: some View {
        HStack(alignment: .center, spacing: BubuTheme.Spacing.m) {
            ZStack {
                Circle().fill(BubuTheme.Color.pinkSurface)
                Image(systemName: "sparkles").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.deepRose)
                    .symbolEffect(.bounce, value: total)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("布布的时光").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                Text(headerSubtitle)
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("timeline.online.counts")
            }
            Spacer(minLength: 0)
        }
        .padding(BubuTheme.Spacing.item)
        .background(BubuTheme.Color.card.opacity(0.92), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .padding(.top, BubuTheme.Spacing.s)
    }

    private var headerSubtitle: String {
        if client == nil { return "家人记录 \(entries.count) 条 · 连接家庭服务后可看第二大脑整理的照片视频" }
        if loading && items.isEmpty { return "正在从第二大脑读取…" }
        return "照片 \(counts.photos) · 视频 \(counts.videos) · 家人记录 \(entries.count)"
    }

    private var sourcePicker: some View {
        HStack(spacing: 4) {
            ForEach(OnlineTimelineSource.allCases) { option in
                let active = source == option
                Button {
                    withAnimation(BubuMotion.quick) { sourceRaw = option.rawValue }
                } label: {
                    Text(option.label).font(BubuTheme.Font.caption.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .foregroundStyle(active ? Color.white : BubuTheme.Color.warmBrown)
                        .background {
                            if active {
                                Capsule().fill(BubuTheme.Color.primary).matchedGeometryEffect(id: "source", in: zoom)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(BubuPressableStyle())
                .accessibilityIdentifier("timeline.source.\(option.rawValue)")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(4)
        .background(BubuTheme.Color.card.opacity(0.92), in: Capsule())
        .bubuSensoryFeedback(.selection, trigger: sourceRaw)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BubuTheme.Spacing.s) {
                ForEach(OnlineTimelineKind.allCases) { kind in
                    chip(kind.label, symbol: kind.symbol, active: query.kind == kind) { query.kind = kind }
                        .accessibilityIdentifier("timeline.kind.\(kind.rawValue)")
                }
                Divider().frame(height: 22)
                Menu {
                    Picker("日期", selection: Binding(get: { rangeTag }, set: { applyRange($0) })) {
                        Text("全部时间").tag("all")
                        Text("近 7 天").tag("last7")
                        Text("近 30 天").tag("last30")
                        Text("今年").tag("thisYear")
                        Text("选择日期范围…").tag("custom")
                    }
                } label: { chipLabel(query.range.label, symbol: "calendar", active: query.range != .all) }
                    .accessibilityIdentifier("timeline.range")
                chip(query.newestFirst ? "最新在前" : "最早在前", symbol: "arrow.up.arrow.down", active: !query.newestFirst) {
                    query.newestFirst.toggle(); query.anchorMonth = nil
                }
                .accessibilityIdentifier("timeline.order")
                if !people.isEmpty {
                    Divider().frame(height: 22)
                    ForEach(people.prefix(6), id: \.name) { person in
                        chip("和\(person.name)", symbol: "person.2.fill", active: query.person == person.name) {
                            query.person = query.person == person.name ? nil : person.name
                        }
                        .accessibilityIdentifier("timeline.person")
                    }
                }
                if query.anchorMonth != nil {
                    chip("回到最新", symbol: "arrow.up.to.line", active: true) { query.anchorMonth = nil }
                }
            }
            .padding(.vertical, 2)
        }
        .bubuSensoryFeedback(.selection, trigger: query)
    }

    private var offlineBanner: some View {
        Label("离线中 · 显示上次加载的内容，家人记录照常可看", systemImage: "wifi.slash")
            .font(BubuTheme.Font.caption)
            .foregroundStyle(BubuTheme.Color.warmBrown)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BubuTheme.Color.butterSurface, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityIdentifier("timeline.offline")
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let sections = self.sections
        if client == nil && entries.isEmpty {
            notConnected
        } else if sections.isEmpty && loading {
            skeleton
        } else if sections.isEmpty, let errorText {
            VStack(spacing: BubuTheme.Spacing.m) {
                BubuEmptyIllustration(assetName: "BubuEmptyTimeline", fallbackExpression: .bye, size: 120)
                Text(errorText).font(BubuTheme.Font.body).multilineTextAlignment(.center)
                Button("重新加载") { Task { await reload() } }.buttonStyle(.borderedProminent).tint(BubuTheme.Color.primary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 50)
        } else if sections.isEmpty {
            VStack(spacing: BubuTheme.Spacing.m) {
                BubuEmptyIllustration(assetName: "BubuEmptyTimeline", size: 120)
                Text(source == .family ? "还没有家人记录，点「记录此刻」留下第一条吧" : "没有找到符合条件的时光，换个说法试试")
                    .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 40)
        } else {
            if !query.text.isEmpty || query.person != nil || query.range != .all || query.kind != .all {
                Text("找到 \(source == .family ? sections.reduce(0) { $0 + $1.rows.reduce(0) { $0 + $1.cells.count } } : total) 份")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    .accessibilityIdentifier("timeline.online.total")
            }
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(section.title).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                        Text(section.subtitle).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, BubuTheme.Spacing.s)
                    .id("month-" + section.id)
                    ForEach(section.rows) { row in
                        HStack(spacing: 4) {
                            ForEach(row.cells, id: \.element.id) { cell in
                                cellView(cell.element)
                                    .frame(width: cell.width, height: row.height)
                            }
                        }
                    }
                }
            }
            footer
        }
    }

    @ViewBuilder
    private func cellView(_ element: TimelineElement) -> some View {
        switch element {
        case .online(let item):
            Button { selected = item } label: { OnlineTimelineCell(item: item, client: client!) }
                .buttonStyle(BubuPressableStyle())
                .matchedTransitionSource(id: element.id, in: zoom)
                .accessibilityIdentifier("timeline.item")
                .onAppear { if item.id == items.last?.id { Task { await loadNextPage() } } }
        case .family(let entry):
            Button { selectedEntry = entry } label: { FamilyRecordCell(entry: entry) }
                .buttonStyle(BubuPressableStyle())
                .matchedTransitionSource(id: element.id, in: zoom)
                .accessibilityIdentifier("timeline.family")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if source != .family && loading {
            ProgressView().frame(maxWidth: .infinity).padding()
        } else if source != .family, let errorText, !items.isEmpty {
            Button("加载失败，点这里重试") { Task { await loadNextPage() } }
                .font(BubuTheme.Font.caption).frame(maxWidth: .infinity).padding()
                .accessibilityHint(errorText)
        } else if source == .family || !hasMore {
            Text("已经到最早的时光啦").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                .frame(maxWidth: .infinity).padding()
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 4) {
            BubuSkeletonBlock(cornerRadius: 10, height: 20).frame(width: 120)
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        BubuSkeletonBlock(cornerRadius: BubuTheme.Radius.xs, height: BubuAdaptive.value(sizeClass, compact: 118, regular: 170))
                    }
                }
            }
        }
        .accessibilityLabel("正在读取")
    }

    private var notConnected: some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            BubuEmptyIllustration(assetName: "BubuEmptyTimeline", size: 140)
            Text("连接家庭服务后，这里会出现第二大脑整理的布布专属照片和视频；家人记下的时光也会合在一起。")
                .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText).multilineTextAlignment(.center)
            NavigationLink { SettingsView() } label: {
                Label("去设置连接", systemImage: "gearshape").font(BubuTheme.Font.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent).tint(BubuTheme.Color.primary)
            .accessibilityIdentifier("timeline.open-settings")
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    // MARK: Scrubber (month jump)

    private var showsScrubber: Bool {
        source != .family && query.text.isEmpty && query.newestFirst && months.count >= 6
    }

    private var scrubber: some View {
        GeometryReader { geometry in
            let height = geometry.size.height - 140
            ZStack(alignment: .topTrailing) {
                Capsule().fill(BubuTheme.Color.card.opacity(0.85)).frame(width: 6, height: height).padding(.trailing, 6)
                if let scrubbing {
                    Text(Self.monthTitle(scrubbing))
                        .font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(BubuTheme.Color.deepRose, in: Capsule())
                        .offset(x: -22, y: offset(for: scrubbing, height: height) - 12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 140, height: height, alignment: .topTrailing)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let month = month(at: value.location.y, height: height)
                    if month != scrubbing { withAnimation(BubuMotion.quick) { scrubbing = month } }
                }
                .onEnded { _ in
                    if let scrubbing { query.anchorMonth = scrubbing == months.first?.month ? nil : scrubbing }
                    withAnimation(BubuMotion.gentle) { scrubbing = nil }
                })
            .padding(.top, 120)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 140)
        .sensoryFeedback(.selection, trigger: scrubbing)
        .accessibilityElement()
        .accessibilityLabel("按月份跳转")
        .accessibilityAdjustableAction { direction in
            let index = months.firstIndex { $0.month == (query.anchorMonth ?? months.first?.month) } ?? 0
            let next = direction == .increment ? min(index + 1, months.count - 1) : max(index - 1, 0)
            query.anchorMonth = next == 0 ? nil : months[next].month
        }
        .accessibilityIdentifier("timeline.scrubber")
    }

    /// Segment length follows how many items a month holds, like Immich's scrubber.
    private func month(at y: CGFloat, height: CGFloat) -> String? {
        let total = max(1, months.reduce(0) { $0 + $1.count })
        var cursor: CGFloat = 0
        for month in months {
            cursor += height * CGFloat(month.count) / CGFloat(total)
            if y <= cursor { return month.month }
        }
        return months.last?.month
    }

    private func offset(for month: String, height: CGFloat) -> CGFloat {
        let total = max(1, months.reduce(0) { $0 + $1.count })
        var cursor: CGFloat = 0
        for item in months {
            if item.month == month { return cursor }
            cursor += height * CGFloat(item.count) / CGFloat(total)
        }
        return cursor
    }

    // MARK: Merging & layout

    private var filteredEntries: [Entry] {
        let text = query.text.lowercased()
        let (start, end) = query.range.bounds()
        return entries.filter { entry in
            if !text.isEmpty {
                let haystack = [entry.title, entry.note, entry.firstPersonNote, entry.locationName].compactMap { $0 }.joined(separator: " ").lowercased()
                if !haystack.contains(text) { return false }
            }
            let day = BubuLearningDates.dayString(entry.happenedAt)
            if let start, day < start { return false }
            if let end, day > end { return false }
            if let anchor = query.anchorMonth, String(day.prefix(7)) > anchor { return false }
            switch query.kind {
            case .all: return true
            case .photo: return entry.media.contains { $0.type == .photo }
            case .video: return entry.media.contains { $0.type == .video }
            }
        }
    }

    private var elements: [TimelineElement] {
        switch source {
        case .brain:
            return items.map(TimelineElement.online)
        case .family:
            return query.newestFirst ? filteredEntries.map(TimelineElement.family) : filteredEntries.reversed().map(TimelineElement.family)
        case .merged:
            guard query.person == nil else { return items.map(TimelineElement.online) }
            // Only merge family records inside the time span already loaded, so paging stays in order.
            let loaded = items.compactMap(\.capturedDate)
            let boundary = hasMore ? (query.newestFirst ? loaded.min() : loaded.max()) : nil
            let family = filteredEntries.filter { entry in
                guard let boundary else { return true }
                return query.newestFirst ? entry.happenedAt >= boundary : entry.happenedAt <= boundary
            }
            let merged = items.map(TimelineElement.online) + family.map(TimelineElement.family)
            return merged.sorted { query.newestFirst ? $0.date > $1.date : $0.date < $1.date }
        }
    }

    private var sections: [TimelineMonthSection] {
        let target: CGFloat = BubuAdaptive.value(sizeClass, compact: 118, regular: 176)
        var order: [String] = []
        var grouped: [String: [TimelineElement]] = [:]
        for element in elements {
            let key = element.monthKey
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(element)
        }
        return order.map { key in
            let group = grouped[key] ?? []
            let photos = group.filter { if case .online(let i) = $0 { return !i.isVideo } else { return false } }.count
            let videos = group.filter { if case .online(let i) = $0 { return i.isVideo } else { return false } }.count
            let family = group.count - photos - videos
            let places = Set(group.compactMap { if case .online(let i) = $0 { return i.place } else { return nil } }).prefix(2)
            var parts: [String] = []
            if photos > 0 { parts.append("照片 \(photos)") }
            if videos > 0 { parts.append("视频 \(videos)") }
            if family > 0 { parts.append("家人记录 \(family)") }
            if !places.isEmpty { parts.append(places.joined(separator: "、")) }
            return TimelineMonthSection(id: key, title: Self.monthTitle(key), subtitle: parts.joined(separator: " · "),
                                        rows: Self.justify(group, width: max(width, 200), target: target, prefix: key))
        }
    }

    /// Justified rows (flickr/justified-layout idea): equal height per row, widths follow the photo's shape.
    private static func justify(_ elements: [TimelineElement], width: CGFloat, target: CGFloat, prefix: String) -> [TimelineRow] {
        let spacing: CGFloat = 4
        var rows: [TimelineRow] = []
        var pending: [TimelineElement] = []
        var aspectSum = 0.0
        func flush(last: Bool) {
            guard !pending.isEmpty else { return }
            let usable = width - spacing * CGFloat(pending.count - 1)
            var height = usable / CGFloat(aspectSum)
            if last { height = min(height, target * 1.15) }
            let cells = pending.map { ($0, CGFloat($0.aspect) * height) }
            rows.append(TimelineRow(id: prefix + "-" + String(rows.count) + "-" + pending[0].id, cells: cells, height: height))
            pending = []; aspectSum = 0
        }
        for element in elements {
            pending.append(element)
            aspectSum += element.aspect
            let height = (width - spacing * CGFloat(pending.count - 1)) / CGFloat(aspectSum)
            if height <= target { flush(last: false) }
        }
        flush(last: true)
        return rows
    }

    static func monthTitle(_ key: String) -> String {
        let parts = key.split(separator: "-")
        return parts.count == 2 ? "\(parts[0])年\(Int(parts[1]) ?? 0)月" : "未知日期"
    }

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
        query.anchorMonth = nil
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
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(active ? Color.white : BubuTheme.Color.warmBrown)
            .background(active ? BubuTheme.Color.primary : BubuTheme.Color.card.opacity(0.92), in: Capsule())
            .overlay(Capsule().stroke(BubuTheme.Color.hairline, lineWidth: active ? 0 : 1))
            .animation(BubuMotion.quick, value: active)
    }

    private func removeItem(_ id: String) {
        withAnimation(BubuMotion.gentle) { items.removeAll { $0.id == id } }
        selected = nil
    }

    // MARK: Data

    private func loadPeople() async {
        guard let client, people.isEmpty else { return }
        people = (try? await client.get("api/online-timeline/people", as: OnlineTimelinePeople.self))?.items ?? []
    }

    private func openPendingOnlineItem() async {
        guard let client, let id = router.pendingOnlineID else { return }
        router.pendingOnlineID = nil
        if let found = items.first(where: { $0.id == id }) { selected = found; return }
        if let item = try? await client.get("api/online-timeline/items", query: [URLQueryItem(name: "ids", value: id)],
                                            as: OnlineTimelineItems.self).items.first {
            if !items.contains(where: { $0.id == item.id }) { items.insert(item, at: 0) }
            selected = item
        }
    }

    private func reload() async {
        generation += 1
        page = 0; hasMore = false; errorText = nil
        await fetch(page: 1, replacing: true)
    }

    private func loadNextPage() async {
        guard hasMore, !loading else { return }
        await fetch(page: page + 1, replacing: false)
    }

    private func parameters(_ request: OnlineTimelineQuery, page next: Int) -> [URLQueryItem] {
        var (start, end) = request.range.bounds()
        if let anchor = request.anchorMonth, let date = BubuLearningDates.day(anchor + "-01"),
           let last = Calendar(identifier: .gregorian).date(byAdding: DateComponents(month: 1, day: -1), to: date) {
            let anchorEnd = BubuLearningDates.dayString(last)
            end = end.map { min($0, anchorEnd) } ?? anchorEnd
        }
        var result = [URLQueryItem(name: "kind", value: request.kind.rawValue),
                      URLQueryItem(name: "order", value: request.newestFirst ? "desc" : "asc"),
                      URLQueryItem(name: "page", value: String(next)),
                      URLQueryItem(name: "limit", value: String(Self.pageSize))]
        if !request.text.isEmpty { result.append(URLQueryItem(name: "query", value: request.text)) }
        if let person = request.person { result.append(URLQueryItem(name: "person", value: person)) }
        if let start { result.append(URLQueryItem(name: "start", value: start)) }
        if let end { result.append(URLQueryItem(name: "end", value: end)) }
        return result
    }

    private func fetch(page next: Int, replacing: Bool) async {
        guard let client else { return }
        let request = query
        let started = generation
        loading = true
        defer { if request == query && started == generation { loading = false } }
        let parameters = parameters(request, page: next)
        let cacheKey = parameters.filter { $0.name != "page" }.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        do {
            let result = try await client.get("api/online-timeline", query: parameters, as: OnlineTimelinePage.self)
            guard request == query, started == generation, !Task.isCancelled else { return }
            if !replacing && result.snapshotId != snapshot {
                await reload()
                return
            }
            apply(result, replacing: replacing)
            withAnimation(BubuMotion.quick) { offline = false }
            if replacing { OnlineTimelineFeedCache.save(result, scope: client.scope, key: cacheKey) }
        } catch is CancellationError {
        } catch {
            guard request == query, started == generation else { return }
            if replacing, let cached = OnlineTimelineFeedCache.load(scope: client.scope, key: cacheKey) {
                apply(cached, replacing: true)
                hasMore = false
                withAnimation(BubuMotion.quick) { offline = true }
                errorText = nil
                return
            }
            if replacing { items = []; total = 0 }
            errorText = learningErrorText(error, fallback: "暂时读取不到第二大脑的素材，请稍后重试。")
        }
    }

    private func apply(_ result: OnlineTimelinePage, replacing: Bool) {
        snapshot = result.snapshotId
        if replacing {
            withAnimation(reduceMotion ? nil : BubuMotion.gentle) { items = result.items }
        } else {
            let known = Set(items.map(\.id))
            items.append(contentsOf: result.items.filter { !known.contains($0.id) })
        }
        total = result.total
        counts = (result.photos, result.videos)
        if let months = result.months, query.anchorMonth == nil { self.months = months }
        page = result.page
        hasMore = result.hasMore
        errorText = nil
    }
}

/// Last first page per query, per account, for offline viewing.
nonisolated enum OnlineTimelineFeedCache {
    static func save(_ page: OnlineTimelinePage, scope: String, key: String) {
        guard let file = LearningMediaCache.file(scope: scope, path: "feed?" + key),
              let data = try? JSONEncoder().encode(page) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load(scope: String, key: String) -> OnlineTimelinePage? {
        guard let file = LearningMediaCache.file(scope: scope, path: "feed?" + key),
              let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(OnlineTimelinePage.self, from: data)
    }
}

private struct OnlineTimelineCell: View {
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
                if item.isVideo {
                    Image(systemName: "play.fill")
                        .font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(6).background(BubuTheme.Color.warmBrown.opacity(0.55), in: Circle()).padding(6)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((item.isVideo ? "视频，" : "照片，") + (item.description.isEmpty ? "布布的时光" : item.description))
            .accessibilityAddTraits(.isButton)
    }
}

/// A family record in the grid: its photo, or a soft quote card for words/voice.
private struct FamilyRecordCell: View {
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
