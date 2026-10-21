import SwiftUI

// MARK: - 布布专属时光（在线）
/// 时光主流程：直接读取第二大脑整理好的「布布」专属照片和视频，按拍摄时间倒序。
/// 不读本机 Entry、不要求先写回 PocketBase；所有原件与缩略图都经家庭身份鉴权取回。
struct OnlineTimelineView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if let client = BubuLearningClient(env: env) {
                OnlineTimelineBrowser(client: client).id(client.scope)
            } else {
                ZStack {
                    BubuThemedBackground().ignoresSafeArea()
                    ContentUnavailableView {
                        Label("连接家庭服务后查看", systemImage: "photo.stack")
                    } description: {
                        Text("布布的专属照片和视频由家里的第二大脑整理。请先在设置里连接家庭服务器和账号。")
                    }
                }
            }
        }
        .navigationTitle("时光")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("timeline.online")
    }
}

nonisolated enum OnlineTimelineKind: String, CaseIterable, Identifiable, Sendable {
    case all, photo, video
    var id: String { rawValue }
    var label: String { switch self { case .all: "全部"; case .photo: "照片"; case .video: "视频" } }
    var symbol: String { switch self { case .all: "square.grid.2x2"; case .photo: "photo"; case .video: "video" } }
}

nonisolated enum OnlineTimelineRange: Hashable, Sendable {
    case all, last7, last30, thisYear, custom(Date, Date)
    var label: String {
        switch self {
        case .all: "全部时间"
        case .last7: "近 7 天"
        case .last30: "近 30 天"
        case .thisYear: "今年"
        case .custom(let start, let end):
            "\(start.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))) – \(end.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))))"
        }
    }
    func bounds(now: Date = .now) -> (String?, String?) {
        let calendar = Calendar(identifier: .gregorian)
        switch self {
        case .all: return (nil, nil)
        case .last7: return (BubuLearningDates.dayString(calendar.date(byAdding: .day, value: -6, to: now)!), nil)
        case .last30: return (BubuLearningDates.dayString(calendar.date(byAdding: .day, value: -29, to: now)!), nil)
        case .thisYear:
            let year = calendar.component(.year, from: now)
            return ("\(year)-01-01", nil)
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
}

private struct OnlineTimelineMonth: Identifiable {
    let id: String
    let title: String
    let items: [OnlineTimelineItem]
}

struct OnlineTimelineBrowser: View {
    let client: BubuLearningClient
    @State private var searchText = ""
    @State private var query = OnlineTimelineQuery()
    @State private var items: [OnlineTimelineItem] = []
    @State private var total = 0
    @State private var counts = (photos: 0, videos: 0)
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var errorText: String?
    @State private var snapshot = ""
    @State private var generation = 0
    @State private var selected: OnlineTimelineItem?
    @State private var customRange = false
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEnd = Date.now
    @Environment(\.horizontalSizeClass) private var sizeClass

    private static let pageSize = 60

    var body: some View {
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BubuTheme.Spacing.item, pinnedViews: []) {
                    header
                    filterBar
                    content
                }
                .padding(.horizontal, BubuTheme.Spacing.item)
                .padding(.bottom, 32)
                .bubuContentColumn(1100)
            }
            .refreshable { await reload() }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜画面描述、文字或视频里的话")
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if text != query.text { query.text = text }
        }
        .task(id: query) { await reload() }
        .navigationDestination(item: $selected) { item in
            OnlineTimelineDetailPager(client: client, items: items, initial: item,
                                      loadMore: { await loadNextPage() }, hasMore: hasMore)
        }
        .sheet(isPresented: $customRange) { customRangeSheet }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center, spacing: BubuTheme.Spacing.m) {
            ZStack {
                Circle().fill(BubuTheme.Color.pinkSurface)
                Image(systemName: "sparkles").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(BubuTheme.Color.deepRose)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("布布专属时光").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                Text(loading && items.isEmpty ? "正在从第二大脑读取…"
                     : "照片 \(counts.photos) · 视频 \(counts.videos) · 第二大脑自动整理")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    .accessibilityIdentifier("timeline.online.counts")
            }
            Spacer(minLength: 0)
        }
        .padding(BubuTheme.Spacing.item)
        .background(BubuTheme.Color.card.opacity(0.92), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .padding(.top, BubuTheme.Spacing.s)
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
                } label: {
                    chipLabel(query.range.label, symbol: "calendar", active: query.range != .all)
                }
                .accessibilityIdentifier("timeline.range")
                chip(query.newestFirst ? "最新在前" : "最早在前", symbol: "arrow.up.arrow.down", active: !query.newestFirst) {
                    query.newestFirst.toggle()
                }
                .accessibilityIdentifier("timeline.order")
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorText, items.isEmpty {
            VStack(spacing: BubuTheme.Spacing.m) {
                Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(BubuTheme.Color.deepRose)
                Text(errorText).font(BubuTheme.Font.body).multilineTextAlignment(.center)
                Button("重新加载") { Task { await reload() } }.buttonStyle(.borderedProminent).tint(BubuTheme.Color.primary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 60)
        } else if items.isEmpty && loading {
            ProgressView("正在读取布布的照片和视频…").frame(maxWidth: .infinity).padding(.vertical, 80)
        } else if items.isEmpty {
            ContentUnavailableView("没有找到符合条件的时光", systemImage: "magnifyingglass",
                                   description: Text("换个关键词、类型或日期范围试试。"))
                .padding(.vertical, 40)
        } else {
            if query != OnlineTimelineQuery() {
                Text("找到 \(total) 份").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    .accessibilityIdentifier("timeline.online.total")
            }
            ForEach(months) { month in
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.s) {
                    Text(month.title).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                        .padding(.top, BubuTheme.Spacing.s)
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(month.items) { item in
                            Button { selected = item } label: { OnlineTimelineCell(item: item, client: client) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("timeline.item")
                                .onAppear { if item.id == items.last?.id { Task { await loadNextPage() } } }
                        }
                    }
                }
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else if let errorText {
                Button("加载失败，点这里重试") { Task { await loadNextPage() } }
                    .font(BubuTheme.Font.caption).frame(maxWidth: .infinity).padding()
                    .accessibilityHint(errorText)
            } else if !hasMore {
                Text("已经到最早的时光啦").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    .frame(maxWidth: .infinity).padding()
            }
        }
    }

    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("开始", selection: $customStart, displayedComponents: .date)
                DatePicker("结束", selection: $customEnd, in: ...Date.now, displayedComponents: .date)
            }
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

    // MARK: Helpers

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: BubuAdaptive.value(sizeClass, compact: 104, regular: 150), maximum: 260), spacing: 6)]
    }

    private var months: [OnlineTimelineMonth] {
        var order: [String] = []
        var grouped: [String: [OnlineTimelineItem]] = [:]
        for item in items {
            let key = String((item.localDay ?? "未知日期").prefix(7))
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(item)
        }
        return order.map { key in
            let parts = key.split(separator: "-")
            let title = parts.count == 2 ? "\(parts[0])年\(Int(parts[1]) ?? 0)月" : "未知日期"
            return OnlineTimelineMonth(id: key, title: title, items: grouped[key] ?? [])
        }
    }

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
        switch tag {
        case "last7": query.range = .last7
        case "last30": query.range = .last30
        case "thisYear": query.range = .thisYear
        case "custom": customRange = true
        default: query.range = .all
        }
    }

    private func chip(_ title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, symbol: symbol, active: active) }.buttonStyle(.plain)
    }

    private func chipLabel(_ title: String, symbol: String, active: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font(BubuTheme.Font.caption)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(active ? Color.white : BubuTheme.Color.warmBrown)
            .background(active ? BubuTheme.Color.primary : BubuTheme.Color.card.opacity(0.92), in: Capsule())
            .overlay(Capsule().stroke(BubuTheme.Color.hairline, lineWidth: active ? 0 : 1))
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

    private func fetch(page next: Int, replacing: Bool) async {
        let request = query
        let started = generation
        loading = true
        defer { if request == query && started == generation { loading = false } }
        let (start, end) = request.range.bounds()
        var parameters = [URLQueryItem(name: "kind", value: request.kind.rawValue),
                          URLQueryItem(name: "order", value: request.newestFirst ? "desc" : "asc"),
                          URLQueryItem(name: "page", value: String(next)),
                          URLQueryItem(name: "limit", value: String(Self.pageSize))]
        if !request.text.isEmpty { parameters.append(URLQueryItem(name: "query", value: request.text)) }
        if let start { parameters.append(URLQueryItem(name: "start", value: start)) }
        if let end { parameters.append(URLQueryItem(name: "end", value: end)) }
        do {
            let result = try await client.get("api/online-timeline", query: parameters, as: OnlineTimelinePage.self)
            // A refresh or new filter started meanwhile: this page belongs to an old list.
            guard request == query, started == generation, !Task.isCancelled else { return }
            // The library changed between pages: start over rather than mixing two snapshots.
            if !replacing && result.snapshotId != snapshot {
                await reload()
                return
            }
            snapshot = result.snapshotId
            if replacing { items = result.items } else {
                let known = Set(items.map(\.id))
                items.append(contentsOf: result.items.filter { !known.contains($0.id) })
            }
            total = result.total
            counts = (result.photos, result.videos)
            page = result.page
            hasMore = result.hasMore
            errorText = nil
        } catch is CancellationError {
        } catch {
            guard request == query, started == generation else { return }
            // Never leave the previous filter's results on screen under a new filter.
            if replacing { items = []; total = 0 }
            errorText = learningErrorText(error, fallback: "暂时读取不到第二大脑的素材，请稍后重试。")
        }
    }
}

private struct OnlineTimelineCell: View {
    let item: OnlineTimelineItem
    let client: BubuLearningClient

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                LearningRemoteImage(path: item.previewUrl, client: client, label: item.description,
                                    contentMode: .fill, diskCache: true)
            }
            .background(BubuTheme.Color.softFill)
            .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if item.isVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .padding(6).background(.black.opacity(0.45), in: Circle()).padding(6)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((item.isVideo ? "视频，" : "照片，") + (item.description.isEmpty ? "布布的时光" : item.description))
    }
}
