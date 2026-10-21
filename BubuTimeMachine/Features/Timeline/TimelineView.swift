import SwiftUI
import SwiftData

// MARK: - 时光轴（分页外壳）
/// 只做一件事：持有「当前取多少条」和排序方式，把它们喂给真正的列表视图。
///
/// 为什么需要这层壳：`@Query` 的取数描述符是在 `init` 里定下的，
/// 视图内部的 `@State` 变了不会重建描述符。要做「先取一页、滚到底再取一页」，
/// 就必须由**外层**把新的页大小作为参数传进来，触发内层重新 init。
///
/// 为什么要分页：原来是无 fetchLimit 的全量 `@Query`。三年量能扛，
/// 十年（这个 App 的目标是陪到 18 岁）必然把冷启动和滚动一起拖垮。
struct TimelineView: View {
    /// 每页条数。一屏最多显示 3~4 条，200 条足够连翻很久都不触底。
    static let pageStep = 200
    @State private var pageLimit = TimelineView.pageStep
    @State private var filters = TimelineFilters()
    /// 搜索词与筛选一起重建数据库查询，结果仍按页取回。
    @State private var searchText = TimelineList.semanticVisualProbe ? "扶着沙发学走路" : ""
    @AppStorage("bubu.timeline.sortMode") private var sortModeRaw = TimelineSortMode.capture.rawValue

    var body: some View {
        TimelineList(pageLimit: pageLimit,
                     sortMode: TimelineSortMode(rawValue: sortModeRaw) ?? .capture,
                     searchText: $searchText, filters: $filters,
                     onNeedMore: { pageLimit += TimelineView.pageStep })
            .onChange(of: searchText) { _, _ in pageLimit = Self.pageStep }
            .onChange(of: filters) { _, _ in pageLimit = Self.pageStep }
            .onChange(of: sortModeRaw) { _, _ in pageLimit = Self.pageStep }
    }
}

// MARK: - 时光轴列表
/// @Query 按当前排序方式取一页本地 Entry，按「年-月」分段展示；
/// 排序方式可切（拍摄时间/记录时间），偏好持久记忆。
/// 离线优先：UI 只读本地 SwiftData，断网全功能可用。
struct TimelineList: View {
    /// 本次取数的上限，由外层 TimelineView 递增。
    private let pageLimit: Int
    /// 滚到底部时请求下一页。
    private let onNeedMore: () -> Void

