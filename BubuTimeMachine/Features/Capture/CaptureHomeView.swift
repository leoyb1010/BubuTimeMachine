import SwiftUI
import SwiftData
import PhotosUI

// MARK: - 首页 · 成长仪表盘
/// 专属布布的主屏：年龄实时计数 + 那年今日 + 统计 + 精选 + 大记录按钮。
/// 背景可用主题渐变或布布的照片。
struct CaptureHomeView: View {
    var openTimeline: (() -> Void)?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt, order: .reverse)
    private var entries: [Entry]
    @Query private var milestones: [Milestone]
    @Query(sort: \GrowthMeasurement.measuredAt, order: .reverse)
    private var measurements: [GrowthMeasurement]

    @State private var model: CaptureModel?
    @State private var firstTimeSuggestion: String?
    @State private var firstTimeEntryID: UUID?

    /// 缩略图 → 详情页的 iOS 18+ 缩放共享元素转场（与 TimelineView 同一套做法）。
    @Namespace private var zoomNS

    private var profile: ChildProfile? { profiles.first }
    private var theme: BubuThemeDefinition { env.theme.theme }
    private var homeSurface: Color {
        env.themedCard.opacity(env.isDarkTheme ? 0.88 : 0.94)
    }

    var body: some View {
        ZStack {
            heroBackground.ignoresSafeArea()

            ScrollView {
                // 布局原则：主操作「记录此刻」必须首屏完整露出——紧跟输入条；
                // 同步状态条属于次要信息，下移到统计行之后；行距 14 紧凑但不拥挤。
                // 严格照搬设计稿 MacHome 的卡片拼贴节奏：
                // 问候 → Hero 相遇卡 → 双卡①(星座+身高体重) → 布布故事横幅 → 双卡②(相册+记录) → 最近时光。
                // 现有功能(健康/今日一问/那年今日/同步)作为下方延伸区保留，不删任何入口。
                VStack(spacing: 14) {
                    greetingRow
                    identityCardTop            // ① 布布身份卡（可翻面看性别/血型/出生地）
                    dashboardGridTop           // ② 双卡：成长星座迷你 ‖ 身高体重 bar
                    storyBanner                // ③ 布布的故事 butter→peach 横幅
                    dashboardGridBottom        // ④ 双卡：相册叠放 ‖ 记录此刻虚线
                    recentMomentsSection       // ⑤ 最近时光（行卡）
                    NaturalCaptureBar()        // —— 以下为现有功能延伸区，全部保留 ——
                    onThisDaySection
                    healthEntryCard
                    dailyQuestionCard
                    saveHealthStrip
                    // 给底部悬浮玻璃 Tab 栏留出空间
                    Spacer(minLength: 110)
                }
                .padding()
            }
            // 详情页转场移到此处（而非 RootTabView），以便与本页 zoomNS 配对实现缩放共享元素转场。
            .navigationDestination(for: Entry.self) { entry in
                EntryDetailView(entry: entry)
                    .navigationTransition(.zoom(sourceID: entry.id, in: zoomNS))
            }

            if let model {
                Color.clear
                    .sheet(isPresented: Binding(get: { model.showQuickCapture },
                                                set: { model.showQuickCapture = $0 })) {
                        QuickCaptureSheet(model: model)
                    }
                if model.savedFlash { savedToast }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // 保存成功时的成功触觉，与「已经收好啦」贴纸同步，强化「完成感」。
        .sensoryFeedback(.success, trigger: model?.savedFlash)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("设置")
                    .bubuGlassButton()
            }
        }
        .onAppear {
            if model == nil {
                model = CaptureModel(mediaStore: env.mediaStore, analyzer: env.photoAnalyzer,
                                     role: env.config.currentRole)
            }
        }
        .onChange(of: model?.lastSavedEntryID) { _, newID in
            if let id = newID {
                Task { await detectFirstTime(entryID: id) }
            }
        }
        .alert("这是布布的第一次吗？", isPresented: Binding(
            get: { firstTimeSuggestion != nil },
            set: { if !$0 { firstTimeSuggestion = nil } })) {
            Button("是的，记一笔") { confirmFirstTime() }
            Button("不是", role: .cancel) { firstTimeSuggestion = nil }
        } message: {
            Text(firstTimeSuggestion ?? "")
        }
    }

    /// 保存后调用 AI 识别"第一次"（仅在启用真实 AI 时）。
    private func detectFirstTime(entryID: UUID) async {
        guard env.config.isAIConfigured else { return }
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryID })
        guard let entry = try? modelContext.fetch(descriptor).first,
              !entry.media.isEmpty else { return }
        if let suggestion = try? await env.aiService.detectFirstTime(media: entry.media),
           suggestion.confidence > 0.4 {
            firstTimeEntryID = entryID
            firstTimeSuggestion = suggestion.what
        }
    }

    private func confirmFirstTime() {
        guard let what = firstTimeSuggestion, let id = firstTimeEntryID else { return }
        let ft = FirstTime(what: what)
        ft.detectedByAI = true
        ft.confirmedByParent = true
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
        if let entry = try? modelContext.fetch(descriptor).first {
            ft.entry = entry
            ft.happenedAt = entry.happenedAt
        }
        modelContext.insert(ft)
        modelContext.insert(FeedEvent(kind: .firstTimeConfirmed, actorRole: env.config.currentRole.rawValue,
                                      summary: "确认了「\(what)」",
                                      targetLocalId: id.uuidString))
        try? modelContext.save()
        firstTimeSuggestion = nil
    }

    // MARK: 背景

    @ViewBuilder
    private var heroBackground: some View {
        ZStack {
            BubuThemedBackground()

            if env.theme.heroMode == .photo,
               let name = profile?.heroBackgroundFileName,
               let data = env.mediaStore.data(forMedia: name),
               let ui = UIImage(data: data) {
                // 首页和其它页面保持同一主题底色；照片只做低透明度质感，避免文字压在照片高亮处。
                Color.clear
                    .overlay {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                    }
                    .opacity(env.isDarkTheme ? 0.10 : 0.14)
                    .saturation(0.75)
                    .clipped()
            }

            LinearGradient(colors: [
                BubuTheme.Color.background.opacity(env.isDarkTheme ? 0.20 : 0.34),
                .clear,
                BubuTheme.Color.background.opacity(env.isDarkTheme ? 0.36 : 0.58)
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
        }
    }

    // MARK: 年龄头部（布布个人身份卡）

    @ViewBuilder
    // 顶部问候行（纯展示，对照设计稿「☀︎ 早安呀 + 名字 + 年龄」）
    private var greetingRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(greetingText) 呀")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                if let profile {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(profile.name)
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text(AgeCalculator.ageDescription(birthday: profile.birthday, at: .now))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.primary)
                    }
                }
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var greetingText: String {
        let h = Calendar.current.component(.hour, from: .now)
        switch h {
        case 5..<11: return "☀︎ 早安"
        case 11..<14: return "🍚 中午好"
        case 14..<18: return "🌤 下午好"
        case 18..<23: return "🌙 晚上好"
        default: return "💤 夜深了"
        }
    }

    // MARK: 布布身份卡（顶部主卡，可翻面看性别/血型/出生地——用户指定保留）

    @ViewBuilder
    private var identityCardTop: some View {
        if let profile {
            BubuIdentityCard(profile: profile, theme: theme, mediaStore: env.mediaStore)
        } else {
            // 无档案：引导建档（保证空态也好看，不留空白）
            NavigationLink { ChildProfileView() } label: {
                HStack(spacing: 14) {
                    BubuMascotBadge(size: 56, expression: .happy)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("建立布布的档案")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text("填上生日，就能看到「相遇第几天」啦 ♡")
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(BubuTheme.Gradient.hero, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .bubuCardShadow()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 双卡① — 成长星座迷你 ‖ 身高体重 bar（对照设计稿 MacHome 第一组双卡）

    private var litMilestoneCount: Int { milestones.filter(\.isAchieved).count }
    private var latestHeight: Double? { measurements.compactMap(\.heightCm).first }
    private var latestWeight: Double? { measurements.compactMap(\.weightKg).first }

    private var dashboardGridTop: some View {
        HStack(spacing: 12) {
            // 成长星座入口卡（迷你星座预览）
            NavigationLink { MilestonesHomeView() } label: {
                VStack(alignment: .leading, spacing: 8) {
                    BubuMiniConstellation(done: max(1, litMilestoneCount))
                    Text("成长星座")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("已点亮 \(litMilestoneCount) / \(milestones.count) 颗星")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .bubuMacaronCard(padding: 16)
            }
            .buttonStyle(.plain)

            // 身高体重卡（→ 成长数据）
            NavigationLink { HealthHomeView() } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        growthStat(title: "身高", value: latestHeight, unit: "cm")
                        growthStat(title: "体重", value: latestWeight, unit: "kg")
                    }
                    growthBars
                        .padding(.top, 10)
                    Text("记录布布的长大 ↗")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .bubuMacaronCard(padding: 16)
            }
            .buttonStyle(.plain)
        }
    }

    private func growthStat(title: String, value: Double?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(BubuTheme.Color.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value.map { String(format: $0 == $0.rounded() ? "%.0f" : "%.1f", $0) } ?? "—")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(unit).font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 设计稿那组渐升 bar（装饰；末柱用主色）
    private var growthBars: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array([40, 55, 62, 70, 76, 88, 100].enumerated()), id: \.offset) { i, h in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(i == 6 ? BubuTheme.Color.primary : BubuTheme.Color.peach)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38 * CGFloat(h) / 100)
            }
        }
        .frame(height: 38)
    }

    // MARK: 布布的故事横幅（butter→peach，对照设计稿 MacHome 故事卡）

    private var storyBanner: some View {
        NavigationLink { BubuStoryView() } label: {
            HStack(spacing: 14) {
                // 倾斜书卡
                BubuDreamPhoto(hue: 18, height: 84, cornerRadius: 14, motif: "✦")
                    .frame(width: 70)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white, lineWidth: 3))
                    .rotationEffect(.degrees(-4))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text("布布的故事 · 成长绘本")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.deepRose)
                    Text(storyHeadline)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .lineLimit(1)
                    Text("由你记录的点滴，自动编织成故事")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.54, green: 0.42, blue: 0.33))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(BubuTheme.Color.deepRose)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [BubuTheme.Color.butter, BubuTheme.Color.peach],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .bubuCardShadow()
        }
        .buttonStyle(.plain)
    }

    private var storyHeadline: String {
        let n = milestones.filter { $0.isAchieved && ($0.detail?.isEmpty == false) }.count
        return n > 0 ? "已写到第 \(min(n, 99)) 篇" : "翻开第一页"
    }

    // MARK: 双卡② — 相册叠放 ‖ 记录此刻虚线（对照设计稿 MacHome 第二组双卡）

    private var dashboardGridBottom: some View {
        HStack(spacing: 12) {
            // 相册卡（多图）
            NavigationLink { AlbumHomeView() } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        BubuDreamPhoto(hue: 150, height: 56, cornerRadius: 12, motif: "✿")
                        VStack(spacing: 6) {
                            BubuDreamPhoto(hue: 335, height: 25, cornerRadius: 9, motif: "")
                            BubuDreamPhoto(hue: 200, height: 25, cornerRadius: 9, motif: "")
                        }
                    }
                    Text("相册 · \(totalPhotos) 张")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("\(entries.count) 个瞬间")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .bubuMacaronCard(padding: 14)
            }
            .buttonStyle(.plain)

            // 记录此刻虚线卡
            Button { model?.startQuickCapture() } label: {
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(BubuTheme.Color.cream2).frame(width: 46, height: 46)
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(BubuTheme.Color.deepRose)
                    }
                    Text("记录此刻")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("留住今天的布布")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 130)
                .background(
                    LinearGradient(colors: [BubuTheme.Color.card, BubuTheme.Color.cream2],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
                        .strokeBorder(BubuTheme.Color.peach, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 最近时光（行卡，对照设计稿 MacMomentRow）

    @ViewBuilder
    private var recentMomentsSection: some View {
        if !entries.isEmpty {
            VStack(spacing: 10) {
                HStack {
                    Text("最近时光")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Spacer()
                    Button { openTimeline?() } label: {
                        Text("查看全部 ›")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.primary)
                    }
                }
                ForEach(entries.prefix(2)) { entry in
                    NavigationLink(value: entry) { momentRow(entry) }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: entry.id, in: zoomNS)
                }
            }
        }
    }

    private func momentRow(_ entry: Entry) -> some View {
        HStack(spacing: 12) {
            Group {
                if let media = entry.media.first {
                    MediaThumbnail(media: media, mediaStore: env.mediaStore)
                } else {
                    BubuDreamPhoto(hue: Double(abs(entry.id.hashValue) % 360), height: 64,
                                   cornerRadius: 16, motif: entry.mood?.emoji ?? "◡")
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(BubuDateFormat.monthDay(entry.happenedAt))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.primary)
                Text(entry.note?.isEmpty == false ? entry.note! : "记录此刻")
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineLimit(1)
                if let mood = entry.mood {
                    Text("\(mood.emoji) \(mood.rawValue)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .bubuCardShadow()
    }

    // MARK: 保存健康度

    private var saveHealthStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: env.syncEngine.pendingCount == 0 ? "checkmark.icloud.fill" : "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(env.syncEngine.pendingCount == 0 ? BubuTheme.Color.success : theme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("本地已保存")
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text(syncSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                Spacer()
                NavigationLink { SettingsView() } label: {
                    Text("查看")
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(theme.primary)
                }
            }

            if let progress = env.syncEngine.syncProgress,
               env.syncEngine.pendingCount > 0 || env.syncEngine.connectionState == .connecting {
                ProgressView(value: progress)
                    .tint(theme.primary)
                if let label = env.syncEngine.currentSyncLabel {
                    Text(label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            if let notice = env.syncEngine.lastLargeFileNotice {
                Text(notice)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(theme.primary)
            } else if let soft = env.syncEngine.softNotice {
                Text(soft)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            } else if let failure = env.syncEngine.lastFailureReason,
                      env.syncEngine.pendingCount > 0 {
                Text(failure)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.danger)
            }
        }
        .padding(12)
        .background(homeSurface, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
        .bubuGlassSurface(cornerRadius: BubuTheme.Radius.small, tint: theme.primary)
    }

    private var syncSummary: String {
        switch env.syncEngine.connectionState {
        case .offline:
            return env.syncEngine.pendingCount == 0 ? "离线也可用，暂无待同步" : "离线可用，\(env.syncEngine.pendingCount) 项等服务器"
        case .connecting:
            return "正在连接家里的服务器…"
        case .online:
            return env.syncEngine.pendingCount == 0 ? "已和家里服务器同步" : "\(env.syncEngine.pendingCount) 项正在等待同步"
        }
    }

    private var totalPhotos: Int {
        entries.reduce(0) { total, entry in
            total + entry.media.filter { $0.type == .photo }.count
        }
    }

    // MARK: 那年今日

    @ViewBuilder
    private var onThisDaySection: some View {
        let memories = onThisDayEntries
        if !memories.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink { OnThisDayView() } label: {
                    HStack(spacing: 6) {
                        Label("那年今日", systemImage: "calendar.badge.clock")
                            .font(BubuTheme.Font.headline)
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(memories) { entry in
                            NavigationLink(value: entry) {
                                onThisDayCard(entry)
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: entry.id, in: zoomNS)
                        }
                    }
                }
            }
            .padding()
            .background(homeSurface, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        }
    }

    private func onThisDayCard(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let media = entry.media.first {
                MediaThumbnail(media: media, mediaStore: env.mediaStore)
                    .frame(width: 130, height: 130)
            } else {
                RoundedRectangle(cornerRadius: BubuTheme.Radius.small)
                    .fill(theme.primary.opacity(0.12))
                    .frame(width: 130, height: 130)
                    .overlay { Text(entry.mood?.emoji ?? "📝").font(.system(size: 40)) }
            }
            if let profile {
                Text(AgeCalculator.compactAge(birthday: profile.birthday, at: entry.happenedAt))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primary)
            }
            Text(yearsAgoText(entry.happenedAt))
                .font(.system(size: 11)).foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .frame(width: 130)
    }

    /// 历史上的今天（同月同日，往年）。
    private var onThisDayEntries: [Entry] {
        let cal = Calendar.current
        let today = cal.dateComponents([.month, .day], from: .now)
        return entries.filter { entry in
            let c = cal.dateComponents([.month, .day], from: entry.happenedAt)
            let isPast = !cal.isDate(entry.happenedAt, inSameDayAs: .now)
            return c.month == today.month && c.day == today.day && isPast
        }
    }

    private func yearsAgoText(_ date: Date) -> String {
        let years = Calendar.current.dateComponents([.year], from: date, to: .now).year ?? 0
        return years <= 0 ? "今年" : "\(years)年前的今天"
    }

    // MARK: 每日一问

    private var dailyQuestionCard: some View {
        let question = DailyQuestion.todays(birthday: profile?.birthday ?? .now)
        return Button {
            model?.startQuickCapture(prefillNote: "【今日一问】\(question)\n")
        } label: {
            HStack(spacing: 14) {
                BubuMascotBadge(size: 46, expression: .surprised)
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日一问")
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(theme.primary)
                    Text(question)
                        .font(BubuTheme.Font.body.weight(.medium))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text("答一句")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(theme.primary, in: Capsule())
            }
            .padding()
            .background(homeSurface, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .bubuGlassSurface(cornerRadius: BubuTheme.Radius.card, tint: theme.primary, interactive: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: 布布健康入口

    private var healthEntryCard: some View {
        NavigationLink {
            HealthHomeView()
        } label: {
            HStack(spacing: 14) {
                BubuMascotBadge(size: 48, expression: .eating)
                VStack(alignment: .leading, spacing: 4) {
                    Text("布布健康")
                        .font(BubuTheme.Font.headline)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("餐食、零食、营养补充、睡眠和不舒服都记在这里")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .padding()
            .background(homeSurface, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .bubuGlassSurface(cornerRadius: BubuTheme.Radius.card, tint: theme.primary, interactive: true)
        }
        .buttonStyle(.plain)
    }

    /// 保存成功：布布「耶」贴纸弹入 + 成功触觉（haptic 在 CaptureModel.flashSaved 触发）。
    private var savedToast: some View {
        VStack {
            HStack(spacing: 10) {
                BubuMascotBadge(size: 44, expression: .yeah)
                Text("已经收好啦")
                    .font(BubuTheme.Font.body.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(BubuTheme.Color.success, in: Capsule())
            .bubuCardShadow()
            Spacer()
        }
        .padding(.top, 8)
        .transition(.scale(scale: 0.5, anchor: .top).combined(with: .opacity))
    }
}

