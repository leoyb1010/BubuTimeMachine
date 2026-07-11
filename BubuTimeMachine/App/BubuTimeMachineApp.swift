import SwiftUI
import SwiftData
import UIKit

// MARK: - App 入口
/// @main：装配 ModelContainer（全部 @Model）+ 注入全局 AppEnvironment（DI）。
@main
struct BubuTimeMachineApp: App {
    /// SwiftData 容器：唯一真相源。包含第 2 章全部实体。
    let modelContainer: ModelContainer

    /// 全局依赖容器。@State 持有，保证生命周期与 App 一致。
    @State private var env = AppEnvironment()
    /// 桌面小组件 / 通知 deep link 路由。
    @State private var router = BubuRouter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let schema = Schema([
            Entry.self, Media.self, Milestone.self, FirstTime.self,
            TimeCapsule.self, VoiceMemo.self, Comment.self, GrowthMovie.self,
            FamilyMember.self, ChildProfile.self, VoiceNote.self, HealthRecord.self,
            FeedEvent.self, VaccineRecord.self, GrowthMeasurement.self,
            PendingDeletion.self
        ])
        // App Group：先把旧私有沙盒的 store/媒体一次性迁到共享容器（幂等、失败不删源），
        // 再让 ModelConfiguration 指向共享容器里的 store —— Widget/灵动岛等 extension 才能读到同一份数据。
        StorageMigrator.migrateIfNeeded()
        let config = ModelConfiguration(schema: schema, url: BubuStorage.storeURL)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("无法创建 SwiftData 容器：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .environment(router)
                .tint(env.theme.theme.primary)
                // 选了深色主题（星夜）就整 App 强制深色：动态色 token 统一翻到深色值，
                // 否则浅色系统下暗渐变底 + 深棕文字 = 全 App 不可读（R4 待核-星夜）
                .preferredColorScheme(env.theme.theme.isDark ? .dark : nil)
                .onOpenURL { router.handle($0) }
                .task {
                    #if DEBUG
                    seedForUITestingIfNeeded()
                    #endif
                    env.bootstrap(context: modelContainer.mainContext)
                    // 语音自动转写补写（端侧优先，尽力而为）：三年语音逐步变成可搜索文字
                    Task {
                        await VoiceTranscriber.backfill(
                            context: modelContainer.mainContext, mediaStore: env.mediaStore,
                            aiService: env.aiService, aiConfigured: env.config.isAIConfigured)
                    }
                    env.refreshWidgetSnapshot(context: modelContainer.mainContext)
                    WidgetRefresher.reload()
                    // 通知直接回复：注册「回一句」类目 + 通知代理
                    NotificationReplyHandler.shared.register()
                    consumePendingRecord()
                    // 手表连接：注入 App 正在用的 context（手表记录能让前台时光轴实时刷新）+ 激活 + 推初始快照 + 监听
                    WatchConnectivityManager.shared.appContext = modelContainer.mainContext
                    WatchConnectivityManager.shared.activate()
                    pushWatchSnapshot()
                    NotificationCenter.default.addObserver(
                        forName: WatchConnectivityManager.didRecordNotification,
                        object: nil, queue: .main) { _ in
                        Task { @MainActor in
                            env.syncEngine.syncNow()
                            env.refreshWidgetSnapshot(context: modelContainer.mainContext)
                            WidgetRefresher.reload()
                            pushWatchSnapshot()
                        }
                    }
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, phase in
            // 进后台停轮询省电；回前台立刻补一轮同步
            switch phase {
            case .active:
                env.syncEngine.start()
                env.refreshWidgetSnapshot(context: modelContainer.mainContext)
                WidgetRefresher.reload()
                pushWatchSnapshot()
                consumePendingRecord()
            case .background: env.syncEngine.stopPolling()
            default: break
            }
        }
    }

    /// 消费控制中心/Action Button 置的记录标志：拉起快速记录。
    @MainActor
    private func consumePendingRecord() {
        guard SharedDefaults.pendingRecord else { return }
        SharedDefaults.pendingRecord = false
        router.pendingQuickCapture = true
    }

    /// 读库生成概览快照并推给手表。
    @MainActor
    private func pushWatchSnapshot() {
        guard let snapshot = WatchSnapshotBuilder.make(context: modelContainer.mainContext,
                                                       role: env.config.currentRole) else { return }
        WatchConnectivityManager.shared.push(snapshot)
    }

