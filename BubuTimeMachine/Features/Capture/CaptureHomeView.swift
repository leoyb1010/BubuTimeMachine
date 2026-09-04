import SwiftUI
import SwiftData
import PhotosUI
import Photos
import UIKit

// MARK: - 首页 · 成长仪表盘
/// 专属布布的主屏：年龄实时计数 + 那年今日 + 统计 + 精选 + 大记录按钮。
/// 背景可用主题渐变或布布的照片。
struct CaptureHomeView: View {
    /// 刚刚确认的「人生第一次」，非空时播一次仪式动画。
    @State private var ceremonyTitle: String?
    var openTimeline: (() -> Void)?
    var quickCaptureTrigger: Int = 0

    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var profiles: [ChildProfile]
    @Query private var entries: [Entry]
    // 里程碑 / 成长实测 / 健康记录的 @Query 随四宫格一起撤走：
    // 首页不再展示这三域的派生统计，留着只会让每次首页刷新多拉三张全表。

    @State private var model: CaptureModel?
    @State private var firstTimeSuggestion: String?
    @State private var firstTimeEntryID: UUID?
    @State private var photoScanner = PhotoLibraryScanner()
    @State private var showTodayPhotos = false
    @State private var uploadQueueSummary = PhotoUploadQueueSummary(
        pendingBatches: 0, failedBatches: 0)
    @State private var ssdIntakeCandidates: [SSDIntakeCandidate] = []
    @State private var showSSDIntakeCandidates = false
    @State private var showPendingRecallDialog = false
    @State private var identityCardFlipped = false
    @State private var heroBackgroundImage: UIImage?

    // 首页统计缓存：全表派生值只在数据指纹变化时重算一次，
    // 避免拖动 AI 球/同步进度等高频 body 重绘里 O(n·m) 全表 faulting（U-P1-5）。
    @State private var totalPhotos = 0
    @State private var todayQuestionAnswerers: [String] = []
    @State private var onThisDayEntries: [Entry] = []

    /// 缩略图 → 详情页的 iOS 18+ 缩放共享元素转场（与 TimelineView 同一套做法）。
    @Namespace private var zoomNS

    init(openTimeline: (() -> Void)? = nil, quickCaptureTrigger: Int = 0) {
        self.openTimeline = openTimeline
        self.quickCaptureTrigger = quickCaptureTrigger
        var descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\Entry.happenedAt, order: .reverse)])
        // 首页只展示最近两条。留到 12 条是为了详情返回与数据刚同步时仍有稳定缓冲，
        // 但不再让十几年档案全部驻留首页；统计改走 COUNT/日期范围查询。
        descriptor.fetchLimit = 12
        _entries = Query(descriptor, animation: .default)
    }

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
                // 布局原则：首页只回答「布布现在怎么样 / 我现在要记一笔 / 最近发生了什么」。
                // 里程碑与成长曲线归「成长」Tab、绘本归「魔法屋」——它们曾在首页四宫格里
                // 再铺一遍，等于把两个 Tab 的存在感稀释掉，也让首页无限变长。
                // 顺序：问候 → 身份卡 → 待办卡片 → 主操作 → 今日一问 → 最近时光 → 那年今日。
                VStack(spacing: 12) {
                    greetingRow
                    if isBirthdayToday { birthdayBanner }   // 🎂 生日当天全 App 仪式（R4 C4）
                    schoolBanner               // 🎒 入园倒计时 / 上学头一个月（过后自动安静）
                    identityCardTop            // ① 布布身份卡（可翻面看性别/血型/出生地）
                    ssdCandidateCard           // 移动硬盘只生成候选，必须回手机确认
                    uploadQueueCard            // 后台原片必须可见、可重试，不能假装已经收好
                    todayPhotosCard            // 今天拍了照片时主动请你收进（零操作记录）
                    primaryActionDock          // ② 记录/相册/健康：首屏主动作更明确
                    // 「功能搬家」提示卡已移除：那次信息架构调整是 2.11.0 的事，
                    // 早就不是新消息了，却还常驻在首屏最值钱的位置上。
                    // 项目已经接了 TipKit，真要做渐进引导用它，不用再自养一套常驻横幅。
                    if entries.isEmpty {
                        firstRecordEmptyState  // ③a 空库：单焦点，只说「记第一笔」
                    } else {
                        dailyQuestionStrip     // ③b 今日一问（轻条，不再占四宫格一格）
                        recentMomentsSection   // ④ 最近时光（行卡）
                        onThisDaySection
                    }
                    SaveHealthStrip()
                    // 给底部悬浮玻璃 Tab 栏留出空间
                    // 宽屏走侧栏、没有悬浮底栏，不需要这块预留
                    Spacer(minLength: BubuAdaptive.value(sizeClass, compact: 150, regular: 40))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .bubuContentColumn(920)
            }
            // 下拉刷新此前全仓 0 处。首页只在出现和回到前台时刷新，同步状态还藏在页面最底部，
            // 而下拉是「我要最新的」最强的本能——之前它纹丝不动。
