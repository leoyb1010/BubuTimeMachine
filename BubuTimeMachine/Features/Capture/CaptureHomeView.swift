import SwiftUI
import SwiftData
import PhotosUI
import UIKit

// MARK: - 首页 · 成长仪表盘
/// 专属布布的主屏：年龄实时计数 + 那年今日 + 统计 + 精选 + 大记录按钮。
/// 背景可用主题渐变或布布的照片。
struct CaptureHomeView: View {
    var openTimeline: (() -> Void)?
    var quickCaptureTrigger: Int = 0

    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var profiles: [ChildProfile]
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt, order: .reverse)
    private var entries: [Entry]
    @Query private var milestones: [Milestone]
    @Query(sort: \GrowthMeasurement.measuredAt, order: .reverse)
    private var measurements: [GrowthMeasurement]
    @Query(sort: \HealthRecord.recordedAt, order: .reverse)
    private var healthRecords: [HealthRecord]

    @State private var model: CaptureModel?
    @State private var firstTimeSuggestion: String?
    @State private var firstTimeEntryID: UUID?
    @State private var photoScanner = PhotoLibraryScanner()
    @State private var showTodayPhotos = false
    @State private var showNaturalCapture = false
    @State private var naturalCaptureButtonOffset: CGSize = .zero
    @State private var heroBackgroundImage: UIImage?
    @GestureState private var naturalCaptureButtonDrag: CGSize = .zero

    /// 缩略图 → 详情页的 iOS 18+ 缩放共享元素转场（与 TimelineView 同一套做法）。
    @Namespace private var zoomNS

    private var profile: ChildProfile? { profiles.first }
    private var theme: BubuThemeDefinition { env.theme.theme }
    private var homeSurface: Color {
        env.themedCard.opacity(colorScheme == .dark || env.isDarkTheme ? 0.92 : 0.94)
    }
    private var heroBackgroundKey: String {
        "\(env.theme.heroMode.rawValue)|\(profile?.heroBackgroundFileName ?? "")|\(theme.id)"
    }

    var body: some View {
        ZStack {
            heroBackground.ignoresSafeArea()

            ScrollView {
                // 布局原则：主操作「记录此刻」必须首屏完整露出——紧跟输入条；
                // 同步状态条属于次要信息，下移到统计行之后；行距 14 紧凑但不拥挤。
                // 参考马卡龙视觉稿，但按真实 App 首屏重排：
                // 问候 → 身份卡 → 主操作 → 紧凑四宫格 → 最近时光/延伸能力。
                VStack(spacing: 12) {
                    greetingRow
                    identityCardTop            // ① 布布身份卡（可翻面看性别/血型/出生地）
                    todayPhotosCard            // 今天拍了照片时主动请你收进（零操作记录）
                    primaryActionDock          // ② 记录/相册/健康：首屏主动作更明确
                    dashboardGridTop           // ③ 紧凑四宫格：星座/成长/故事/健康
                    recentMomentsSection       // ⑤ 最近时光（行卡）
                    onThisDaySection
                    saveHealthStrip
                    // 给底部悬浮玻璃 Tab 栏留出空间
                    Spacer(minLength: 150)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            // 详情页转场移到此处（而非 RootTabView），以便与本页 zoomNS 配对实现缩放共享元素转场。
            .navigationDestination(for: UUID.self) { entryID in
                if let entry = entries.first(where: { $0.id == entryID }) {
                    EntryDetailView(entry: entry)
                        .navigationTransition(.zoom(sourceID: entryID, in: zoomNS))
                } else {
                    ContentUnavailableView("这条时光暂时找不到", systemImage: "clock.badge.questionmark")
                        .background(BubuTheme.Color.background.ignoresSafeArea())
                }
            }

            if let model {
                Color.clear
                    .sheet(isPresented: Binding(get: { model.showQuickCapture },
                                                set: { model.showQuickCapture = $0 })) {
                        QuickCaptureSheet(model: model)
                    }
                if model.savedFlash { savedToast }
            }

            naturalCaptureFloatingButton
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // 保存成功时的成功触觉，与「已经收好啦」贴纸同步，强化「完成感」。
        .sensoryFeedback(.success, trigger: model?.savedFlash)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if model == nil {
                model = CaptureModel(mediaStore: env.mediaStore, analyzer: env.photoAnalyzer,
                                     role: env.config.currentRole)
            }
            // 已授权过相册就顺手扫一下今天的照片（不主动弹权限）
            photoScanner.refreshAuthorizationState()
            if photoScanner.authorized { _ = photoScanner.scan() }
        }
        .onChange(of: quickCaptureTrigger) { _, _ in
            startQuickCapture()
        }
        .onChange(of: model?.lastSavedEntryID) { _, newID in
            if let id = newID {
                Task { await detectFirstTime(entryID: id) }
            }
        }
        .task(id: heroBackgroundKey) {
            await refreshHeroBackgroundImage()
        }
        .alert("这是布布的第一次吗？", isPresented: Binding(
            get: { firstTimeSuggestion != nil },
            set: { if !$0 { firstTimeSuggestion = nil } })) {
            Button("是的，记一笔") { confirmFirstTime() }
            Button("不是", role: .cancel) { firstTimeSuggestion = nil }
        } message: {
            Text(firstTimeSuggestion ?? "")
        }
        .sheet(isPresented: $showNaturalCapture) {
            NaturalCapturePanel()
        }
        .sheet(isPresented: $showTodayPhotos) {
            TodayPhotosSheet(assets: photoScanner.todayAssets) { handled in
                photoScanner.markHandled(handled)
            }
        }
    }

    // MARK: 今天拍的照片卡（零操作记录）
    @ViewBuilder
    private var todayPhotosCard: some View {
        if photoScanner.authorized, !photoScanner.todayAssets.isEmpty {
            Button {
                showTodayPhotos = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(BubuTheme.Color.primary.opacity(0.16)).frame(width: 44, height: 44)
                        Image(systemName: "photo.badge.plus.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(BubuTheme.Color.primary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今天拍了 \(photoScanner.todayAssets.count) 个瞬间")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text("挑几张收进布布的时光轴？")
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BubuTheme.Color.primary)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(homeSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .bubuCardShadow()
            }
            .buttonStyle(.plain)
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

    private func startQuickCapture(prefillNote: String = "") {
        if model == nil {
            model = CaptureModel(mediaStore: env.mediaStore, analyzer: env.photoAnalyzer,
                                 role: env.config.currentRole)
        }
        model?.role = env.config.currentRole   // 身份可能在设置里换过：署名跟随当前身份
        model?.startQuickCapture(prefillNote: prefillNote)
    }

    // MARK: 背景

    @ViewBuilder
    private var heroBackground: some View {
        ZStack {
            themeBackgroundLayer

            if env.theme.heroMode == .photo, let heroBackgroundImage {
                Image(uiImage: heroBackgroundImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay {
                        LinearGradient(colors: [
                            Color.black.opacity(colorScheme == .dark ? 0.36 : 0.12),
                            theme.primary.opacity(colorScheme == .dark ? 0.28 : 0.16),
                            BubuTheme.Color.background.opacity(colorScheme == .dark ? 0.78 : 0.62),
                        ], startPoint: .top, endPoint: .bottom)
                    }
            }

            BubuBlobBackground(tint: theme.primary, includeBase: false)
                .opacity(env.theme.heroMode == .photo ? 0.18 : 0.34)

            LinearGradient(colors: [
                BubuTheme.Color.background.opacity(0.28),
                .clear,
                BubuTheme.Color.background.opacity(0.62)
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var themeBackgroundLayer: some View {
        if colorScheme == .dark || theme.isDark {
            BubuTheme.Color.background
        } else {
            switch theme.backgroundStyle {
            case .solid(let hex):
                Color(hex: hex)
            case .gradient(let a, let b):
                LinearGradient(colors: [Color(hex: a), Color(hex: b), BubuTheme.Color.background],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    @MainActor
    private func refreshHeroBackgroundImage() async {
        guard env.theme.heroMode == .photo,
              let fileName = profile?.heroBackgroundFileName else {
            heroBackgroundImage = nil
            return
        }
        let url = env.mediaStore.mediaURL(for: fileName)
        heroBackgroundImage = await Task.detached(priority: .utility) {
            ThumbnailProvider.downsample(url: url, maxPixel: 1800)
        }.value
    }

    // MARK: 年龄头部（布布个人身份卡）

    @ViewBuilder
    // 顶部问候行（纯展示，对照设计稿「☀︎ 早安呀 + 名字 + 年龄」）
    private var greetingRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
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
            todayStatusPill
            NavigationLink { SettingsView() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(BubuTheme.Color.primary)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.62), lineWidth: 1))
                    .shadow(color: BubuTheme.Color.deepRose.opacity(0.18), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
        }
        .padding(.top, 2)
    }

    private var todayStatusPill: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .bold))
                Text(todayText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            HStack(spacing: 5) {
                Image(systemName: weatherSymbol)
                    .font(.system(size: 11, weight: .bold))
                Text(weatherMoodText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(BubuTheme.Color.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.52), lineWidth: 1)
        }
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

    private var todayText: String {
        let c = Calendar.current.dateComponents([.month, .day, .weekday], from: .now)
        let weekday = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"][c.weekday ?? 0]
        return "\(c.month ?? 1)月\(c.day ?? 1)日 \(weekday)"
    }

    private var weatherSymbol: String {
        let h = Calendar.current.component(.hour, from: .now)
        switch h {
        case 6..<18: return "cloud.sun.fill"
        case 18..<23: return "moon.stars.fill"
        default: return "sparkles"
        }
    }

    private var weatherMoodText: String {
        let h = Calendar.current.component(.hour, from: .now)
        switch h {
        case 6..<12: return "晨光好"
        case 12..<18: return "适合记录"
        case 18..<23: return "晚风轻"
        default: return "安静时刻"
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

    // MARK: 首屏主操作 — 记录 / 相册 / 健康

    private var primaryActionDock: some View {
        HStack(spacing: 10) {
            Button { startQuickCapture() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(BubuTheme.Gradient.primaryButton, in: Circle())
                        .shadow(color: BubuTheme.Color.deepRose.opacity(0.35), radius: 8, y: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("记录此刻")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text("照片、语音、文字一起收好")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 10)
                .frame(height: 64)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.58), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .layoutPriority(1)

            NavigationLink { AlbumHomeView() } label: {
                quickDockButton(icon: "photo.on.rectangle.angled.fill", title: "相册",
                                subtitle: "\(totalPhotos) 张", tint: BubuTheme.Color.mint)
            }
            .buttonStyle(.plain)

            NavigationLink { HealthHomeView() } label: {
                quickDockButton(icon: "cross.case.fill", title: "健康",
                                subtitle: "餐睡", tint: BubuTheme.Color.sky)
            }
            .buttonStyle(.plain)
        }
    }

    private func quickDockButton(icon: String, title: String, subtitle: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(BubuTheme.Color.deepRose)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.72), in: Circle())
            Text(title)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text(subtitle)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .lineLimit(1)
        }
        .frame(width: 66, height: 64)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.54), lineWidth: 1)
        }
    }

    // MARK: 紧凑四宫格 — 里程碑 / 成长数据 / 故事 / 今日一问

    private var litMilestoneCount: Int { milestones.filter(\.isAchieved).count }
    private var latestHeight: Double? {
        measurements.compactMap(\.heightCm).first ?? latestLegacyGrowthValue(.height)
    }

    private var latestWeight: Double? {
        measurements.compactMap(\.weightKg).first ?? latestLegacyGrowthValue(.weight)
    }

    private func latestLegacyGrowthValue(_ metric: WHOGrowthStandard.Metric) -> Double? {
        for record in healthRecords {
            if let value = GrowthMeasurementExtractor.value(metric, from: record) {
                return value
            }
        }
        return nil
    }

    private var dashboardGridTop: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], spacing: 10) {
            NavigationLink { MilestonesHomeView() } label: { constellationTile }
                .buttonStyle(.plain)
            NavigationLink { GrowthCurveView() } label: { growthTile }
                .buttonStyle(.plain)
            NavigationLink { BubuStoryView() } label: { storyTile }
                .buttonStyle(.plain)
            Button { startQuickCapture(prefillNote: "【今日一问】\(DailyQuestion.todays(birthday: profile?.birthday ?? .now))\n") } label: {
                dailyQuestionTile
            }
            .buttonStyle(.plain)
        }
    }

    private var constellationTile: some View {
        compactTileSurface(centered: true, contentPadding: 12) {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle().fill(BubuTheme.Color.pink.opacity(0.38)).frame(width: 34, height: 34)
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(BubuTheme.Color.deepRose)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("里程碑")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .lineLimit(1)
                    Text("\(litMilestoneCount)/\(max(milestones.count, 1)) 颗")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.deepRose)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 7) {
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: index < min(litMilestoneCount, 5) ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(index < min(litMilestoneCount, 5)
                                         ? BubuTheme.Color.butter
                                         : BubuTheme.Color.secondaryText.opacity(0.46))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var growthTile: some View {
        compactTileSurface(contentPadding: 14) {
            HStack(spacing: 6) {
                growthStat(title: "身高", value: latestHeight, unit: "cm")
                growthStat(title: "体重", value: latestWeight, unit: "kg")
            }
            growthBars
                .frame(height: 30)
            Text("成长数据")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .lineLimit(1)
        }
    }

    private var storyTile: some View {
        compactTileSurface(
            fill: AnyShapeStyle(LinearGradient(colors: [BubuTheme.Color.warmSurfaceTop,
                                                        BubuTheme.Color.warmSurfaceMid,
                                                        BubuTheme.Color.warmSurfaceEnd],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing)),
            centered: true
        ) {
            HStack(alignment: .center, spacing: 10) {
                BubuDreamPhoto(hue: 18, height: 52, cornerRadius: 13, motif: "✦")
                    .frame(width: 46)
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white, lineWidth: 2))
                    .rotationEffect(.degrees(-4))
                VStack(alignment: .leading, spacing: 3) {
                    Text("故事绘本")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text(storyHeadline)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.deepRose)
                    Text("自动编成故事")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var dailyQuestionTile: some View {
        compactTileSurface(centered: true) {
            HStack(alignment: .center, spacing: 9) {
                BubuMascotBadge(size: 38, expression: .surprised)
                VStack(alignment: .leading, spacing: 3) {
                    Text("今日一问")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("答一句就成时光")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .lineLimit(1)
                    Text("记录")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(BubuTheme.Color.primary, in: Capsule())
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func compactTileSurface<Content: View>(
        fill: AnyShapeStyle? = nil,
        centered: Bool = false,
        contentPadding: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let surface = fill ?? AnyShapeStyle(LinearGradient(colors: [
            BubuTheme.Color.tileSurfaceTop,
            BubuTheme.Color.tileSurfaceBottom
        ], startPoint: .topLeading, endPoint: .bottomTrailing))
        return VStack(alignment: .leading, spacing: 6) {
            content()
            if !centered {
                Spacer(minLength: 0)
            }
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .frame(height: 104)
        .frame(maxHeight: .infinity, alignment: centered ? .center : .top)
        .background(surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.60), lineWidth: 1)
        }
        .shadow(color: SwiftUI.Color(red: 0.71, green: 0.47, blue: 0.43).opacity(0.16),
                radius: 12, x: 0, y: 7)
    }

    private func growthStat(title: String, value: Double?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(BubuTheme.Color.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value.map { String(format: $0 == $0.rounded() ? "%.0f" : "%.1f", $0) } ?? "—")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
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
                        .foregroundStyle(BubuTheme.Color.secondaryText)
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
                LinearGradient(colors: [BubuTheme.Color.warmSurfaceTop, BubuTheme.Color.warmSurfaceMid],
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
                        Circle().fill(BubuTheme.Color.softFill).frame(width: 46, height: 46)
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
                    LinearGradient(colors: [BubuTheme.Color.tileSurfaceTop, BubuTheme.Color.tileSurfaceBottom],
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
                    NavigationLink(value: entry.id) { momentRow(entry) }
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
                            NavigationLink(value: entry.id) {
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

    private var naturalCaptureFloatingButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    BubuHaptics.tapLight()
                    showNaturalCapture = true
                } label: {
                    NaturalCaptureFloatingBubble(isDragging: naturalCaptureButtonDrag != .zero)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("一句话智能记录")
                .offset(CGSize(width: naturalCaptureButtonOffset.width + naturalCaptureButtonDrag.width,
                               height: naturalCaptureButtonOffset.height + naturalCaptureButtonDrag.height))
                .transaction { transaction in
                    if naturalCaptureButtonDrag != .zero {
                        transaction.animation = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .updating($naturalCaptureButtonDrag) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            naturalCaptureButtonOffset.width += value.translation.width
                            naturalCaptureButtonOffset.height += value.translation.height
                        }
                )
                .padding(.trailing, 16)
                .padding(.bottom, 118)
            }
        }
        .allowsHitTesting(true)
    }
}

private struct NaturalCaptureFloatingBubble: View {
    let isDragging: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(
                    LinearGradient(colors: [
                        BubuTheme.Color.primary,
                        BubuTheme.Color.pink.opacity(0.95),
                        BubuTheme.Color.peach.opacity(0.90)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 50, height: 50)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.86), lineWidth: 1.4)
                }
                .shadow(color: BubuTheme.Color.deepRose.opacity(isDragging ? 0.10 : 0.24),
                        radius: isDragging ? 5 : 10,
                        y: isDragging ? 2 : 5)
                .overlay {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-10))
                        .shadow(color: BubuTheme.Color.deepRose.opacity(0.18), radius: 2, y: 1)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("AI")
                        .font(.system(size: 10.5, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: BubuTheme.Color.deepRose.opacity(0.36), radius: 2, y: 1)
                        .padding(.trailing, 7)
                        .padding(.bottom, 5)
                }
                .offset(x: -7, y: -7)

            BubuStarShape()
                .fill(BubuTheme.Color.butter)
                .frame(width: 9, height: 9)
                .rotationEffect(.degrees(-12))
                .offset(x: -42, y: -38)
                .opacity(isDragging ? 0.55 : 0.86)

            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(BubuTheme.Color.butter)
                .offset(x: -3, y: -40)
                .opacity(isDragging ? 0.55 : 0.92)

        }
        .frame(width: 58, height: 58)
        .contentShape(Circle())
    }
}