    init(pageLimit: Int, sortMode: TimelineSortMode,
         searchText: Binding<String>, filters: Binding<TimelineFilters> = .constant(.init()),
         onNeedMore: @escaping () -> Void) {
        self.pageLimit = pageLimit
        self.onNeedMore = onNeedMore
        self._searchText = searchText
        self._filters = filters
        let descriptor = TimelineEntryQuery.descriptor(filters: filters.wrappedValue,
            query: Self.semanticVisualProbe ? "" : searchText.wrappedValue, sort: sortMode, limit: pageLimit)
        _entries = Query(descriptor, animation: .default)
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query private var entries: [Entry]
    @Query private var profiles: [ChildProfile]
    @State private var showFamilyFeed = false
    @State private var showFilters = false
    @State private var entryPendingDelete: Entry?
    /// 长按「分享这一刻」选中的记录。
    @State private var entryPendingShare: Entry?
    @State private var sections: [TimelineSection] = []
    /// 由外层持有：数据库先匹配搜索词，再取当前页，不展开整库常驻内存。
    @Binding private var searchText: String
    @Binding private var filters: TimelineFilters
    @State private var remoteEntries: [Entry] = []
    @State private var remoteRawHits: [SemanticSearchHit] = []
    @State private var remoteResultsKey: SemanticSearchTaskKey?
    @State private var pendingRemoteCount = 0
    @State private var remoteHasMore = false
    @State private var remoteFailureMessage: String?
    @State private var searchRetry = 0
    @State private var semanticMatches: [UUID: SemanticSearchHit] = [:]
    @State private var semanticSearchState: SemanticSearchState = .idle
    /// 排序方式偏好：默认按拍摄时间（成长回顾心智），可切按记录时间（家庭动态心智）。
    @AppStorage("bubu.timeline.sortMode") private var sortModeRaw = TimelineSortMode.capture.rawValue
    /// 未读家庭动态红点：一次性算好缓存，避免每次 body 全表 faulting comments（P2e）。
    @State private var hasUnseenFamilyActivity = false
    @Namespace private var zoomNS
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 删除后的撤销提示。软删除（isArchived）本来就可逆，把这条退路显式给到用户。
    @State private var undoToast: BubuToastState?

    /// 宽屏（iPad 全屏/半屏）：时光轴改双列、封面限高。窄屏（含 iPad 1/3 分屏）保持单列。
    private var isWide: Bool { BubuAdaptive.isWide(sizeClass) }

    var body: some View {
        #if DEBUG
        let bodyT0 = CFAbsoluteTimeGetCurrent()
        #endif
        let semanticTaskKey = SemanticSearchTaskKey(
            query: searchText,
            enabled: env.config.isAIConfigured || Self.semanticVisualProbe,
            serviceRevision: env.aiServiceRevision, entriesRevision: entriesRevision,
            filters: filters, sort: sortMode, access: LearningServiceAccess(env),
            visualEnabled: env.config.semanticSearchEnabled, retry: searchRetry
        )
        #if DEBUG
        let _ = Self.logSlowKey(CFAbsoluteTimeGetCurrent() - bodyT0, entries: entries.count)
        #endif
        ZStack {
            BubuTheme.Color.background.ignoresSafeArea()

            if sections.isEmpty {
                if filters.isActive || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchEmptyState
                } else { emptyState }
            } else {
                timeline
            }
        }
        .navigationTitle("时光轴")
        .navigationBarTitleDisplayMode(.inline)
        // 显式钉在导航栏抽屉里。不指定时，iOS 26 会按容器自行决定：
        // 在 Tab 容器内落到顶部（现状正确），脱离 Tab 容器（如直达探针）则改成底部悬浮条，
        // 直接压在列表内容上。搜索位置不该随容器漂移，这里固定住。
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: env.config.isAIConfigured
                    ? "找文字、画面描述或视频内容" : "找找\(profiles.first?.name ?? "布布")的记录")
        // 本地文字结果立即出现；停顿 300ms 后再请求家中语义索引。请求失败不影响离线结果。
        .task(id: semanticTaskKey) { await updateSearch(semanticTaskKey) }
        .onAppear { rebuildSections(); refreshUnseenBadge() }
        .onChange(of: entries) { _, _ in
            entriesRevision += 1
            // 卡片的增删都由 sections 驱动。不裹动画的话，删除是「瞬间蒸发」——
            // 与保存成功的仪式感落差极大，也让人怀疑是不是点错了。
            if reduceMotion {
                rebuildSections()
            } else {
                withAnimation(BubuMotion.gentle) { rebuildSections() }
            }
            refreshUnseenBadge()
        }
        .onChange(of: sortModeRaw) { _, _ in rebuildSections() }
        .onChange(of: filters) { _, _ in rebuildSections() }
        .onChange(of: searchText) { _, _ in rebuildSections() }
        .onChange(of: env.syncEngine.isSyncing) { _, running in
            if !running, pendingRemoteCount > 0 { refreshRemoteMapping(); rebuildSections() }
        }
        .safeAreaInset(edge: .top, spacing: 0) { if filters.isActive { filterSummary } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showFilters = true } label: {
                    Label("筛选", systemImage: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }.accessibilityIdentifier("timeline.filters")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("排序方式", selection: $sortModeRaw) {
                        ForEach(TimelineSortMode.allCases, id: \.rawValue) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                } label: {
                    Label("排序方式", systemImage: "arrow.up.arrow.down")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFamilyFeed = true
                    // 打开即视为已读
                    UserDefaults.standard.set(Date.now, forKey: "bubu.feed.lastSeenAt")
                    hasUnseenFamilyActivity = false
                } label: {
                    Label("家庭动态", systemImage: "person.2.wave.2.fill")
                }
                // 未读红点（R4 F-3）：上次看过之后家人有新动态就亮
                .overlay(alignment: .topTrailing) {
                    if hasUnseenFamilyActivity {
                        Circle().fill(BubuTheme.Color.danger).frame(width: 8, height: 8).offset(x: 2, y: -1)
                    }
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            TimelineFilterSheet(filters: $filters)
        }
        .sheet(isPresented: $showFamilyFeed) {
            NavigationStack { FamilyFeedView() }
        }
        .sheet(item: $entryPendingShare) { entry in
            ShareCardSheet(entry: entry)
        }
        .alert("删除这条记录？", isPresented: Binding(
            get: { entryPendingDelete != nil },
            set: { if !$0 { entryPendingDelete = nil } }
        )) {
            Button("删除", role: .destructive) { deletePendingEntry() }
            Button("取消", role: .cancel) { entryPendingDelete = nil }
        } message: {
            Text("删除后会从时光轴隐藏，本地记录会标记为待同步删除。")
        }
        .bubuToast($undoToast)
        .bubuIOS27NavigationPolish()
    }

    /// 上次看过动态之后，家里其他人有没有新动作（新记录/新评论）。一次性算好写入缓存。
    private func refreshUnseenBadge() {
        let lastSeen = UserDefaults.standard.object(forKey: "bubu.feed.lastSeenAt") as? Date ?? .distantPast
        let myRole = env.config.currentRole.rawValue
        if entries.contains(where: { $0.createdAt > lastSeen && $0.authorRole != myRole }) {
            hasUnseenFamilyActivity = true
            return
        }
        hasUnseenFamilyActivity = entries.contains { entry in
            entry.comments.contains { $0.createdAt > lastSeen && $0.authorRole != myRole }
        }
    }

