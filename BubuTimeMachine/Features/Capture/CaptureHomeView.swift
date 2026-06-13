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

    @State private var model: CaptureModel?
    @State private var firstTimeSuggestion: String?
    @State private var firstTimeEntryID: UUID?

    /// 缩略图 → 详情页的 iOS 18+ 缩放共享元素转场（与 TimelineView 同一套做法）。
    @Namespace private var zoomNS

    private var profile: ChildProfile? { profiles.first }
    private var theme: BubuThemeDefinition { env.theme.theme }

    var body: some View {
        ZStack {
            heroBackground.ignoresSafeArea()

            ScrollView {
                // 布局原则：主操作「记录此刻」必须首屏完整露出——紧跟输入条；
                // 同步状态条属于次要信息，下移到统计行之后；行距 14 紧凑但不拥挤。
                VStack(spacing: 14) {
                    ageHeader
                    NaturalCaptureBar()
                    recordButton
                    statRow
                    saveHealthStrip
                    onThisDaySection
                    healthEntryCard
                    dailyQuestionCard
                    recentStrip
                    Spacer(minLength: 24)
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
        if env.theme.heroMode == .photo,
           let name = profile?.heroBackgroundFileName,
           let data = env.mediaStore.data(forMedia: name),
           let ui = UIImage(data: data) {
            // 关键：用 Color.clear 接住父级提议的尺寸（满屏），照片以 overlay 填充再裁切。
            // 若直接给 Image .scaledToFill() 而不锁定 frame，它会把整页撑到照片原生尺寸（撑爆布局 bug）。
            Color.clear
                .overlay {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .overlay {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(colors: [theme.primary.opacity(0.25), .clear, theme.primary.opacity(0.15)],
                                   startPoint: .top, endPoint: .bottom)
                }
        } else {
            // 主题模式：MeshGradient 呼吸背景（§2.2）。星夜深色面板单独走暗渐变保证对比度。
            if env.isDarkTheme {
                BubuThemedBackground()
            } else {
                BubuMeshHero(colors: theme.meshColors)
                    .bubuPaperTexture(theme.paperTexture, isDark: false)
            }
        }
    }

    // MARK: 年龄头部（布布个人身份卡）

    @ViewBuilder
    private var ageHeader: some View {
        if let profile {
            NavigationLink {
                ChildProfileView()
            } label: {
                BubuIdentityCard(profile: profile,
                                 theme: theme,
                                 mediaStore: env.mediaStore)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        } else {
            VStack(spacing: 12) {
                Image("BubuLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 82, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: theme.primary.opacity(0.18), radius: 10, y: 4)
                Text("布布时光机").font(BubuTheme.Font.hugeTitle)
            }
        }
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
        .background(BubuTheme.Color.card.opacity(0.58), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
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

    // MARK: 统计行

    /// 三张统计卡都可点：瞬间 → 时光轴；照片 → 照片墙；生日 → 倒计时页。
    private var statRow: some View {
        HStack(spacing: 12) {
            Button { openTimeline?() } label: {
                statCard(value: "\(entries.count)", label: "个瞬间", icon: "sparkles")
            }
            .buttonStyle(.plain)

            NavigationLink { AlbumHomeView() } label: {
                statCard(value: "\(totalPhotos)", label: "张照片", icon: "photo.stack")
            }
            .buttonStyle(.plain)

            if let profile {
                NavigationLink { BirthdayCountdownView() } label: {
                    statCard(value: "\(AgeCalculator.daysUntilNextBirthday(birthday: profile.birthday))",
                             label: "天后生日", icon: "gift")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(theme.primary)
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text(label).font(.system(size: 12)).foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(BubuTheme.Color.card.opacity(0.68), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        // iOS 26 glassEffect 自带景深，去掉冗余的额外阴影（既省合成又更贴近原生质感）。
        .bubuGlassSurface(cornerRadius: BubuTheme.Radius.card, tint: theme.primary, interactive: true)
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
            .background(BubuTheme.Color.card.opacity(0.7), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
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
            .background(BubuTheme.Color.card.opacity(0.68), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
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
            .background(BubuTheme.Color.card.opacity(0.68), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .bubuGlassSurface(cornerRadius: BubuTheme.Radius.card, tint: theme.primary, interactive: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: 大记录按钮

    private var recordButton: some View {
        Button {
            model?.startQuickCapture()
        } label: {
            HStack(spacing: 0) {
                BubuMascotBadge(size: 82, expression: .travel)
                    .padding(.leading, 4)
                    .zIndex(1)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(BubuTheme.Copy.recordNow)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text("拍照、写一句、说给布布听")
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(theme.primary)
                }
                .padding(.vertical, 16)
                .padding(.leading, 20)
                .padding(.trailing, 18)
                .background(BubuTheme.Color.card.opacity(0.66), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .bubuGlassSurface(cornerRadius: 30, tint: theme.primary, interactive: true)
                .overlay(alignment: .leading) {
                    BubuSpeechTail()
                        .fill(BubuTheme.Color.card.opacity(0.66))
                        .frame(width: 18, height: 26)
                        .offset(x: -10)
                }
                .bubuCardShadow()
                .padding(.leading, -6)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("记录此刻，可以拍照、写一句或说给布布听")
    }

    // MARK: 最近精选

    @ViewBuilder
    private var recentStrip: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("最近的瞬间", systemImage: "clock")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(entries.prefix(8)) { entry in
                            NavigationLink(value: entry) {
                                if let media = entry.media.first {
                                    MediaThumbnail(media: media, mediaStore: env.mediaStore)
                                        .frame(width: 96, height: 96)
                                } else {
                                    BubuMascotBadge(size: 96, mood: entry.mood)
                                }
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: entry.id, in: zoomNS)
                        }
                    }
                }
            }
        }
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

private struct BubuSpeechTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                          control: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.18))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                          control: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.maxY - rect.height * 0.18))
        path.closeSubpath()
        return path
    }
}
