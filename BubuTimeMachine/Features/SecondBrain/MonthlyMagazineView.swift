import SwiftUI

// MARK: - 布布成长月刊（每月成长小报的可翻阅形态）
/// The monthly reports read as a magazine shelf: one cover per issue (oldest = 第 1 期), grouped by
/// year, newest first. Opening a cover lands in a page-turn reader that swipes between issues.

nonisolated enum MonthlyMagazine {
    /// Issues oldest → newest, de-duplicated by month.
    static func issues(_ reports: [MonthlyReportDTO]) -> [MonthlyReportDTO] {
        var seen: Set<String> = []
        return reports.sorted { $0.month < $1.month }.filter { seen.insert(String($0.month.prefix(7))).inserted }
    }

    struct Shelf: Sendable, Hashable {
        let year: String
        let issues: [MonthlyReportDTO]
    }

    /// Years newest first, each with its issues newest first.
    static func shelves(_ issues: [MonthlyReportDTO]) -> [Shelf] {
        let grouped = Dictionary(grouping: issues) { String($0.month.prefix(4)) }
        return grouped.keys.sorted(by: >).map { year in
            Shelf(year: year, issues: (grouped[year] ?? []).sorted { $0.month > $1.month })
        }
    }

    /// A soft macaron hue per calendar month, used when a cover has no photo yet.
    static func hue(_ month: String) -> Double {
        let value = Int(month.split(separator: "-").dropFirst().first ?? "") ?? 1
        return Double((value * 29) % 360)
    }

    /// "深圳市 · 尚云花园" / "深圳市·尚云花园" → "尚云花园"; at most `limit`, no repeats.
    static func shortPlaces(_ places: [String], limit: Int = 4) -> [String] {
        var result: [String] = []
        for place in places {
            let short = place.split(separator: "·").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? place
            if !short.isEmpty, !result.contains(short) { result.append(short) }
            if result.count == limit { break }
        }
        return result
    }
}

private nonisolated struct MonthlyIssueRoute: Hashable, Identifiable, Sendable {
    let month: String
    var id: String { month }
}

struct MonthlyMagazineShelf: View {
    let reports: [MonthlyReportDTO]
    let client: BubuLearningClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var covers: [String: OnlineTimelineItem] = [:]
    @State private var opened: MonthlyIssueRoute?

    private var issues: [MonthlyReportDTO] { MonthlyMagazine.issues(reports) }

    var body: some View {
        let issues = self.issues
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.l) {
            masthead(issues)
            if let latest = issues.last {
                Button { open(latest) } label: {
                    MonthlyIssueCover(report: latest, number: issues.count, cover: covers[latest.highlightIds.first ?? ""],
                                      client: client, featured: true)
                }
                .buttonStyle(BubuPressableStyle())
                .accessibilityHint("翻开最新一期")
                .accessibilityIdentifier("monthly.latest")
            }
            ForEach(MonthlyMagazine.shelves(issues), id: \.year) { shelf in
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
                    Text("\(shelf.year) 年").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: BubuTheme.Spacing.m)],
                              spacing: BubuTheme.Spacing.m) {
                        ForEach(Array(shelf.issues.enumerated()), id: \.element.id) { index, report in
                            let number = (issues.firstIndex(of: report) ?? 0) + 1
                            Button { open(report) } label: {
                                MonthlyIssueCover(report: report, number: number, cover: covers[report.highlightIds.first ?? ""],
                                                  client: client, featured: false)
                            }
                            .buttonStyle(BubuPressableStyle())
                            .entranceEffect(index: index)
                            .accessibilityIdentifier("monthly.cover")
                        }
                    }
                }
            }
        }
        .navigationDestination(item: $opened) { route in
            MonthlyIssueReader(issues: issues, initialMonth: route.month, client: client)
        }
        .task(id: issues.map(\.month)) {
            let ids = issues.compactMap(\.highlightIds.first).filter { covers[$0] == nil }
            guard !ids.isEmpty, let items = try? await client.timelineItems(ids: ids) else { return }
            withAnimation(reduceMotion ? nil : BubuMotion.smooth) {
                for item in items { covers[item.id] = item }
            }
        }
    }

    private func masthead(_ issues: [MonthlyReportDTO]) -> some View {
        HStack(spacing: BubuTheme.Spacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BUBU MONTHLY").font(BubuTheme.Font.scaled(11, weight: .heavy)).tracking(2)
                    .foregroundStyle(BubuTheme.Color.deepRose)
                Text("布布成长月刊").font(BubuTheme.Font.hugeTitle).foregroundStyle(BubuTheme.Color.warmBrown)
                if let first = issues.first?.month, let last = issues.last?.month {
                    Text("共 \(issues.count) 期 · \(SecondBrainMonths.caption(first)) – \(SecondBrainMonths.caption(last))")
                        .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            Spacer(minLength: 0)
            BubuMascotBadge(size: 72, expression: .cheer)
        }
        .accessibilityElement(children: .combine)
    }

    private func open(_ report: MonthlyReportDTO) {
        BubuHaptics.selection()
        opened = MonthlyIssueRoute(month: report.month)
    }
}