    #if DEBUG
    /// 仅供截图/联调：以 `-uitest-seed` 启动时，注入一个布布档案 + 成员 + 几条记录，跳过引导。
    @MainActor
    private func seedForUITestingIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-uitest-seed") else { return }
        let context = modelContainer.mainContext
        let existing = (try? context.fetch(FetchDescriptor<ChildProfile>())) ?? []
        guard existing.isEmpty else { env.hasCompletedOnboarding = true; return }

        let birthday = Calendar.current.date(byAdding: .month, value: -19, to: .now) ?? .now
        let profile = ChildProfile(name: "布布", birthday: birthday)
        context.insert(profile)

        let mama = FamilyMember(name: "妈妈", relation: "妈妈", avatarEmoji: "👩", themeColorHex: "#F28C9E")
        mama.isPrimary = true
        context.insert(mama)
        let grandma = FamilyMember(name: "姥姥", relation: "姥姥", avatarEmoji: "👵", themeColorHex: "#F2B705")
        context.insert(grandma)

        let moods: [Mood] = [.happy, .curious, .proud, .sleepy]
        let notes = ["布布今天第一次自己扶着沙发站起来了！", "在公园看小鸟看了好久，眼睛亮亮的。",
                     "午睡醒来冲我笑，奶香奶香的。", "把积木叠到了三层，特别得意。"]
        for i in 0..<4 {
            let day = Calendar.current.date(byAdding: .day, value: -i * 9, to: .now) ?? .now
            let e = Entry(happenedAt: day, authorRole: i % 2 == 0 ? "妈妈" : "姥姥", note: notes[i])
            e.mood = moods[i]
            e.locationName = i == 1 ? "家附近的公园" : "家"
            context.insert(e)

            if let image = makeSeedImage(index: i),
               let data = image.jpegData(compressionQuality: 0.92),
               let fileName = try? env.mediaStore.savePhoto(data) {
                let media = Media(type: .photo, localFileName: fileName)
                media.width = Int(image.size.width)
                media.height = Int(image.size.height)
                media.thumbnailFileName = env.mediaStore.makePhotoThumbnail(fromImage: image)
                media.aiTags = [["微笑", "家", "玩具"], ["公园", "小鸟", "阳光"], ["午睡", "奶香", "笑脸"], ["积木", "成长", "高光"]][i]
                media.entry = e
                context.insert(media)
            }
        }

        for tpl in MilestoneTemplate.presets.prefix(6) {
            let m = Milestone(title: tpl.title, category: tpl.category, emoji: tpl.emoji)
            context.insert(m)
        }
        // 点亮一个
        if let walk = (try? context.fetch(FetchDescriptor<Milestone>()))?.first {
            walk.happenedAt = Calendar.current.date(byAdding: .day, value: -3, to: .now)
            walk.ageDescription = AgeCalculator.ageDescription(birthday: birthday, at: walk.happenedAt!)
        }

        seedHealthRecords(into: context)

        // 时间胶囊：一封已可开启（解锁时间在过去）、一封锁定中
        seedCapsule(into: context, title: "写给一岁的你",
                    letter: "亲爱的布布，今天你刚满一岁。你最爱笑，一笑全家都化了。等你看到这封信，已经长大啦。",
                    unlockAt: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now, emoji: "🎂")
        seedCapsule(into: context, title: "写给18岁的你",
                    letter: "等你十八岁，妈妈想对你说……（这封要到那天才能打开哦）",
                    unlockAt: Calendar.current.date(byAdding: .year, value: 17, to: .now) ?? .now, emoji: "🌟")

