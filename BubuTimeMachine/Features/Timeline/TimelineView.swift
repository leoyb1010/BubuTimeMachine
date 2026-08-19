import SwiftUI
import SwiftData

// MARK: - 时光轴排序方式
/// 拍摄时间 = 事件真实发生的时刻（回顾成长）；记录时间 = 家人存进 App 的时刻（看最新动态）。
enum TimelineSortMode: String, CaseIterable {
    case capture   // 按拍摄/发生时间
    case recorded  // 按记录时间

    var title: String {
        switch self {
        case .capture: return "按拍摄时间"
        case .recorded: return "按记录时间"
        }
    }
}

// MARK: - 时光轴
/// @Query 按 happenedAt 倒序读取本地 Entry，按「年-月」分段展示；
/// 分段在 rebuildSections 内存重排，排序方式可切（拍摄时间/记录时间），偏好持久记忆。
/// 离线优先：UI 只读本地 SwiftData，断网全功能可用。
struct TimelineView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<Entry> { !$0.isArchived },
        sort: \Entry.happenedAt,
        order: .reverse
    )
    private var entries: [Entry]
    @Query private var profiles: [ChildProfile]
    @State private var showFamilyFeed = false
    @State private var entryPendingDelete: Entry?
    /// 长按「分享这一刻」选中的记录。
    @State private var entryPendingShare: Entry?
    @State private var sections: [TimelineSection] = []
    @State private var searchText = Self.semanticVisualProbe ? "扶着沙发学走路" : ""
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
            enabled: (env.config.semanticSearchEnabled && env.config.isAIConfigured) || Self.semanticVisualProbe,
            serviceRevision: env.aiServiceRevision,
            entriesRevision: entriesRevision
        )
        #if DEBUG
        let _ = Self.logSlowKey(CFAbsoluteTimeGetCurrent() - bodyT0, entries: entries.count)
        #endif
        ZStack {
            BubuTheme.Color.background.ignoresSafeArea()

            if entries.isEmpty {
                emptyState
            } else if sections.isEmpty {
                searchEmptyState
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
                    prompt: env.config.semanticSearchEnabled
                    ? "找文字或照片里的画面" : "找找\(profiles.first?.name ?? "布布")的记录")
        // 本地文字结果立即出现；停顿 300ms 后再请求家中语义索引。请求失败不影响离线结果。
        .task(id: semanticTaskKey) { await updateSearch(semanticTaskKey) }
        .onAppear { rebuildSectionsIfNeeded(); refreshUnseenBadge() }
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
        .toolbar {
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
            }
            .padding()
        }
        .navigationDestination(for: UUID.self) { entryID in
            if let entry = entries.first(where: { $0.id == entryID }) {
                EntryDetailView(entry: entry)
                    .navigationTransition(.zoom(sourceID: entryID, in: zoomNS))
            } else {
                ContentUnavailableView("这条时光暂时找不到", systemImage: "clock.badge.questionmark")
                    .background(BubuTheme.Color.background.ignoresSafeArea())
            }
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
        }
    }

    // 大图卡片：顶部 hue 占位/真实图（带日期标）+ 标题正文 + tag 行
    private func bigPhotoCard(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let media = cardMedia(entry) {
                        MediaThumbnail(media: media, mediaStore: env.mediaStore)
                    } else {
                        BubuDreamPhoto(hue: entry.id.bubuStableHue, height: 178,
                                       cornerRadius: 0, motif: entry.mood?.emoji ?? "◡")
                    }
                }
                // 封面按照片自己的长宽比排版（夹在 4:5 ~ 1.9:1 之间）：
                // 原来固定 178 高，竖图会被裁成中间一条窄带，看不出拍了什么。
                // 宽屏把最小比例收紧到 1.5（而不是加 maxHeight——那会让封面按比例缩小、两侧留灰边）：
                // 高度 = 宽 / 比例，天然受控，同时始终填满卡片宽度。
                .aspectRatio(coverAspect(cardMedia(entry)), contentMode: .fit)
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
                if let hit = semanticMatches[entry.id] {
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
        }
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        .bubuCardShadow()
    }

    /// 卡片标题：有标题用标题，没标题就把正文顶上来，都没有才是「记录此刻」。
    private func cardHeadline(_ entry: Entry) -> String {
        if let title = entry.title, !title.isEmpty { return title }
        if let note = entry.note, !note.isEmpty { return note }
        return "记录此刻"
    }

    /// 卡片副文案：只有当它和标题不是同一句话时才显示，避免同屏上下两行重复。
    private func cardSubtitle(_ entry: Entry) -> String? {
        guard let note = entry.note, !note.isEmpty else { return nil }
        guard let title = entry.title, !title.isEmpty else { return nil }   // 无标题时正文已当标题
        return note == title ? nil : note
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
                    .foregroundStyle(env.theme.theme.primary)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(env.theme.theme.primary.opacity(0.10), in: Capsule())
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.background.opacity(0.95))
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            BubuEmptyIllustration(assetName: "BubuEmptyTimeline", fallbackExpression: .bye)
            Text(BubuTheme.Copy.emptyTimeline)
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 16) {
            BubuMascotBadge(size: 72, expression: .surprised)
            if semanticSearchState == .searching {
                ProgressView("正在理解照片画面…")
                    .font(BubuTheme.Font.body)
            } else {
                Text("没找到「\(searchText)」相关的记录")
                    .font(BubuTheme.Font.body)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .multilineTextAlignment(.center)
            }
            if semanticSearchState == .offlineFallback {
                Label("语义服务暂时不可用，已完成本地文字搜索", systemImage: "wifi.slash")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            if semanticSearchState == .active {
                Text("照片画面和文字都找过了，换个说法再试试")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
        .padding(40)
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
        ((env.config.semanticSearchEnabled && env.config.isAIConfigured) || Self.semanticVisualProbe)
    }

    private static var semanticVisualProbe: Bool {
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
        HStack(spacing: 8) {
            switch semanticSearchState {
            case .searching:
                ProgressView().controlSize(.small)
                Text("正在理解照片画面…")
            case .active:
                Image(systemName: "sparkle.magnifyingglass")
                Text("已同时搜索照片画面与文字")
            case .offlineFallback:
                Image(systemName: "wifi.slash")
                Text("语义服务暂时不可用，已用本地文字搜索")
            case .idle:
                EmptyView()
            }
            Spacer(minLength: 0)
        }
        .font(BubuTheme.Font.caption.weight(.semibold))
        .foregroundStyle(BubuTheme.Color.secondaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(BubuTheme.Color.card.opacity(0.78), in: Capsule())
        .accessibilityElement(children: .combine)
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

    private func rebuildSectionsIfNeeded() {
        if sections.isEmpty { rebuildSections() }
    }

    private func updateSearch(_ key: SemanticSearchTaskKey) async {
        semanticMatches = [:]
        semanticSearchState = .idle
        // 本地匹配永远先完成，断网或未开启语义能力时搜索体验不变。
        rebuildSections()

        let query = key.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, key.enabled else { return }
#if DEBUG
        if Self.semanticVisualProbe, let entry = entries.first {
            semanticMatches = [entry.id: SemanticSearchHit(
                assetId: "visual-probe",
                entryLocalId: entry.id.uuidString,
                mediaRecordId: "visual-probe",
                capturedAt: ISO8601DateFormatter().string(from: entry.happenedAt),
                score: 0.93,
                reason: "画面语义接近“扶着沙发学走路”"
            )]
            semanticSearchState = .active
            rebuildSections()
            return
        }
#endif
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        semanticSearchState = .searching
        do {
            let response = try await env.aiService.semanticSearch(query: query, limit: 30)
            guard !Task.isCancelled, response.query == query else { return }
            semanticMatches = TimelineSemanticSearchResolver.bestHits(
                response.hits,
                availableEntryIDs: Set(entries.map(\.id))
            )
            semanticSearchState = .active
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, searchText == key.query,
                  env.aiServiceRevision == key.serviceRevision else { return }
            semanticMatches = [:]
            semanticSearchState = .offlineFallback
        }
        rebuildSections()
    }

    private func cardMedia(_ entry: Entry) -> Media? {
        guard let recordID = semanticMatches[entry.id]?.mediaRecordId else { return entry.coverMedia }
        // 不在 ?? autoclosure 里捕获 SwiftData 模型；Release whole-module 会按严格并发拒绝。
        let matched = entry.sortedMedia.first(where: { $0.remoteId == recordID })
        let fallback = entry.coverMedia
        return matched ?? fallback
    }

    private func semanticReason(entry: Entry, hit: SemanticSearchHit) -> String {
        let matchedMedia = entry.sortedMedia.first(where: { $0.remoteId == hit.mediaRecordId })
        let clean = hit.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "画面语义接近", with: "画面接近")
        if matchedMedia == nil, entry.coverMedia != nil {
            return "这条记录中的另一张照片：" + clean
        }
        return clean
    }

    private var sortMode: TimelineSortMode { TimelineSortMode(rawValue: sortModeRaw) ?? .capture }

    /// 当前排序方式下条目的排序/分组键。
    private func sortDate(_ entry: Entry) -> Date {
        sortMode == .capture ? entry.happenedAt : entry.createdAt
    }

    /// 重新分组：仅在 entries / 搜索词 / 排序方式变化时调用，避免每次 body 求值 O(n) 重分组。
    /// @Query 固定按 happenedAt 倒序取数；按记录时间浏览时在这里内存重排（个人家庭库量级无压力）。
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
        let filtered = matchingEntries.sorted { sortDate($0) > sortDate($1) }
        let groups = Dictionary(grouping: filtered) { entry -> DateComponents in
            calendar.dateComponents([.year, .month], from: sortDate(entry))
        }
        sections = groups
            .map { (comps, items) in
                TimelineSection(key: monthTitle(comps), entries: items)
            }
            .sorted { lhs, rhs in
                (lhs.entries.first.map(sortDate) ?? .distantPast) >
                (rhs.entries.first.map(sortDate) ?? .distantPast)
            }
    }

    /// 搜索命中范围：正文 / 第一人称 / 标题 / 地点 / 作者 / 心情 / 「第一次」名称。
    private var matchingEntries: [Entry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        let lower = q.lowercased()
        return entries.filter { e in
            func hit(_ s: String?) -> Bool { s?.lowercased().contains(lower) ?? false }
            return semanticMatches[e.id] != nil || hit(e.note) || hit(e.firstPersonNote) || hit(e.title)
                || hit(e.locationName) || hit(e.authorRole)
                || hit(e.mood?.rawValue) || hit(e.firstTime?.what)
        }
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
    }
}