/// One magazine cover: photo (or a macaron wash), issue number, month and the story title.
private struct MonthlyIssueCover: View {
    let report: MonthlyReportDTO
    let number: Int
    let cover: OnlineTimelineItem?
    let client: BubuLearningClient
    let featured: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BubuTheme.Color.hueSurface(MonthlyMagazine.hue(report.month))
            if let cover {
                LearningRemoteImage(path: featured ? cover.largeUrl : cover.previewUrl, client: client,
                                    label: cover.description, contentMode: .fill, diskCache: true)
                    .transition(.opacity)
            } else {
                Image(systemName: "book.pages.fill").font(.system(size: featured ? 64 : 40, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(SecondBrainMonths.caption(report.month))
                    .font(BubuTheme.Font.scaled(featured ? 14 : 12, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                Text(report.title.isEmpty ? "这个月的小报" : report.title)
                    .font(featured ? BubuTheme.Font.title : BubuTheme.Font.scaled(15, weight: .heavy))
                    .foregroundStyle(.white).lineLimit(featured ? 3 : 2).multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            }
            .padding(featured ? BubuTheme.Spacing.l : BubuTheme.Spacing.m)
        }
        .overlay(alignment: .topLeading) {
            Text(featured ? "最新 · 第 \(number) 期" : "No.\(number)")
                .font(BubuTheme.Font.scaled(11, weight: .heavy)).foregroundStyle(BubuTheme.Color.deepRose)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(BubuTheme.Color.card.opacity(0.92), in: Capsule())
                .padding(featured ? BubuTheme.Spacing.m : BubuTheme.Spacing.s)
        }
        .aspectRatio(featured ? 4.0 / 3.0 : 3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: featured ? BubuTheme.Radius.card : BubuTheme.Radius.md, style: .continuous))
        .shadow(color: BubuTheme.Color.deepRose.opacity(0.14), radius: 10, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(number) 期，\(SecondBrainMonths.caption(report.month))，\(report.title)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Page-turn reader: swipe (or use the bottom buttons) to move between issues.
private struct MonthlyIssueReader: View {
    let issues: [MonthlyReportDTO]
    let initialMonth: String
    let client: BubuLearningClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var current: String
    @State private var route: TimelinePagerRoute?

    init(issues: [MonthlyReportDTO], initialMonth: String, client: BubuLearningClient) {
        self.issues = issues
        self.initialMonth = initialMonth
        self.client = client
        _current = State(initialValue: initialMonth)
    }

    private var index: Int { issues.firstIndex { $0.month == current } ?? 0 }

    var body: some View {
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            TabView(selection: $current) {
                ForEach(Array(issues.enumerated()), id: \.element.id) { offset, report in
                    MonthlyIssuePage(report: report, number: offset + 1, client: client) { items, item in
                        route = TimelinePagerRoute(items: items, initial: item)
                    }
                    .tag(report.month)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .safeAreaInset(edge: .bottom) { pageBar }
        .navigationTitle("第 \(index + 1) 期")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: current) { _, _ in BubuHaptics.selection() }
        .navigationDestination(item: $route) { route in
            OnlineTimelineDetailPager(client: client, items: route.items, initial: route.initial, loadMore: {}, hasMore: false)
        }
        .accessibilityIdentifier("monthly.reader")
    }

    private var pageBar: some View {
        HStack {
            Button { turn(-1) } label: { Label("上一期", systemImage: "chevron.left") }
                .disabled(index == 0)
            Spacer()
            Text("\(index + 1) / \(issues.count)").font(BubuTheme.Font.caption.monospacedDigit())
                .foregroundStyle(BubuTheme.Color.secondaryText).contentTransition(.numericText())
            Spacer()
            Button { turn(1) } label: { Label("下一期", systemImage: "chevron.right").labelStyle(TrailingIconLabelStyle()) }
                .disabled(index >= issues.count - 1)
        }
        .font(BubuTheme.Font.caption.weight(.semibold))
        .tint(BubuTheme.Color.deepRose)
        .padding(.horizontal, BubuTheme.Spacing.l).padding(.vertical, BubuTheme.Spacing.s)
        .background(.ultraThinMaterial)
    }

    private func turn(_ step: Int) {
        let target = index + step
        guard issues.indices.contains(target) else { return }
        withAnimation(reduceMotion ? nil : BubuMotion.gentle) { current = issues[target].month }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon }
    }
}

/// One issue laid out like a magazine spread.
private struct MonthlyIssuePage: View {
    let report: MonthlyReportDTO
    let number: Int
    let client: BubuLearningClient
    let open: ([OnlineTimelineItem], OnlineTimelineItem) -> Void
    @State private var items: [OnlineTimelineItem] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.l) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("布布成长月刊 · 第 \(number) 期").font(BubuTheme.Font.scaled(12, weight: .heavy)).tracking(1)
                        .foregroundStyle(BubuTheme.Color.deepRose)
                    Text(SecondBrainMonths.caption(report.month)).font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                    Text(report.title.isEmpty ? "这个月的小报" : report.title)
                        .font(BubuTheme.Font.hugeTitle).foregroundStyle(BubuTheme.Color.warmBrown)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                if let hero = items.first {
                    Button { open(items, hero) } label: {
                        Color.clear.aspectRatio(4.0 / 3.0, contentMode: .fit)
                            .overlay { LearningRemoteImage(path: hero.largeUrl, client: client, label: hero.description, contentMode: .fill, diskCache: true) }
                            .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                    }
                    .buttonStyle(BubuPressableStyle())
                } else if !loaded, !report.highlightIds.isEmpty {
                    RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
                        .fill(BubuTheme.Color.hueSurface(MonthlyMagazine.hue(report.month)))
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
                        .overlay { ProgressView() }
                }

                if !report.summary.isEmpty {
                    Text(report.summary).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
                        .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                }

                if items.count > 1 {
                    VStack(alignment: .leading, spacing: BubuTheme.Spacing.s) {
                        Text("本期精选").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                            ForEach(items.dropFirst()) { item in
                                Button { open(items, item) } label: { SecondBrainThumb(item: item, client: client, height: 110) }
                                    .buttonStyle(BubuPressableStyle())
                            }
                        }
                    }
                }

                if !report.firsts.isEmpty {
                    section("这个月的第一次", symbol: "star.fill", tint: BubuTheme.Color.deepRose, values: report.firsts)
                }
                let places = MonthlyMagazine.shortPlaces(report.places)
                if !places.isEmpty {
                    section("去过的地方", symbol: "mappin.and.ellipse", tint: BubuTheme.Color.warmBrown, values: places)
                }
                Label("这个月存下照片 \(report.photos) 张 · 视频 \(report.videos) 段", systemImage: "photo.stack")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .padding(BubuTheme.Spacing.l)
            .background(BubuTheme.Color.card.opacity(0.95), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .padding(BubuTheme.Spacing.item)
            .bubuContentColumn(760)
        }
        .task {
            guard !loaded else { return }
            defer { loaded = true }
            guard !report.highlightIds.isEmpty else { return }
            items = (try? await client.timelineItems(ids: Array(report.highlightIds.prefix(12)))) ?? []
        }
    }

    private func section(_ title: String, symbol: String, tint: Color, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.s) {
            Label(title, systemImage: symbol).font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(tint)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(values, id: \.self) { value in
                    Text(value).font(BubuTheme.Font.caption.weight(.semibold)).foregroundStyle(BubuTheme.Color.warmBrown)
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(BubuTheme.Color.pinkSurface, in: Capsule())
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