        try? context.save()
        env.currentMemberId = mama.id
        env.hasCompletedOnboarding = true
    }

    @MainActor
    private func seedCapsule(into context: ModelContext, title: String, letter: String, unlockAt: Date, emoji: String) {
        let capsule = TimeCapsule(title: title, fromRole: "妈妈", unlockAt: unlockAt)
        capsule.coverEmoji = emoji
        let payload = CapsulePayload(letter: letter)
        if let blob = try? env.vault.seal(payload, unlockAt: unlockAt, salt: capsule.id.uuidString) {
            capsule.encryptedBlobFileName = blob
            context.insert(capsule)
        }
    }

    @MainActor
    private func seedHealthRecords(into context: ModelContext) {
        let meal = HealthRecord(kind: .meal, title: "南瓜米糊 + 蛋黄")
        meal.amountText = "半碗"
        meal.reaction = "吃得很香"
        context.insert(meal)

        let sleep = HealthRecord(kind: .sleep, title: "午睡")
        sleep.amountText = "1 小时 40 分钟"
        sleep.reaction = "醒来心情很好"
        context.insert(sleep)

        let water = HealthRecord(kind: .water, title: "温水")
        water.amountText = "120ml"
        context.insert(water)
    }

    @MainActor
    private func makeSeedImage(index: Int) -> UIImage? {
        let size = CGSize(width: 1200, height: 1600)
        let colors: [(UIColor, UIColor)] = [
            (UIColor(red: 1.0, green: 0.70, blue: 0.74, alpha: 1), UIColor(red: 1.0, green: 0.90, blue: 0.76, alpha: 1)),
            (UIColor(red: 0.72, green: 0.88, blue: 1.0, alpha: 1), UIColor(red: 0.78, green: 0.95, blue: 0.78, alpha: 1)),
            (UIColor(red: 0.95, green: 0.82, blue: 1.0, alpha: 1), UIColor(red: 1.0, green: 0.92, blue: 0.82, alpha: 1)),
            (UIColor(red: 1.0, green: 0.82, blue: 0.62, alpha: 1), UIColor(red: 0.85, green: 0.92, blue: 1.0, alpha: 1))
        ]
        let pair = colors[index % colors.count]
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [pair.0.cgColor, pair.1.cgColor] as CFArray,
                                      locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])

            let circleColor = UIColor.white.withAlphaComponent(0.42)
            circleColor.setFill()
            cg.fillEllipse(in: CGRect(x: 150, y: 220, width: 900, height: 900))
            UIColor.white.withAlphaComponent(0.72).setFill()
            cg.fillEllipse(in: CGRect(x: 350, y: 430, width: 500, height: 500))

            let emoji = ["👶🏻", "🌳", "🧸", "🧱"][index % 4]
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 260),
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    return style
                }()
            ]
            emoji.draw(in: CGRect(x: 0, y: 520, width: size.width, height: 320), withAttributes: attrs)

            let title = ["布布的笑", "公园小鸟", "午睡醒来", "积木高高"][index % 4]
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 74, weight: .bold),
                .foregroundColor: UIColor(red: 0.36, green: 0.30, blue: 0.27, alpha: 1),
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    return style
                }()
            ]
            title.draw(in: CGRect(x: 80, y: 1040, width: size.width - 160, height: 110), withAttributes: textAttrs)
        }
    }
    #endif
}

// MARK: - 根视图：首启引导 or 主界面
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showWhatsNew = false

    var body: some View {
        if env.hasCompletedOnboarding {
            content
                .transition(.opacity)
                // 升级后首次启动：弹出本版更新内容（全新安装不弹；老用户升级会弹）。
                .task {
                    if WhatsNewGate.shouldPresent(isReturningUser: env.hasCompletedOnboarding) {
                        // 略等 UI 稳定再弹，避免与首页加载抢呈现。
                        try? await Task.sleep(for: .milliseconds(600))
                        showWhatsNew = true
                    }
                }
                .sheet(isPresented: $showWhatsNew) {
                    if let note = Changelog.latest {
                        WhatsNewSheet(note: note) { showWhatsNew = false }
                    }
                }
        } else {
            OnboardingView().transition(.opacity)
        }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitest-simple") {
            SimpleModeView()
        } else if ProcessInfo.processInfo.arguments.contains("-uitest-capture") {
            DebugQuickCapturePreviewView()
        } else if ProcessInfo.processInfo.arguments.contains("-uitest-timeline") {
            NavigationStack { TimelineView() }
        } else if ProcessInfo.processInfo.arguments.contains("-uitest-ai") {
            NavigationStack { AIStudioHomeView() }
        } else if ProcessInfo.processInfo.arguments.contains("-uitest-movie") {
            NavigationStack { GrowthMovieView() }
        } else if ProcessInfo.processInfo.arguments.contains("-uitest-report") {
            NavigationStack { GrowthReportView() }
        } else if ProcessInfo.processInfo.arguments.contains("-uitest-settings") {
            NavigationStack { SettingsView() }
        } else if ProcessInfo.processInfo.arguments.contains("-uitest-voice") {
            NavigationStack { VoiceArchiveView() }
        } else if ProcessInfo.processInfo.arguments.contains("-uitest-export") {
            NavigationStack { ExportView() }
        } else {
            mainOrSimple
        }
        #else
        mainOrSimple
        #endif
    }

    /// 身份决定界面：长辈（或手动开启）→ 简单模式；否则完整 App。
    @ViewBuilder
    private var mainOrSimple: some View {
        if env.config.simpleModeEnabled {
            SimpleModeView().transition(.opacity)
        } else {
            RootTabView().transition(.opacity)
        }
    }
}