.overlay {
    if let title = ceremonyTitle {
        CeremonyAnimation(title: title, subtitle: "布布的人生第一次，已经收进档案里了。") {
            withAnimation(BubuMotion.gentle) { ceremonyTitle = nil }
        }
        .transition(.opacity)
    }
}
            .refreshable { await pullToRefresh() }
            // 详情页转场移到此处（而非 RootTabView），以便与本页 zoomNS 配对实现缩放共享元素转场。
            .navigationDestination(for: UUID.self) { entryID in
                if let entry = navigableEntries.first(where: { $0.id == entryID }) {
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
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // 保存成功时的成功触觉，与「已经收好啦」贴纸同步，强化「完成感」。
        .bubuSensoryFeedback(.success, trigger: model?.savedFlash)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if model == nil {
                model = CaptureModel(mediaStore: env.mediaStore, analyzer: env.photoAnalyzer,
                                     role: env.config.currentRole)
            }
            kickOffHomeRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // 拍完照切回 App 时立即消费 PhotoKit 增量，不等重启；仍只生成候选，不自动发布。
            kickOffHomeRefresh()
        }
        .onChange(of: quickCaptureTrigger) { _, _ in
            startQuickCapture()
        }
        .onChange(of: model?.lastSavedEntryID) { _, newID in
            if let id = newID {
                Task { await detectFirstTime(entryID: id) }
            }
        }
        .onChange(of: statsFingerprint, initial: true) { _, _ in rebuildStats() }
        .onChange(of: env.syncEngine.lastSyncedAt) { _, _ in rebuildStats() }
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
        // 部分媒体导入失败：面板已关，提示在首页层弹出（U-P1-3）
        .alert("部分照片没导入", isPresented: Binding(
            get: { model?.partialSaveWarning != nil },
            set: { if !$0 { model?.partialSaveWarning = nil } })) {
            Button("好") { model?.partialSaveWarning = nil }
        } message: {
            Text(model?.partialSaveWarning ?? "")
        }
        .sheet(isPresented: $showTodayPhotos) {
            TodayPhotosSheet(assets: photoScanner.pendingAssets, groups: photoScanner.eventGroups) { outcome in
                photoScanner.markAccepted(outcome.accepted)
                photoScanner.markIgnored(outcome.ignored)
                photoScanner.markQueued(outcome.queued)
                refreshUploadQueueSummary()
            }
        }
        .sheet(isPresented: $showSSDIntakeCandidates) {
            SSDIntakeCandidatesSheet(candidates: $ssdIntakeCandidates)
        }
    }

    @ViewBuilder
    private var ssdCandidateCard: some View {
        if !ssdIntakeCandidates.isEmpty {
            Button { showSSDIntakeCandidates = true } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(BubuTheme.Color.primary.opacity(0.16))
                            .frame(width: 44, height: 44)
                        Image(systemName: "externaldrive.badge.plus")
                            .font(BubuTheme.Font.scaled(19, weight: .bold))
                            .foregroundStyle(BubuTheme.Color.primary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("移动硬盘有 \(ssdIntakeCandidates.count) 段待确认")
                            .font(BubuTheme.Font.scaled(15, weight: .heavy, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text("先核对拍摄时间，再决定收进或忽略；源文件不会被移动或删除")
                            .font(BubuTheme.Font.scaled(12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(BubuTheme.Font.scaled(13, weight: .bold))
                        .foregroundStyle(BubuTheme.Color.primary)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(homeSurface, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
                .bubuCardShadow()
            }
            .buttonStyle(.plain)
        }
    }

    private func refreshSSDCandidates() async {
        guard let service = makeIntakeService(env) else { return }
        if let candidates = try? await service.intakeCandidates() {
            ssdIntakeCandidates = candidates
        }
    }

    @ViewBuilder
    private var uploadQueueCard: some View {
        if uploadQueueSummary.failedBatches > 0 {
            photoIntakePermissionCard(
                title: "有 \(uploadQueueSummary.failedBatches) 段原片暂时停住了",
                subtitle: "原片仍在系统相册里；网络恢复后可以安全继续，不会重复发布",
                actionTitle: "重新整理"
            ) {
                retryFailedUploads()
            }
        } else if uploadQueueSummary.pendingBatches > 0 {
            // 【出路修复】原来是不可点的死卡：批次在服务端卡在 accepted/uploading 时
            // 会永远显示"正在回家"，用户没有任何操作出口。改成可点 + 取回对话框。
            Button {
                showPendingRecallDialog = true
            } label: {
                HStack(spacing: 12) {
                    ProgressView().tint(BubuTheme.Color.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(uploadQueueSummary.pendingBatches) 段原片正在回家")
                            .font(BubuTheme.Font.scaled(15, weight: .heavy, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text(uploadQueueSummary.totalJobs > 0
                             ? "已传 \(uploadQueueSummary.uploadedJobs)/\(uploadQueueSummary.totalJobs) 张；锁屏也会继续，长时间没进展可点这里"
                             : "锁屏或切换 App 也会继续；长时间没进展可点这里处理")
                            .font(BubuTheme.Font.scaled(12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(BubuTheme.Font.scaled(13, weight: .semibold))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(homeSurface, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
                .bubuCardShadow()
            }
            .buttonStyle(.plain)
            .confirmationDialog("原片正在后台上传", isPresented: $showPendingRecallDialog,
                                titleVisibility: .visible) {
                Button("取回照片，重新整理") { recallPendingUploads() }
                Button("继续等待", role: .cancel) {}
            } message: {
                Text("通常无需操作，锁屏也会继续上传。如果长时间没进展，可以把照片取回候选箱重新整理；已部分上传成功的批次会保留继续等待，不会重复发布。")
            }
        }
    }

    /// 首页刷新統一入口。冷启动时 onAppear 与 didBecomeActive 会背靠背各来一次，
    /// 原来是两份一模一样的工作清单——scan 有合并闸，但 SSD 候选/上传对账没有：
    /// 双份认证、双份批次状态查询、双份 commit 尝试，纯浪费。2 秒节流合并成一份。
    @State private var lastHomeRefreshAt = Date.distantPast
    /// 照片智能收件箱总开关（默认关）：实际使用验证下来，手动发记录 + SSD 批量
    /// 导入才是主路；自动收件箱交互不顺手，收进设置里做可选能力。
    @AppStorage("bubu.photoInbox.enabled") private var photoInboxEnabled = false

    /// 下拉刷新：重算本页派生数据 + 立刻催一轮同步。
    /// 留一段最短可见时间，否则本地重算是同步的，转轮会闪一下就消失，
    /// 用户会以为「没反应」——这里的等待是给人看的，不是给机器的。
    @MainActor
    private func pullToRefresh() async {
        kickOffHomeRefresh()
        env.syncEngine.syncNow()
        try? await Task.sleep(for: .milliseconds(650))
    }

    private func kickOffHomeRefresh() {
        photoScanner.refreshAuthorizationState()
        guard Date.now.timeIntervalSince(lastHomeRefreshAt) > 2 else { return }
        lastHomeRefreshAt = .now
        rebuildStats()
        if photoInboxEnabled, photoScanner.authorized { Task { _ = await photoScanner.scan() } }
        refreshUploadQueueSummary()
        Task { await refreshSSDCandidates() }
        Task { await reconcileReliableUploads() }
    }

    private func refreshUploadQueueSummary() {
        // 这是与 BubuPhotoUpload 扩展跨进程共享的 WAL 库（busy_timeout 5s）：
        // 扩展正持有写锁的瞬间（didBecomeActive 恰是双方同时活跃的时刻），
        // 主线程同步读最长会卡整整 5 秒。读移到后台，结果回主线程。
        Task {
            let summary = await Task.detached(priority: .utility) {
                (try? PhotoIntakeStore().uploadQueueSummary())
                    ?? PhotoUploadQueueSummary(pendingBatches: 0, failedBatches: 0)
            }.value
            uploadQueueSummary = summary
        }
    }

    private func recallPendingUploads() {
        Task {
            do {
                let recalledEntryIDs = try await Task.detached(priority: .userInitiated) {
                    try PhotoIntakeStore().recallStalledUploadBatches()
                }.value
                // 取回批次对应的本地占位记录一并删除（照片回到候选箱，占位留着
                // 会在用户再次确认时变成重复记录）。只删服务器从未确认过的。
                deletePlaceholderEntries(localIDs: recalledEntryIDs)
                _ = await photoScanner.scan()
                refreshUploadQueueSummary()
                BubuHaptics.success()
                if recalledEntryIDs.isEmpty {
                    model?.partialSaveWarning = "这些批次已有照片上传成功，为避免重复发布会继续等待服务器收口"
                }
            } catch {
                model?.partialSaveWarning = "取回暂时没成功：\(error.localizedDescription)"
            }
        }
    }

    /// 删除后台上传的本地占位记录。判据必须同时满足：
    /// syncState == .synced 且 remoteId == nil——只有占位记录长这样
    /// （正常记录推送后有 remoteId，拉下来的也有），绝不会误删真实记录。
    private func deletePlaceholderEntries(localIDs: [String]) {
        guard !localIDs.isEmpty else { return }
        for idString in localIDs {
            guard let uuid = UUID(uuidString: idString) else { continue }
            let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == uuid })
            guard let entry = try? modelContext.fetch(descriptor).first,
                  entry.remoteId == nil, entry.syncState == .synced else { continue }
            for media in entry.media {
                env.mediaStore.deleteLocalFiles(media: media.localFileName,
                                                thumbnail: media.thumbnailFileName)
                modelContext.delete(media)
            }
            modelContext.delete(entry)
        }
        try? modelContext.save()
    }

    /// 孤儿占位清理：批次已 committed 但服务端因整批照片重复没建 Entry
    /// （hook 去重路径），本地占位在一轮成功同步后仍无 remoteId——删除，
    /// 否则同一批照片在时光轴出现两条记录。给同步留 5 分钟余量。
    private func cleanupOrphanPlaceholders() async {
        guard let lastSynced = env.syncEngine.lastSyncedAt else { return }
        let rows = await Task.detached(priority: .utility) {
            (try? PhotoIntakeStore().committedBatchEntryInfo()) ?? []
        }.value
        let stale = rows.filter { lastSynced > $0.committedAt.addingTimeInterval(300) }
        guard !stale.isEmpty else { return }
        deletePlaceholderEntries(localIDs: stale.map(\.entryLocalID))
    }

    private func retryFailedUploads() {
        Task {
            do {
                // BEGIN IMMEDIATE 逐批写事务：同样下移，别在主线程等跨进程锁。
                try await Task.detached(priority: .userInitiated) {
                    try PhotoIntakeStore().resetFailedUploadBatches()
                }.value
                _ = await photoScanner.scan()
                refreshUploadQueueSummary()
                BubuHaptics.success()
            } catch {
                model?.partialSaveWarning = "后台上传暂时没有恢复：\(error.localizedDescription)"
            }
        }
    }

    private func reconcileReliableUploads() async {
        guard #available(iOS 26.4, *),
              env.config.isConfigured,
              let baseURL = env.config.aiBaseURL else { return }
        let service = ReliablePhotoIntakeService(baseURL: baseURL) {
            try await env.apiClient.authenticate(role: "intake").token
        }
        await service.reconcilePendingBatches()
        await cleanupOrphanPlaceholders()
        refreshUploadQueueSummary()
        photoScanner.refreshAuthorizationState()
        if photoScanner.authorized { _ = await photoScanner.scan() }
    }

    // MARK: 今天拍的照片卡（零操作记录）
    @ViewBuilder
    private var todayPhotosCard: some View {
        if photoInboxEnabled, photoScanner.authorized, photoScanner.lastError != nil {
            photoIntakePermissionCard(
                title: "照片自动整理暂时停住了",
                subtitle: "没有处理或发布任何照片，原片仍在系统相册里；可以稍后重试",
                actionTitle: "重试"
            ) {
                Task { _ = await photoScanner.scan() }
            }
        } else if photoInboxEnabled, photoScanner.authorized, !photoScanner.pendingAssets.isEmpty {
            Button {
                showTodayPhotos = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(BubuTheme.Color.primary.opacity(0.16)).frame(width: 44, height: 44)
                        Image(systemName: "photo.badge.plus.fill")
                            .font(BubuTheme.Font.scaled(19, weight: .bold))
                            .foregroundStyle(BubuTheme.Color.primary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("有 \(photoScanner.eventGroups.count) 段时光待收好")
                            .font(BubuTheme.Font.scaled(15, weight: .heavy, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text(photoScanner.truncatedPendingCount > 0
                             ? "先收好最近 \(photoScanner.pendingAssets.count) 个，还有 \(photoScanner.truncatedPendingCount) 个更早的会自动接上"
                             : (photoScanner.hasFullAccess
                                ? "共 \(photoScanner.pendingAssets.count) 个照片和视频，已自动整理"
                                : "已整理授权范围内的 \(photoScanner.pendingAssets.count) 个素材；完整访问可自动发现全部"))
                            .font(BubuTheme.Font.scaled(12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(BubuTheme.Font.scaled(13, weight: .bold))
                        .foregroundStyle(BubuTheme.Color.primary)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(homeSurface, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
                .bubuCardShadow()
            }
            .buttonStyle(.plain)
            .popoverTip(TodayPhotosTip())
        } else if photoInboxEnabled, photoScanner.authorizationStatus == .limited {
            photoIntakePermissionCard(
                title: "目前只看得到部分照片",
                subtitle: "改为完整访问后，才能自动发现之后拍摄的全部照片和视频",
                actionTitle: "管理"
            ) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        } else if photoInboxEnabled, photoScanner.authorizationStatus == .notDetermined {
            photoIntakePermissionCard(
                title: "让照片自己排好队",
                subtitle: "一次授权，自动发现新照片和视频；确认后才会收进时光",
                actionTitle: "开启"
            ) {
                Task { _ = await photoScanner.requestAndScan() }
            }
        } else if photoScanner.authorizationStatus == .denied ||
                    photoScanner.authorizationStatus == .restricted {
            photoIntakePermissionCard(
                title: "照片自动整理还没开启",
                subtitle: "到系统设置允许读取照片，原片仍只在你确认后收录",
                actionTitle: "去设置"
            ) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }

    private func photoIntakePermissionCard(
        title: String,
        subtitle: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(BubuTheme.Color.primary.opacity(0.16)).frame(width: 44, height: 44)
                Image(systemName: "photo.stack.fill")
                    .font(BubuTheme.Font.scaled(18, weight: .bold))
                    .foregroundStyle(BubuTheme.Color.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BubuTheme.Font.scaled(15, weight: .heavy, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(subtitle)
                    .font(BubuTheme.Font.scaled(12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(actionTitle, action: action)
                .font(BubuTheme.Font.scaled(13, weight: .bold))
                .buttonStyle(.borderedProminent)
                .tint(BubuTheme.Color.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(homeSurface, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        .bubuCardShadow()
    }

    /// 保存后调用 AI 识别"第一次"（仅在启用真实 AI 时）。
    private func detectFirstTime(entryID: UUID) async {
        guard env.config.isAIConfigured else { return }
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryID })
        guard let entry = try? modelContext.fetch(descriptor).first,
              !entry.sortedMedia.isEmpty else { return }
        if let suggestion = try? await env.aiService.detectFirstTime(media: entry.sortedMedia),
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
        guard (try? modelContext.save()) != nil else { firstTimeSuggestion = nil; return }
        firstTimeSuggestion = nil
        // CeremonyAnimation 的注释写的是「里程碑 / **人生第一次**完成时」，
        // 但一直只接了里程碑那一处。「第一次」是 AI 主动认出来、家长点头确认的时刻，
        // 是这个产品最感人的几秒之一，此前却只是插条数据、关掉弹窗，像在填表。
        ceremonyTitle = what
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

    // MARK: 生日仪式（素材早齐：生日图标/音效/迸发组件，只差编排——R4 C4）

    private var isBirthdayToday: Bool {
        guard let birthday = profile?.birthday else { return false }
        let cal = Calendar.current
        return cal.component(.month, from: .now) == cal.component(.month, from: birthday)
            && cal.component(.day, from: .now) == cal.component(.day, from: birthday)
    }

    private var birthdayBanner: some View {
        HStack(spacing: 12) {
            Text("🎂").font(BubuTheme.Font.scaled(32))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(profile?.name ?? "布布")生日快乐！")
                    .font(BubuTheme.Font.scaled(18, weight: .heavy, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.paperInk)
                Text("今天的每一个瞬间都值得收藏 🎈")
                    .font(BubuTheme.Font.scaled(12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.paperInkSecondary)
            }
            Spacer()
            Text("🎉").font(BubuTheme.Font.scaled(26))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(
            LinearGradient(colors: [BubuTheme.Color.butter, BubuTheme.Color.pink],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        .bubuCardShadow()
        .overlay { BubuBurst(count: 20, radius: 150) }
        // sfx-birthday.caf 与 BubuSound.Effect.birthday 早就做好了，却从没有一处调用。
        // 当天只放一次：横幅在首页常驻，每次滚回来都响会变成骚扰。
        // BubuSound 本身默认关闭、跟随静音键，用户没开就什么都不会发生。
        .onAppear {
            let key = "bubu.birthdaySoundPlayed"
            let today = BubuDateFormat.yearMonthDay(.now)
            guard UserDefaults.standard.string(forKey: key) != today else { return }
            UserDefaults.standard.set(today, forKey: key)
            BubuSound.play(.birthday)
        }
    }

    // MARK: 入园（幼儿园）

    /// 只在真正相关的窗口里出现：开学前 30 天内的倒计时，或开学后头 30 天的「上学第 N 天」。
    /// 过了就自动安静下去——首页不该再多一张常驻卡；之后想看，身份卡背面一直印着。
    @ViewBuilder
    private var schoolBanner: some View {
        if let start = profile?.schoolStartDate, let copy = schoolBannerCopy(start: start) {
            HStack(spacing: 12) {
                BubuMascotBadge(size: 44, expression: copy.expression)
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.title)
                        .font(BubuTheme.Font.scaled(16, weight: .heavy, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.paperInk)
                    Text(copy.subtitle)
                        .font(BubuTheme.Font.scaled(12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.paperInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Text("🎒").font(BubuTheme.Font.scaled(26))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(
                LinearGradient(colors: [BubuTheme.Color.butter, BubuTheme.Color.pink],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
            .bubuCardShadow()
            .accessibilityElement(children: .combine)
        }
    }

    private func schoolBannerCopy(start: Date) -> (title: String, subtitle: String, expression: BubuExpression)? {
        let name = profile?.name ?? "布布"
        if let left = AgeCalculator.daysUntilSchoolStart(start) {
            guard left <= 30 else { return nil }
            if left == 1 {
                return ("明天就要上幼儿园了", "今晚问问\(name)，她期待什么、担心什么——这句话以后再也问不到了。", .surprised)
            }
            return ("还有 \(left) 天上幼儿园", "开学那天只有一次。可以先记下现在的\(name)是什么样子。", .thinking)
        }
        guard let day = AgeCalculator.daysSinceSchoolStart(start) else { return nil }
        switch day {
        case 1:
            return ("今天是上幼儿园第 1 天", "接回来先别急着问乖不乖。问问她今天认识了谁。", .cheer)
        case 2...30:
            return ("上幼儿园第 \(day) 天", "白天你看不见的那几个小时，靠她自己讲出来。", .happy)
        default:
            return nil
        }
    }

    // 顶部问候行（纯展示，对照设计稿「☀︎ 早安呀 + 名字 + 年龄」）
    private var greetingRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(greetingText) 呀")
                    .font(BubuTheme.Font.scaled(14, weight: .semibold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                if let profile {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(profile.name)
                            .font(BubuTheme.Font.scaled(28, weight: .heavy, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text(AgeCalculator.ageDescription(birthday: profile.birthday, at: .now))
                            .font(BubuTheme.Font.scaled(14, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.primary)
                    }
                }
            }
            Spacer()
            todayStatusPill
            NavigationLink { SettingsView() } label: {
                Image(systemName: "gearshape.fill")
                    .font(BubuTheme.Font.scaled(18, weight: .bold))
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
        // 顶部四个并列信息在无障碍超大字号会互相挤压；保留完整 VoiceOver 语义，
        // 视觉字号夹到 xxxLarge，避免姓名逐字断行和设置按钮被推出屏幕。
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var todayStatusPill: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(BubuTheme.Font.scaled(10, weight: .bold))
                Text(todayText)
                    .font(BubuTheme.Font.scaled(11, weight: .bold, design: .rounded))
            }
            HStack(spacing: 5) {
                Image(systemName: weatherSymbol)
                    .font(BubuTheme.Font.scaled(11, weight: .bold))
                Text(weatherMoodText)
                    .font(BubuTheme.Font.scaled(11, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(BubuTheme.Color.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous)
                .stroke(.white.opacity(0.52), lineWidth: 1)
        }
        // 四个碎片（日历图标/日期/天气图标/心情）逐个念出来毫无意义，合成一句。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今天 \(todayText)，\(weatherMoodText)")
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
            BubuIdentityCard(
                profile: profile,
                theme: theme,
                mediaStore: env.mediaStore,
                isFlipped: $identityCardFlipped)
                .entranceEffect(index: 0)
        } else {
            // 无档案：引导建档（保证空态也好看，不留空白）
            NavigationLink { ChildProfileView() } label: {
                HStack(spacing: 14) {
                    BubuMascotBadge(size: 56, expression: .happy)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("建立布布的档案")
                            .font(BubuTheme.Font.scaled(18, weight: .heavy, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text("填上生日，就能看到「相遇第几天」啦 ♡")
                            .font(BubuTheme.Font.scaled(12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(BubuTheme.Gradient.hero, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                .bubuCardShadow()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 首屏主操作 — 记录 / 相册 / 健康

    private var primaryActionDock: some View {
        HStack(spacing: 10) {
            // 「记录此刻」在窄屏是重复的：系统底部附件（RootTabView 的 root.record）
            // 已经常驻在屏幕底部，两处同名同功能、副标题还不一样，读起来像 bug。
            // 宽屏没有底部附件（tabViewBottomAccessory(isEnabled: !isWide)），
            // 所以 iPad / Mac 侧栏形态下这里仍是唯一入口，必须保留。
            if BubuAdaptive.isWide(sizeClass) {
                Button { startQuickCapture() } label: { recordButtonLabel }
                    .buttonStyle(BubuPressableStyle())
                    .layoutPriority(1)
                    .accessibilityIdentifier("home.record")
            }

            NavigationLink { AlbumHomeView() } label: {
                quickDockButton(icon: "photo.on.rectangle.angled.fill", title: "相册",
                                subtitle: "\(totalPhotos) 张", tint: BubuTheme.Color.mint)
            }
            .buttonStyle(BubuPressableStyle())

            NavigationLink { HealthHomeView() } label: {
                quickDockButton(icon: "cross.case.fill", title: "健康",
                                subtitle: "餐睡", tint: BubuTheme.Color.sky)
            }
            .buttonStyle(BubuPressableStyle())
        }
    }

    private var recordButtonLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(BubuTheme.Font.scaled(20, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(BubuTheme.Gradient.primaryButton, in: Circle())
                .shadow(color: BubuTheme.Color.deepRose.opacity(0.35), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("记录此刻")
                    .font(BubuTheme.Font.scaled(16, weight: .heavy, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("照片、声音和一句话一起收好")
                    .font(BubuTheme.Font.scaled(11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 64)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous)
                .stroke(.white.opacity(0.58), lineWidth: 1)
        }
    }

    /// 首屏三个主动作的小方块。图标 + 标题 + 副标三段分别朗读会很啰嗦，合成一句。
    private func quickDockButton(icon: String, title: String, subtitle: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(BubuTheme.Font.scaled(16, weight: .bold))
                .foregroundStyle(BubuTheme.Color.deepRose)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.72), in: Circle())
            Text(title)
                .font(BubuTheme.Font.scaled(11.5, weight: .bold, design: .rounded))
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text(subtitle)
                .font(BubuTheme.Font.scaled(9.5, weight: .medium, design: .rounded))
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .lineLimit(1)
        }
        .frame(minWidth: 66, minHeight: 64)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous)
                .stroke(.white.opacity(0.54), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(subtitle)")
    }

    private var navigableEntries: [Entry] {
        entries + onThisDayEntries.filter { memory in
            !entries.contains(where: { $0.id == memory.id })
        }
    }

    /// 首页统计指纹只看限量窗口和当天；实际统计走 SQLite COUNT/日期范围查询。
    private var statsFingerprint: String {
        var mediaCount = 0
        for e in entries { mediaCount += e.sortedMedia.count }
        let day = Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)
        return "\(entries.count)-\(mediaCount)-\(day)"
    }

    /// 重算三项派生统计。照片走 COUNT；今日问题和那年今日只查询命中的日期窗口。
    private func rebuildStats() {
        let cal = Calendar.current
        let photoDescriptor = FetchDescriptor<Media>(predicate: #Predicate {
            $0.typeRaw == "photo"
                && ($0.thumbnailFileName != nil || $0.localFileName != nil)
                && $0.entry?.isArchived == false
        })
        totalPhotos = (try? modelContext.fetchCount(photoDescriptor)) ?? 0

        let startOfToday = cal.startOfDay(for: .now)
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? .now
        let todayDescriptor = FetchDescriptor<Entry>(predicate: #Predicate {
            !$0.isArchived && $0.happenedAt >= startOfToday && $0.happenedAt < startOfTomorrow
        })
        var roles: [String] = []
        for e in (try? modelContext.fetch(todayDescriptor)) ?? [] {
            guard e.note?.hasPrefix("【今日一问】") == true else { continue }
            if !roles.contains(e.authorRole) { roles.append(e.authorRole) }
        }
        todayQuestionAnswerers = roles

        let today = cal.dateComponents([.month, .day], from: .now)
        let currentYear = cal.component(.year, from: .now)
        let firstYear = profile.map { cal.component(.year, from: $0.birthday) } ?? currentYear - 18
        var memories: [Entry] = []
        if firstYear < currentYear {
            for year in firstYear..<currentYear {
                var components = DateComponents()
                components.calendar = cal
                components.year = year
                components.month = today.month
                components.day = today.day
                guard let dayStart = cal.date(from: components),
                      cal.component(.month, from: dayStart) == today.month,
                      cal.component(.day, from: dayStart) == today.day,
                      let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { continue }
                let descriptor = FetchDescriptor<Entry>(
                    predicate: #Predicate {
                        !$0.isArchived && $0.happenedAt >= dayStart && $0.happenedAt < dayEnd
                    },
                    sortBy: [SortDescriptor(\Entry.happenedAt, order: .reverse)])
                memories.append(contentsOf: (try? modelContext.fetch(descriptor)) ?? [])
            }
        }
        onThisDayEntries = memories.sorted { $0.happenedAt > $1.happenedAt }
    }

    // MARK: 今日一问（轻条）

    /// 从四宫格里的一格改成一条轻横条：它是「回答一句」，不是一个需要占据首屏 1/4 的入口。
    /// 文案里带上今天已回答的家人，全家合唱的感觉比一个静态图标更能推动人去答。
    private var dailyQuestionStrip: some View {
        Button {
            startQuickCapture(prefillNote: "【今日一问】\(DailyQuestion.todays(birthday: profile?.birthday ?? .now, schoolStartDate: profile?.schoolStartDate))\n")
        } label: {
            HStack(spacing: 11) {
                BubuMascotBadge(size: 34, expression: .surprised)
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日一问")
                        .font(BubuTheme.Font.scaled(14, weight: .heavy, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text(dailyQuestionSubtitle)
                        .font(BubuTheme.Font.scaled(12, weight: .medium, design: .rounded))
                        .foregroundStyle(todayQuestionAnswerers.isEmpty
                                         ? BubuTheme.Color.secondaryText : BubuTheme.Color.deepRose)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Text("答一句")
                    .font(BubuTheme.Font.scaled(12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(BubuTheme.Color.primary, in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("今日一问，\(dailyQuestionSubtitle)")
        .accessibilityHint("打开记录面板并预填今天的问题")
    }

    private var dailyQuestionSubtitle: String {
        todayQuestionAnswerers.isEmpty
            ? DailyQuestion.todays(birthday: profile?.birthday ?? .now, schoolStartDate: profile?.schoolStartDate)
            : "\(todayQuestionAnswerers.joined(separator: "、"))已回答，一起合个唱？"
    }

    // MARK: 空库单焦点

    /// 新装机第一印象：不摆一整屏还没有数据的仪表盘，只说一件事——记第一笔。
    /// 有了第一条记录，最近时光/那年今日/今日一问才依次登场。
    private var firstRecordEmptyState: some View {
        VStack(spacing: 14) {
            BubuMascotBadge(size: 76, expression: .happy)
            Text("给\(profile?.name ?? "布布")记第一笔")
                .font(BubuTheme.Font.scaled(20, weight: .heavy, design: .rounded))
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text("一张照片、一句话，或者按住说一段。\n以后这里会长成她的时光轴。")
                .font(BubuTheme.Font.scaled(13, weight: .medium, design: .rounded))
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { startQuickCapture() } label: {
                Text("记第一笔")
                    .font(BubuTheme.Font.scaled(16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 14)
                    .background(BubuTheme.Gradient.primaryButton, in: Capsule())
                    .shadow(color: BubuTheme.Color.deepRose.opacity(0.32), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 1)
        }
    }

    // MARK: 最近时光（行卡，对照设计稿 MacMomentRow）

    @ViewBuilder
    private var recentMomentsSection: some View {
        if !entries.isEmpty {
            VStack(spacing: 10) {
                HStack {
                    Text("最近时光")
                        .font(BubuTheme.Font.scaled(17, weight: .heavy, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Spacer()
                    Button { openTimeline?() } label: {
                        Text("查看全部 ›")
                            .font(BubuTheme.Font.scaled(12.5, weight: .semibold, design: .rounded))
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
                if let media = entry.coverMedia {
                    MediaThumbnail(media: media, mediaStore: env.mediaStore)
                } else {
                    BubuDreamPhoto(hue: entry.id.bubuStableHue, height: 64,
                                   cornerRadius: BubuTheme.Radius.sm, motif: entry.mood?.emoji ?? "◡")
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(BubuDateFormat.monthDay(entry.happenedAt))
                    .font(BubuTheme.Font.scaled(11, weight: .bold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.primary)
                Text(entry.note?.isEmpty == false ? entry.note! : "记录此刻")
                    .font(BubuTheme.Font.scaled(14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineLimit(1)
                if let mood = entry.mood {
                    Text("\(mood.emoji) \(mood.rawValue)")
                        .font(BubuTheme.Font.scaled(12, weight: .medium, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        .bubuCardShadow()
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
                            .font(BubuTheme.Font.scaled(13, weight: .semibold))
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
            if let media = entry.coverMedia {
                MediaThumbnail(media: media, mediaStore: env.mediaStore)
                    .frame(width: 130, height: 130)
            } else {
                RoundedRectangle(cornerRadius: BubuTheme.Radius.small)
                    .fill(theme.primary.opacity(0.12))
                    .frame(width: 130, height: 130)
                    .overlay { Text(entry.mood?.emoji ?? "📝").font(BubuTheme.Font.scaled(40)) }
            }
            if let profile {
                Text(AgeCalculator.compactAge(birthday: profile.birthday, at: entry.happenedAt))
                    .font(BubuTheme.Font.scaled(13, weight: .semibold))
                    .foregroundStyle(theme.primary)
            }
            Text(yearsAgoText(entry.happenedAt))
                .font(BubuTheme.Font.scaled(11)).foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .frame(width: 130)
    }


    private func yearsAgoText(_ date: Date) -> String {
        // 筛选已保证同月同日，只取「年」分量之差，避免 dateComponents 含时分导致
        // 晚间拍的两年前照片上午被算成「1年前」。
        let cal = Calendar.current
        let years = cal.component(.year, from: .now) - cal.component(.year, from: date)
        return years <= 0 ? "今年" : "\(years)年前的今天"
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
            // 保存是核心奖励时刻（R4 C1）：贴纸落下同时星点迸发，一眼「收好了」
            .overlay { BubuBurst(count: 16, radius: 115) }
            Spacer()
        }
        .padding(.top, 8)
        .transition(.scale(scale: 0.5, anchor: .top).combined(with: .opacity))
    }

}

private struct SSDIntakeCandidatesSheet: View {
    @Binding var candidates: [SSDIntakeCandidate]
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var editedDates: [String: Date] = [:]
    @State private var workingID: String?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(candidates) { candidate in
                    Section {
                        DatePicker(
                            "发生时间",
                            selection: dateBinding(for: candidate),
                            displayedComponents: [.date, .hourAndMinute])
                        Text(candidate.items.prefix(3).map(\.fileName).joined(separator: "、"))
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                        if candidate.items.count > 3 {
                            Text("另有 \(candidate.items.count - 3) 个素材")
                                .font(BubuTheme.Font.caption)
                                .foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                        if candidate.entry.captureTimeSources?.contains("file-modified-fallback") == true {
                            Label("未读到内嵌拍摄时间，当前日期按文件时间推测，请核对后再确认。",
                                  systemImage: "exclamationmark.triangle")
                                .font(BubuTheme.Font.caption)
                                .foregroundStyle(BubuTheme.Color.warning)
                        }
                        HStack {
                            Button("忽略", role: .destructive) {
                                Task { await cancel(candidate) }
                            }
                            Spacer()
                            Button(workingID == candidate.id ? "处理中…" : "确认收进") {
                                Task { await confirm(candidate) }
                            }
                            .disabled(workingID != nil)
                            .buttonStyle(.borderedProminent)
                        }
                    } header: {
                        Text("\(candidate.items.count) 个照片或视频")
                    }
                }
                if let errorText {
                    Text(errorText).foregroundStyle(BubuTheme.Color.danger)
                }
            }
            .navigationTitle("移动硬盘候选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                for candidate in candidates where editedDates[candidate.id] == nil {
                    editedDates[candidate.id] = Self.parse(candidate.entry.happenedAt) ?? .now
                }
            }
        }
    }

    private func dateBinding(for candidate: SSDIntakeCandidate) -> Binding<Date> {
        Binding(
            get: { editedDates[candidate.id] ?? Self.parse(candidate.entry.happenedAt) ?? .now },
            set: { editedDates[candidate.id] = $0 })
    }

    private func confirm(_ candidate: SSDIntakeCandidate) async {
        guard let service = makeIntakeService(env) else { return }
        workingID = candidate.id
        defer { workingID = nil }
        do {
            try await service.updateIntakeCandidate(
                id: candidate.id,
                happenedAt: editedDates[candidate.id] ?? Self.parse(candidate.entry.happenedAt) ?? .now)
            try await service.confirmIntakeCandidate(id: candidate.id)
            candidates.removeAll { $0.id == candidate.id }
            BubuHaptics.success()
        } catch {
            errorText = "这段时光暂时没能收进：\(error.localizedDescription)"
        }
    }

    private func cancel(_ candidate: SSDIntakeCandidate) async {
        guard let service = makeIntakeService(env) else { return }
        workingID = candidate.id
        defer { workingID = nil }
        do {
            try await service.cancelIntakeCandidate(id: candidate.id)
            candidates.removeAll { $0.id == candidate.id }
        } catch {
            errorText = "这段候选暂时没能忽略：\(error.localizedDescription)"
        }
    }

    nonisolated private static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

@MainActor
private func makeIntakeService(_ env: AppEnvironment) -> BubuAIService? {
    guard env.config.isConfigured, let url = env.config.aiBaseURL else { return nil }
    return BubuAIService(baseURL: url) {
        try await env.apiClient.authenticate(role: "intake").token
    }
}

// MARK: - 保存健康度（独立子视图）
/// 只有这里观察 env.syncEngine——同步进度高频更新只重绘这一条，
/// 不再触发 CaptureHomeView 整页重算（U-P1-5）。
private struct SaveHealthStrip: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme

    private var theme: BubuThemeDefinition { env.theme.theme }
    private var homeSurface: Color {
        env.themedCard.opacity(colorScheme == .dark || env.isDarkTheme ? 0.92 : 0.94)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: env.syncEngine.pendingCount == 0 ? "checkmark.icloud.fill" : "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(env.syncEngine.pendingCount == 0 ? BubuTheme.Color.success : theme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("本地已保存")
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text(syncSummary)
                        .font(BubuTheme.Font.scaled(11))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                Spacer()
                // 直达同步中心，而不是设置根页——用户点「查看」是想看同步细节。
                NavigationLink { SyncCenterView() } label: {
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
                        .font(BubuTheme.Font.scaled(11, weight: .medium, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            if let notice = env.syncEngine.lastLargeFileNotice {
                Text(notice)
                    .font(BubuTheme.Font.scaled(11, weight: .regular, design: .rounded))
                    .foregroundStyle(theme.primary)
            } else if let soft = env.syncEngine.softNotice {
                Text(soft)
                    .font(BubuTheme.Font.scaled(11, weight: .regular, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            } else if let failure = env.syncEngine.lastFailureReason {
                // 原来这条只在「还有待同步项」时显示。可是最常见的失败恰恰是
                // 「连不上服务器」——此时没有待推项，家长只看到一句「离线」，
                // 完全不知道是家里断电了、还是自己没连 WiFi。原因一律浮出来。
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(BubuTheme.Font.scaled(10, weight: .bold))
                        .foregroundStyle(BubuTheme.Color.danger)
                        .padding(.top, 1)
                    Text(failure)
                        .font(BubuTheme.Font.scaled(11, weight: .regular, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button {
                        BubuHaptics.tapLight()
                        env.syncEngine.syncNow()
                    } label: {
                        Text("重试")
                            .font(BubuTheme.Font.scaled(11, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("立刻重试同步")
                }
            }
        }
        .animation(BubuMotion.gentle, value: env.syncEngine.lastFailureReason)
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
}