    private var timeline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BubuTheme.Spacing.section, pinnedViews: [.sectionHeaders]) {
                if shouldShowSemanticStatus {
                    semanticStatusBanner
                }
                ForEach(Array(sections.enumerated()), id: \.element.key) { sectionIndex, section in
                    Section {
                        // 虚线竖轴 + hue 圆点（对照设计稿 MacTimeline）
                        ZStack(alignment: .topLeading) {
                            // 竖向虚线（落在圆点中心 x ≈ 15）
                            Rectangle()
                                .fill(BubuTheme.Color.peach)
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                                .padding(.leading, 14)
                                .padding(.vertical, 18)
                                .opacity(0.55)

                            if isWide {
                                // 宽屏双列：单列在 iPad 上信息密度太低，一屏只能看一两条
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 296), spacing: 16)],
                                          spacing: 16) {
                                    ForEach(section.entries) { entry in
                                        timelineRow(entry, sectionIndex: sectionIndex)
                                    }
                                }
                                .padding(.leading, 30)   // 让开左侧竖轴装饰
                            } else {
                                LazyVStack(alignment: .leading, spacing: 16) {
                                    ForEach(section.entries) { entry in
                                        timelineRow(entry, sectionIndex: sectionIndex)
                                    }
                                }
                            }
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }
                // 触底加载下一页：取满一页说明后面很可能还有，
                // 这个哨兵出现在视野里就把窗口再放大一页，搜索结果同样分页。
                if entries.count >= pageLimit {
                    HStack {
                        Spacer()
                        ProgressView().tint(BubuTheme.Color.primary)
                        Text(sortMode.ascending ? "正在翻出后面的时光…" : "正在翻出更多时光…")
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                        Spacer()
                    }
                    .padding(.vertical, BubuTheme.Spacing.l)
                    .onAppear { onNeedMore() }
                }
            }
            .padding()
        }
        // 同上：时光轴是最想「看看家人有没有新记录」的地方，下拉必须有反应。
        .refreshable {
            env.syncEngine.syncNow()
            try? await Task.sleep(for: .milliseconds(650))
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { searchRetry += 1 }
        }
        .bubuIOS27SwipeActionsContainer()
        .navigationDestination(for: UUID.self) { entryID in
            TimelineEntryDestination(entryID: entryID)
                .navigationTransition(.zoom(sourceID: entryID, in: zoomNS))
        }
    }

    // 单条：左侧 hue 圆点 + 右侧大图卡片
    private func timelineRow(_ entry: Entry, sectionIndex: Int) -> some View {
        // scrollTransition 的闭包是 Sendable 的，不能在里面读 @Environment；先取成局部值。
        let animates = !reduceMotion
        return HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(BubuTheme.Color.hue(entry.id.bubuStableHue, lightness: 0.78))
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                .padding(.top, 16)
            NavigationLink(value: entry.id) {
                bigPhotoCard(entry)
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: entry.id, in: zoomNS)
            .accessibilityIdentifier("timeline.memory.\(entry.id.uuidString)")
            .entranceEffect(index: entranceIndex(sectionIndex: sectionIndex, entryId: entry.id))
            // 进出视口时轻微淡入淡出 + 缩放。幅度刻意很小：时光轴是每天翻的页面，
            // 动效要像纸张的质感，不能像特效。reduceMotion 时整段跳过。
            .scrollTransition(.interactive) { view, phase in
                view.opacity(animates && !phase.isIdentity ? 0.72 : 1)
                    .scaleEffect(animates && !phase.isIdentity ? 0.97 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
            // 删除不再是卡片上常驻的裸垃圾桶键（每天翻时光轴，误触代价是丢一条回忆）。
            // 统一收进长按菜单：多一步长按当摩擦，删完还有 3.5 秒撤销。
            .contextMenu {
                Button { entryPendingShare = entry } label: {
                    Label("分享这一刻", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) { entryPendingDelete = entry } label: {
                    Label("删除记录", systemImage: "trash")
                }
            }
            .accessibilityAction(named: "分享这一刻") { entryPendingShare = entry }
            .accessibilityAction(named: "删除记录") { entryPendingDelete = entry }
            .bubuIOS27TimelineActions(
                onShare: { entryPendingShare = entry },
                onDelete: { entryPendingDelete = entry })
        }
    }

    // 真实媒体保留大图；纯文字/声音直接阅读，不用假照片占据封面空间。
    private func bigPhotoCard(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let media = cardMedia(entry) {
                ZStack(alignment: .bottomLeading) {
                    MediaThumbnail(media: media, mediaStore: env.mediaStore)
                    // 封面按照片自己的长宽比排版（夹在 4:5 ~ 1.9:1 之间）：
                    // 原来固定 178 高，竖图会被裁成中间一条窄带，看不出拍了什么。
                    // 宽屏把最小比例收紧到 1.5（而不是加 maxHeight——那会让封面按比例缩小、两侧留灰边）：
                    // 高度 = 宽 / 比例，天然受控，同时始终填满卡片宽度。
                    .aspectRatio(coverAspect(media), contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Text("\(BubuDateFormat.monthDay(entry.happenedAt)) · \(BubuDateFormat.shortTime(entry.happenedAt))")
                        .font(BubuTheme.Font.scaled(12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .padding(.horizontal, 14).padding(.bottom, 10)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(cardHeadline(entry))
                        .font(BubuTheme.Font.scaled(15.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .lineLimit(1)
                    // 无标题时正文已被顶上去当标题，这里不能再原样重复一遍。
                    if let note = cardSubtitle(entry) {
                        Text(note)
                            .font(BubuTheme.Font.scaled(12.5, weight: .regular, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        if let mood = entry.mood {
                            BubuTag(text: "\(mood.emoji) \(mood.rawValue)")
                        }
                        if let ft = entry.firstTime?.what, !ft.isEmpty {
                            BubuTag(text: "第一次 · \(ft)", background: BubuTheme.Color.pink.opacity(0.5),
                                    foreground: BubuTheme.Color.deepRose)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                    if let hit = currentSearchHit(for: entry.id) {
                        Label(semanticReason(entry: entry, hit: hit), systemImage: "sparkle.magnifyingglass")
                            .font(BubuTheme.Font.caption.weight(.semibold))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                            .accessibilityLabel("语义匹配原因：\(semanticReason(entry: entry, hit: hit))")
                    }
                }
                .padding(14)
            } else {
                compactTextContent(entry)
            }
        }
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        .bubuCardShadow()
        // 一张卡上有封面、日期、标题、正文、若干标签；逐个朗读要滑七八下才过一条记录。
        // 合成一句「日期 · 标题 · 正文」，与视觉主次一致。
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cardAccessibilityLabel(entry))
    }

    private func compactTextContent(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(BubuDateFormat.monthDay(entry.happenedAt)) · \(BubuDateFormat.shortTime(entry.happenedAt)) · \(entry.authorRole)")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                if let note = cardSubtitle(entry) {
                    Text(cardHeadline(entry))
                        .font(BubuTheme.Font.body.weight(.semibold))
                        .lineLimit(1)
                    Text(note)
                        .font(BubuTheme.Font.body)
                        .lineLimit(4)
                } else {
                    Text(cardHeadline(entry))
                        .font(BubuTheme.Font.body)
                        .lineLimit(4)
                }
            }
            .foregroundStyle(BubuTheme.Color.warmBrown)
            .fixedSize(horizontal: false, vertical: true)

            if !entry.voiceNotes.isEmpty {
                Label(entry.voiceNotes.count == 1 ? "语音记录" : "\(entry.voiceNotes.count) 段语音", systemImage: "waveform")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            if entry.mood != nil || !(entry.firstTime?.what.isEmpty ?? true) {
                FlowLayout(spacing: 6) {
                    if let mood = entry.mood {
                        BubuTag(text: "\(mood.emoji) \(mood.rawValue)")
                    }
                    if let ft = entry.firstTime?.what, !ft.isEmpty {
                        BubuTag(text: "第一次 · \(ft)", background: BubuTheme.Color.pink.opacity(0.5),
                                foreground: BubuTheme.Color.deepRose)
                    }
                }
            }
            if let hit = currentSearchHit(for: entry.id) {
                Label(semanticReason(entry: entry, hit: hit), systemImage: "sparkle.magnifyingglass")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("语义匹配原因：\(semanticReason(entry: entry, hit: hit))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    private func cardAccessibilityLabel(_ entry: Entry) -> String {
        var parts = ["\(BubuDateFormat.monthDay(entry.happenedAt)) \(BubuDateFormat.shortTime(entry.happenedAt))"]
        if cardMedia(entry) == nil {
            parts.append(entry.authorRole)
            if !entry.voiceNotes.isEmpty { parts.append("\(entry.voiceNotes.count) 段语音") }
        }
        parts.append(cardHeadline(entry))
        if let note = cardSubtitle(entry) { parts.append(note) }
        if let mood = entry.mood { parts.append("心情\(mood.rawValue)") }
        if let ft = entry.firstTime?.what, !ft.isEmpty { parts.append("第一次\(ft)") }
        return parts.joined(separator: "，")
    }

    /// 标题/副文案规则抽在 TimelineCardText（纯函数 + 单测），避免「同一句话上下重复」复发。
    private func cardHeadline(_ entry: Entry) -> String {
        TimelineCardText.headline(title: entry.title, note: TimelineFilters.displayNote(entry.note))
    }

    private func cardSubtitle(_ entry: Entry) -> String? {
        TimelineCardText.subtitle(title: entry.title, note: TimelineFilters.displayNote(entry.note))
    }

    /// 封面长宽比：取媒体真实比例并夹在可读区间。
    /// 下限 0.8（≈4:5 竖幅，再高的竖图会把一屏塞满、时光轴不好翻）；
    /// 上限 1.9（超宽全景不至于压成一条缝）；缺尺寸的老记录回退 1.5（与旧版观感接近）。
    private static let coverMinAspect: CGFloat = 0.8
    private static let coverMaxAspect: CGFloat = 1.9
    private static let coverFallbackAspect: CGFloat = 1.5

    private func coverAspect(_ media: Media?) -> CGFloat {
        // 宽屏最小比例 1.5：卡片宽时若仍允许 0.8 的竖幅，单张封面能顶到近 500pt 高。
        let minAspect = isWide ? 1.5 : Self.coverMinAspect
        guard let media, let w = media.width, let h = media.height, w > 0, h > 0 else {
            return max(Self.coverFallbackAspect, minAspect)
        }
        return min(max(CGFloat(w) / CGFloat(h), minAspect), Self.coverMaxAspect)
    }

    /// 月份 + 年龄锚点：翻旧记录时「布布多大」比日期更有感。
    private func sectionHeader(_ section: TimelineSection) -> some View {
        HStack(spacing: 8) {
            Text(section.key)
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            if let profile = profiles.first, let anchor = section.entries.first.map(sortDate) {
                Text("\(profile.name) \(AgeCalculator.compactAge(birthday: profile.birthday, at: anchor))")
                    .font(BubuTheme.Font.caption.weight(.medium))
                    .foregroundStyle(env.theme.theme.textAccent)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(env.theme.theme.primary.opacity(0.10), in: Capsule())
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.background.opacity(0.95))
    }

    private var filterSummary: some View {
        HStack(spacing: 10) {
            Text(filterDescription).font(BubuTheme.Font.caption).lineLimit(2)
            Spacer(minLength: 0)
            Button("清除筛选") { filters = .init() }.font(BubuTheme.Font.caption.weight(.semibold))
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 16).background(BubuTheme.Color.card)
    }

    private var filterDescription: String {
        var parts: [String] = []
        if filters.kind != .all { parts.append(filters.kind.title) }
        if filters.source != .all { parts.append(filters.source.title) }
        if let start = filters.start { parts.append("从 " + BubuDateFormat.shortDate(start)) }
        if let end = filters.end { parts.append("截至 " + BubuDateFormat.shortDate(end)) }
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            BubuEmptyIllustration(assetName: "BubuEmptyTimeline", fallbackExpression: .bye)
            Text("等待第二大脑同步布布的时光")
                .font(BubuTheme.Font.body.weight(.semibold))
            Text("已确认属于布布的素材会自动出现在这里，家人留下的记录也会保留。")
                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
            Button("同步家庭记录") { env.syncEngine.syncNow() }.buttonStyle(.bordered)
        }.padding(32)
    }

    private var searchEmptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                BubuMascotBadge(size: 72, expression: .surprised)
                if semanticSearchState == .searching {
                    ProgressView("正在查找第二大脑的素材解析…")
                } else if pendingRemoteCount > 0, remoteResultsAreCurrent {
                    Text("找到相关时光，正在等这台设备同步")
                        .font(BubuTheme.Font.body.weight(.semibold))
                } else if semanticSearchState == .offlineFallback {
                    Text("暂时没能完成解析检索")
                        .font(BubuTheme.Font.body.weight(.semibold))
                } else {
                    Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "这个筛选条件下暂时没有时光" : "本机暂未找到「\(searchText)」的匹配记录")
                        .font(BubuTheme.Font.body).multilineTextAlignment(.center)
                }
                if shouldShowSemanticStatus { semanticStatusBanner }
                if filters.isActive {
                    Button("清除筛选，再看看") { filters = .init() }.buttonStyle(.bordered)
                }
                if !searchText.isEmpty { Button("清除搜索词") { searchText = "" } }
                Button("同步家庭记录") { env.syncEngine.syncNow() }
            }.padding(30)
        }
    }

    // MARK: 分段

    private struct TimelineSection {
        let key: String
        let entries: [Entry]
    }

    private struct SemanticSearchTaskKey: Hashable {
        let query: String
        let enabled: Bool
        let serviceRevision: Int
        let entriesRevision: Int
        let filters: TimelineFilters
        let sort: TimelineSortMode
        let access: LearningServiceAccess?
        let visualEnabled: Bool
        let retry: Int
    }

    private enum SemanticSearchState: Equatable {
        case idle
        case searching
        case active
        case offlineFallback
    }

    private var shouldShowSemanticStatus: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        semanticSearchState != .idle &&
        (env.config.isAIConfigured || Self.semanticVisualProbe) && filters.kind != .audio
    }

    static var semanticVisualProbe: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uitest-semantic-result")
        #else
        false
        #endif
    }

    /// 仅作当前进程 task 失效键：Entry 或媒体/remoteId 后补时，活跃查询自动重跑。
    /// 【性能事故现场，别改回计算属性】原实现是 body 里的计算属性：
    /// 遍历全库 entries × 每条的 media 关系——首次访问触发 SwiftData faulting（主线程磁盘读）。
    /// 实测 400 条 × 2 媒体：每次 body 65-77ms，一次进页 body 求值 5 次 ≈ 350ms 纯阻塞，
    /// 真机真实照片库上这就是「点时光 Tab 卡 1 秒」的主因。
    /// 改为计数器：entries 变化时在已有的 onChange 里 +1，body 里零遍历。
    /// 语义损失（media.remoteId 同步完成不再触发重搜）可接受：
    /// 命中解析在渲染时兜底（cardMedia 找不到 remoteId 会落到封面图）。
    @State private var entriesRevision = 0

    @ViewBuilder
    private var semanticStatusBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                switch semanticSearchState {
                case .searching:
                    ProgressView().controlSize(.small)
                    Text("正在查找第二大脑解析…")
                case .active:
                    Image(systemName: "sparkle.magnifyingglass")
                    Text("已查找本机文字与第二大脑解析")
                case .offlineFallback:
                    Image(systemName: "wifi.slash")
                    Text(remoteFailureMessage ?? "解析检索暂不可用，本机结果仍可查看")
                case .idle: EmptyView()
                }
                Spacer(minLength: 0)
            }
            if pendingRemoteCount > 0, remoteResultsAreCurrent {
                Text("另有 \(pendingRemoteCount) 条匹配时光尚未同步到这台设备。")
                Button("同步家庭记录") { env.syncEngine.syncNow() }
            }
            if remoteHasMore, remoteResultsAreCurrent {
                Text("解析匹配仅展示前 50 项。可以缩小拍摄日期或搜索词，继续找其他结果。")
            }
            if semanticSearchState == .offlineFallback {
                Button("重试解析检索") { searchRetry += 1 }
            }
        }
        .font(BubuTheme.Font.caption.weight(.semibold))
        .foregroundStyle(BubuTheme.Color.secondaryText)
        .padding(14)
        .background(BubuTheme.Color.card.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
    }

    /// 仅首屏 section 的前 6 张做错峰入场动画，其余直接呈现。
    /// 用首屏首个 section 的 id 集合判断，避免每个 cell O(n) 查找。
    private func entranceIndex(sectionIndex: Int, entryId: UUID) -> Int {
        guard sectionIndex == 0, let first = sections.first else { return 6 }
        if let idx = first.entries.prefix(6).firstIndex(where: { $0.id == entryId }) {
            return idx
        }
        return 6
    }

    private var remoteResultsAreCurrent: Bool {
        guard let key = remoteResultsKey else { return false }
        return key.query == searchText && key.filters == filters && key.sort == sortMode
            && key.serviceRevision == env.aiServiceRevision && key.access == LearningServiceAccess(env)
            && key.visualEnabled == env.config.semanticSearchEnabled
    }

    private func currentSearchHit(for id: UUID) -> SemanticSearchHit? {
        remoteResultsAreCurrent ? semanticMatches[id] : nil
    }

    private func updateSearch(_ key: SemanticSearchTaskKey) async {
        semanticMatches = [:]; remoteEntries = []; remoteRawHits = []; remoteResultsKey = nil
        pendingRemoteCount = 0; remoteHasMore = false; remoteFailureMessage = nil
        semanticSearchState = .idle
        rebuildSections()
        let query = key.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, key.enabled, key.filters.kind != .audio else { return }
#if DEBUG
        if Self.semanticVisualProbe, let entry = entries.first {
            remoteRawHits = [SemanticSearchHit(assetId: "visual-probe", entryLocalId: entry.id.uuidString,
                mediaRecordId: "visual-probe", capturedAt: ISO8601DateFormatter().string(from: entry.happenedAt),
                score: 0.93, reason: "画面语义接近“扶着沙发学走路”")]
            remoteResultsKey = key
            refreshRemoteMapping(); semanticSearchState = .active; rebuildSections()
            return
        }
#endif
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        guard !Task.isCancelled, let access = key.access, LearningServiceAccess(env) == access else { return }
        semanticSearchState = .searching
        let api = env.apiClient
        let visualService = env.aiService
        var hits: [SemanticSearchHit] = []
        var failure: String?
        var more = false
        do {
            let token = try await api.authenticate(role: "ai").token
            guard !Task.isCancelled, LearningServiceAccess(env) == access else { return }
            let response = try await TimelineAnalysisSearchClient(baseURL: access.baseURL)
                .search(query: query, filters: key.filters, sort: key.sort, token: token)
            more = response.hasMore || response.items.count > 50
            hits = response.confirmedHits.map { hit in
                SemanticSearchHit(assetId: "analysis:" + hit.mediaID, entryLocalId: hit.entryLocalID,
                    mediaRecordId: hit.mediaID, capturedAt: hit.capturedAt ?? "", score: 0,
                    reason: hit.matchReason?.isEmpty == false ? hit.matchReason! : "第二大脑解析：" + String((hit.description ?? "内容匹配").prefix(100)))
            }
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled else { return }
            failure = (error as? LearningServiceError)?.errorDescription ?? "第二大脑解析检索暂不可用，已保留本机结果"
        }
        // Preserve the existing, separately opted-in visual search. Both channels only map to local facts.
        if key.visualEnabled, !Task.isCancelled, LearningServiceAccess(env) == access {
            do {
                let response = try await visualService.semanticSearch(query: query, limit: 30)
                if response.query == query { hits.append(contentsOf: response.hits.prefix(30)) }
            } catch is CancellationError { return }
            catch {
                if failure == nil { failure = "画面检索暂不可用，本机文字与第二大脑解析结果仍可查看" }
            }
        }
        guard !Task.isCancelled, searchText == key.query, filters == key.filters,
              sortMode == key.sort, LearningServiceAccess(env) == access else { return }
        remoteRawHits = hits; remoteResultsKey = key; remoteHasMore = more; remoteFailureMessage = failure
        semanticSearchState = failure == nil ? .active : .offlineFallback
        refreshRemoteMapping()
        rebuildSections()
    }

    /// Fetch only bounded remote IDs, including those outside the current text-search page.
    /// Re-run this local mapping when a sync completes; it never polls the network.
    private func refreshRemoteMapping() {
        guard remoteResultsAreCurrent else { return }
        let ids = Array(Set(remoteRawHits.compactMap { UUID(uuidString: $0.entryLocalId) }))
        guard !ids.isEmpty else { remoteEntries = []; semanticMatches = [:]; pendingRemoteCount = 0; return }
        do {
            var existing = FetchDescriptor<Entry>(predicate: #Predicate { ids.contains($0.id) })
            existing.fetchLimit = 80
            let known = try context.fetch(existing)
            let references = remoteRawHits.compactMap { hit -> (entryID: UUID, mediaID: String)? in
                guard let id = UUID(uuidString: hit.entryLocalId) else { return nil }
                return (id, hit.mediaRecordId)
            }
            pendingRemoteCount = Self.semanticVisualProbe ? 0 : TimelineEntryQuery.pendingRemoteCount(references: references, known: known)
            remoteEntries = try context.fetch(TimelineEntryQuery.descriptor(filters: filters, query: "",
                sort: sortMode, limit: 80, entryIDs: ids))
            if filters.kind != .all {
                remoteEntries = remoteEntries.filter { entry in
                    remoteRawHits.contains { hit in
                        hit.entryLocalId.caseInsensitiveCompare(entry.id.uuidString) == .orderedSame
                            && entry.sortedMedia.contains { $0.remoteId == hit.mediaRecordId && $0.typeRaw == filters.kind.rawValue }
                    }
                }
            }
            let available = Set(remoteEntries.map(\.id))
            var matches = TimelineSemanticSearchResolver.bestHits(
                remoteRawHits.filter { !$0.assetId.hasPrefix("analysis:") }, availableEntryIDs: available)
            var explained: Set<UUID> = []
            // The analysis endpoint has no confidence score; prefer its first explanation explicitly instead of inventing one.
            for hit in remoteRawHits where hit.assetId.hasPrefix("analysis:") {
                if let id = UUID(uuidString: hit.entryLocalId), available.contains(id), explained.insert(id).inserted {
                    matches[id] = hit
                }
            }
            semanticMatches = matches
        } catch {
            remoteEntries = []; semanticMatches = [:]
            remoteFailureMessage = "本机记录暂时未能读取完整，请稍后重试。"
            semanticSearchState = .offlineFallback
        }
    }

    private func cardMedia(_ entry: Entry) -> Media? {
        guard let recordID = currentSearchHit(for: entry.id)?.mediaRecordId else { return filterCover(entry) }
        // 不在 ?? autoclosure 里捕获 SwiftData 模型；Release whole-module 会按严格并发拒绝。
        let matched = entry.sortedMedia.first(where: { $0.remoteId == recordID })
        let fallback = filterCover(entry)
        return matched ?? fallback
    }

    private func filterCover(_ entry: Entry) -> Media? {
        if filters.kind == .photo || filters.kind == .video {
            return entry.sortedMedia.first { $0.typeRaw == filters.kind.rawValue }
        }
        return entry.coverMedia
    }

    private func semanticReason(entry: Entry, hit: SemanticSearchHit) -> String {
        let matchedMedia = entry.sortedMedia.first(where: { $0.remoteId == hit.mediaRecordId })
        let clean = hit.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "画面语义接近", with: "画面接近")
        if matchedMedia == nil, entry.coverMedia != nil {
            return "这条记录中的另一份素材：" + clean
        }
        return clean
    }

    private var sortMode: TimelineSortMode { TimelineSortMode(rawValue: sortModeRaw) ?? .capture }

    /// 当前排序方式下条目的排序/分组键。
    private func sortDate(_ entry: Entry) -> Date {
        sortMode == .recorded ? entry.createdAt : entry.happenedAt
    }

    /// 重新分组：仅在 entries / 搜索词 / 排序方式变化时调用，避免每次 body 求值 O(n) 重分组。
    /// @Query 已按当前顺序取页；这里把有限的本机页与远端映射结果合并分组。
    #if DEBUG
    /// 性能取证：semanticTaskKey（含全库 revision 遍历）在 body 里的耗时。
    /// `-uitest-perf` 时打印每次；平时只在超 8ms 时告警。
    nonisolated static func logSlowKey(_ seconds: Double, entries: Int) {
        let ms = seconds * 1000
        if ProcessInfo.processInfo.arguments.contains("-uitest-perf") {
            print("BUBUPERF key=\(String(format: "%.1f", ms))ms entries=\(entries)")
        } else if ms > 8 {
            print("BUBUPERF SLOW key=\(String(format: "%.1f", ms))ms entries=\(entries)")
        }
    }
    #endif

    private func rebuildSections() {
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        defer {
            if ProcessInfo.processInfo.arguments.contains("-uitest-perf") {
                print("BUBUPERF sections=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
            }
        }
        #endif
        let calendar = Calendar.current
        let filtered = matchingEntries.sorted { sortMode.ascending ? sortDate($0) < sortDate($1) : sortDate($0) > sortDate($1) }
        let groups = Dictionary(grouping: filtered) { entry -> DateComponents in
            calendar.dateComponents([.year, .month], from: sortDate(entry))
        }
        sections = groups
            .map { (comps, items) in
                TimelineSection(key: monthTitle(comps), entries: items)
            }
            .sorted { lhs, rhs in
                let left = lhs.entries.first.map(sortDate) ?? .distantPast
                let right = rhs.entries.first.map(sortDate) ?? .distantPast
                return sortMode.ascending ? left < right : left > right
            }
    }

    /// 搜索命中范围：正文 / 第一人称 / 标题 / 地点 / 作者 / 心情 / 「第一次」名称。
    private var matchingEntries: [Entry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicate = TimelineEntryQuery.descriptor(filters: filters, query: query, sort: sortMode, limit: pageLimit).predicate
        var result = entries.filter { entry in (try? predicate?.evaluate(entry)) == true }
        if remoteResultsAreCurrent {
            let scope = TimelineEntryQuery.descriptor(filters: filters, query: "", sort: sortMode, limit: 80).predicate
            let present = Set(result.map(\.id))
            result += remoteEntries.filter { !present.contains($0.id) && (try? scope?.evaluate($0)) == true }
        }
        return result
    }

    private func monthTitle(_ comps: DateComponents) -> String {
        guard let year = comps.year, let month = comps.month else { return "" }
        return "\(year)年\(month)月"
    }

    private func deletePendingEntry() {
        guard let entry = entryPendingDelete else { return }
        BubuHaptics.warning()
        entry.isArchived = true
        entry.editedAt = .now
        entry.syncState = .local
        context.insert(FeedEvent(kind: .entryArchived,
                                 actorRole: env.config.currentRole.rawValue,
                                 summary: "删除了一条时光轴记录",
                                 targetLocalId: entry.id.uuidString))
        try? context.save()
        // 删除后与 EntryDetailView.deleteEntry 一致：刷新小组件快照 + 推送墓碑同步，
        // 否则小组件仍显示已删记录、其它设备不知情。
        env.refreshWidgetSnapshot(context: context)
        env.syncEngine.syncNow()
        entryPendingDelete = nil
        rebuildSections()
        let deletedID = entry.id
        undoToast = BubuToastState(message: "已删除这条时光", systemImage: "trash",
                                   actionTitle: "撤销") { restoreEntry(deletedID) }
    }

    /// 撤销删除：isArchived 是软删字段（会随同步双向传播），置回 false 再推一次即可全家恢复。
    private func restoreEntry(_ id: UUID) {
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
        guard let entry = try? context.fetch(descriptor).first else { return }
        BubuHaptics.tapLight()
        entry.isArchived = false
        entry.editedAt = .now
        entry.syncState = .local
        context.insert(FeedEvent(kind: .entryCreated,
                                 actorRole: env.config.currentRole.rawValue,
                                 summary: "撤销了一条删除",
                                 targetLocalId: entry.id.uuidString))
        try? context.save()
        env.refreshWidgetSnapshot(context: context)
        env.syncEngine.syncNow()
        rebuildSections()
    }
}

/// Spotlight 可能打开 200 条分页窗口之外的旧记录；目标页按 id 单条查询，
/// 不为一次深链把整个时光轴扩成全量常驻。
struct TimelineEntryDestination: View {
    @Query private var entries: [Entry]

    init(entryID: UUID) {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate {
            $0.id == entryID && !$0.isArchived
        })
        descriptor.fetchLimit = 1
        _entries = Query(descriptor)
    }

    var body: some View {
        if let entry = entries.first {
            EntryDetailView(entry: entry)
        } else {
            ContentUnavailableView("这条时光暂时找不到", systemImage: "clock.badge.questionmark")
                .background(BubuTheme.Color.background.ignoresSafeArea())
        }
    }
}
