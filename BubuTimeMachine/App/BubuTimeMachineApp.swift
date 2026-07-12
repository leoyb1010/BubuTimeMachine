import SwiftUI
import TipKit
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
    /// 启动期注册（通知回复 / BGTask handler / WC 激活）前移到这里：后台冷启动也必定执行。
    @UIApplicationDelegateAdaptor(BubuAppDelegate.self) private var appDelegate

    /// 只做一次的启动装配防重（iPad 多窗口下每个 scene 都会跑一遍 .task）。
    @State private var didWireLaunchTasks = false
    /// 手表记录观察者 token：留存不丢弃（原代码直接丢弃，且每个 scene 重复注册）。
    @State private var syncObserver: NSObjectProtocol?

    init() {
        // schema 唯一真相源：版本化 BubuSchemaV1（与 Widget/Intent 完全一致）
        let schema = SharedModelContainer.schema
        // App Group：先【同步】把旧私有沙盒的 store 三件套迁到共享容器（小、幂等、失败不删源），
        // 再让 ModelConfiguration 指向共享容器里的 store —— Widget/灵动岛等 extension 才能读到同一份数据。
        // 媒体库（可能几 GB）不在 init 里搬——它改到 .task 后台执行（migrateMediaIfNeeded），
        // 避免大库用户升级时主线程同步拷贝超过启动看门狗被 0x8badf00d 强杀。
        StorageMigrator.migrateStoreIfNeeded()
        let config = ModelConfiguration(schema: schema, url: BubuStorage.storeURL)
        do {
            modelContainer = try ModelContainer(for: schema, migrationPlan: BubuMigrationPlan.self,
                                                configurations: [config])
            BubuStoreHealth.markHealthy()
        } catch {
            // 数据保护模式（R4 G-3）：以前这里 fatalError——升级迁移一旦失败，
            // 全家的 30 年数据直接锁死打不开。现在改为：磁盘 store 原样保留（绝不动它），
            // App 以内存容器运行并在设置页明确提示，等待修复/导出。
            BubuStoreHealth.markFailed()
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [memory])
            } catch {
                fatalError("无法创建 SwiftData 容器（连内存容器都失败）：\(error)")
            }
        }
        // 进程内统一容器：把 App 真正在用的容器（磁盘或内存兜底）注入共享入口，
        // 让 App Intents / 通知回复 / 手表写入都经它拿到同一个容器——写入能刷新主 UI、
        // 快照读到最新数据。注入时机足够早（App.init），且 extension 是独立进程、天然拿不到它。
        SharedModelContainer.injected = modelContainer
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
                    // 只做一次的启动装配（多窗口下 .task 每个 scene 都会跑，需防重）。
                    // 注意：NotificationReplyHandler / BGTask handler / WC 激活已前移到 BubuAppDelegate，
                    // 保证后台冷启动也执行；这里只保留必须在 env/container 就绪后做的部分。
                    if !didWireLaunchTasks {
                        didWireLaunchTasks = true
                        // 媒体库（Media/Thumbnails，老用户可能几 GB）从旧沙盒搬到 App Group 共享容器：
                        // 放到后台 detached 任务，绝不阻塞首帧/卡启动看门狗。迁移是拷贝不删源，
                        // 迁移窗口内 MediaStore 读取会自动回退旧目录，绝不白图。失败下次启动再补。
                        Task.detached(priority: .utility) {
                            StorageMigrator.migrateMediaIfNeeded()
                        }
                        try? Tips.configure()   // 渐进式功能引导（H-3）
                        env.bootstrap(context: modelContainer.mainContext)
                        // env 就绪后注入后台补拉 runner（handler 已在 AppDelegate 注册）：
                        // syncOnce() 会 await 到一轮同步真正跑完，BGTask 才能如实 setTaskCompleted。
                        BackgroundRefresher.setRunner { await env.syncEngine.syncOnce() }
                        Task { await BackupReminder.scheduleIfAuthorized() }   // 备份提醒（G-6）
                        // 语音自动转写补写（端侧优先，尽力而为）：三年语音逐步变成可搜索文字
                        Task {
                            await VoiceTranscriber.backfill(
                                context: modelContainer.mainContext, mediaStore: env.mediaStore,
                                aiService: env.aiService, aiConfigured: env.config.isAIConfigured)
                        }
                        // 手表记录 → 立即同步 + 刷新。观察者只注册一次，token 留存不丢弃。
                        syncObserver = NotificationCenter.default.addObserver(
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
                    // 每次场景出现都要做的：手表上下文注入 + 小组件快照 + 消费待办 + 推手表快照。
                    WatchConnectivityManager.shared.appContext = modelContainer.mainContext
                    WatchConnectivityManager.shared.retryPendingVoiceImports()   // 重试上次导入失败的手表语音（W-P1-3）
                    env.refreshWidgetSnapshot(context: modelContainer.mainContext)
                    WidgetRefresher.reload()
                    consumePendingRecord()
                    pushWatchSnapshot()
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, phase in
            // 进后台停轮询省电；回前台立刻补一轮同步
            switch phase {
            case .active:
                env.syncEngine.start()
                WatchConnectivityManager.shared.retryPendingVoiceImports()   // 进前台重试手表语音应急导入（W-P1-3）
                env.refreshWidgetSnapshot(context: modelContainer.mainContext)
                WidgetRefresher.reload()
                pushWatchSnapshot()
                consumePendingRecord()
            case .background:
                env.syncEngine.stopPolling()
                BackgroundRefresher.scheduleNext()   // 系统择机唤醒补一轮同步
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
        rootContent
            // 全 App Dynamic Type 兜底基线：老人把系统字体开到最大无障碍档时，先统一夹到
            // accessibility3，避免布局爆裂。这是较宽的上限，专给以大按钮/单列布局为主、
            // 抗放大能力强的 SimpleMode（老人模式）与引导页用；密集的 RootTabView 会在其内部
            // 再收紧到 accessibility1（见 RootTabView）。外松内紧：内层更严的夹取会生效。
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    @ViewBuilder
    private var rootContent: some View {
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
        } else if ProcessInfo.processInfo.arguments.contains("-uitest-capsule") {
            NavigationStack { CapsuleHomeView() }
        } else if ProcessInfo.processInfo.arguments.contains("-uitest-growth") {
            NavigationStack { GrowthCurveView() }
        } else if ProcessInfo.processInfo.arguments.contains("-uitest-diary") {
            NavigationStack { FirstPersonDiaryView() }
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
