import SwiftUI
import SwiftData

// MARK: - 根导航
/// iPhone 使用系统 Liquid Glass Tab；iPad/可调整宽窗口由 sidebarAdaptable 自动切成侧栏。
/// 记录不是第五个页面，而是跨页面一直可用的底部附件/侧栏动作。
struct RootTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(BubuRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection = 0
    @State private var quickCaptureTrigger = 0
    @State private var timelinePath: [UUID] = []
    /// 首页以外的 Tab 点「记录此刻」时，就地弹出记录面板，不再把人拽回首页。
    @State private var rootCapture: CaptureModel?
    @State private var captureToast: BubuToastState?

    private var isWide: Bool { BubuAdaptive.isWide(sizeClass) }

    init() { _ = Self.navigationTitleAppearance }

    /// 导航标题统一暖棕（系统默认纯黑/纯白和奶油底、马卡龙卡片不搭）。
    /// 只改标题文字属性，不碰导航栏背景，Liquid Glass 材质保持系统默认。
    private static let navigationTitleAppearance: Void = {
        let bar = UINavigationBar.appearance()
        bar.titleTextAttributes = [.foregroundColor: BubuTheme.Color.warmBrownUIColor]
        bar.largeTitleTextAttributes = [.foregroundColor: BubuTheme.Color.warmBrownUIColor]
    }()

    /// 每日学习是独立入口；用独立 tag，避免改动已有 0~4 的直达参数。
    static let learningTab = 5

    private var maximumSelectableTab: Int {
        #if targetEnvironment(macCatalyst)
        4
        #else
        3
        #endif
    }

    var body: some View {
        // 幼儿园 Tab 以前藏起系统底栏、换成自绘平底栏：图标、材质、高度都和其他页不同，
        // 还丢了「记录此刻」附件和 VoiceOver 的标签栏语义。现在每个 Tab 都用同一条系统 Liquid Glass 底栏。
        tabsWithRecordAccessory
            // 切 Tab 此前手上没有任何回音：内容过渡做了、记录按钮的轻触做了，
            // 唯独最高频的这个动作是哑的。bubuSensoryFeedback 全仓只用了 2 处，严重低用。
            .bubuSensoryFeedback(.selection, trigger: selection)
            .tabViewStyle(.sidebarAdaptable)
            // 页面入口必须始终可直接选择；自动收缩会把当前 Tab 与记录附件
            // 合成紧凑底栏，跨页面/关闭记录后可能无法恢复完整导航。
            .tabBarMinimizeBehavior(.never)
            .tabViewSidebarHeader {
                Label("布布时光机", systemImage: "book.pages.fill")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(env.theme.theme.textAccent)
                    .padding(.vertical, 8)
            }
            .tabViewSidebarBottomBar {
                if isWide {
                    Button(action: openQuickCapture) {
                        Label(BubuTheme.Copy.recordNow, systemImage: "plus.circle.fill")
                            .font(BubuTheme.Font.body.weight(.semibold))
                            .foregroundStyle(env.theme.theme.textAccent)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("root.record")
                }
            }
            .onChange(of: isWide) { _, wide in
                // 档案馆只在宽屏侧栏出现；学习（tag 5）在所有宽度都可用。
                if !wide && selection == 4 { selection = 1 }
            }
            .background { keyboardShortcuts }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            // 全 App 统一圆体：散落的 .caption / .system(size:) 也随设计语言变圆润。
            .fontDesign(.rounded)
            // 开发语言已是 zh-Hans；这里再兜底一次，日期选择器/格式化在任何设备地区下都显示中文月份。
            .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
            // 第一次连上家庭服务时，先说明第二大脑如何整理内容，再展示回忆、时光与学习。
            .secondBrainConsent(active: BubuLearningClient(env: env) != nil && !OnlineTimelineView.skipsConsentForUITest)
            .ignoresSafeArea(.keyboard)
            .onAppear {
                #if DEBUG
                if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-uitest-tab"),
                   i + 1 < ProcessInfo.processInfo.arguments.count,
                   let tab = Int(ProcessInfo.processInfo.arguments[i + 1]) {
                    selection = tab == Self.learningTab ? tab : min(max(tab, 0), maximumSelectableTab)
                }
                if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-uitest-openurl"),
                   i + 1 < ProcessInfo.processInfo.arguments.count,
                   let url = URL(string: ProcessInfo.processInfo.arguments[i + 1]) {
                    router.handle(url)
                }
                if ProcessInfo.processInfo.arguments.contains("-uitest-open-first-moment") {
                    openFirstMomentForUITest()
                }
                #endif
                consumePendingRoute()
            }
            .onChange(of: router.pendingTab) { _, _ in consumePendingRoute() }
            .onChange(of: router.pendingQuickCapture) { _, _ in consumePendingRoute() }
            .onChange(of: router.pendingEntryID) { _, _ in openPendingTimelineEntryIfReady() }
            .sheet(item: Binding(get: { router.pendingAsk.map(PendingAsk.init) }, set: { _ in router.pendingAsk = nil })) { ask in
                NavigationStack {
                    AskBubuView(initialQuestion: ask.question)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { router.pendingAsk = nil } } }
                }
            }
            .onChange(of: selection) { _, tab in
                if tab == 1 { openPendingTimelineEntryIfReady() }
            }
            .sheet(isPresented: Binding(get: { rootCapture?.showQuickCapture ?? false },
                                        set: { rootCapture?.showQuickCapture = $0 })) {
                if let rootCapture { QuickCaptureSheet(model: rootCapture) }
            }
            .onChange(of: rootCapture?.savedFlash) { _, flashed in
                if flashed == true {
                    captureToast = BubuToastState(message: BubuTheme.Copy.savedLocally, systemImage: "checkmark.circle.fill")
                }
            }
            .alert("部分照片没导入", isPresented: Binding(
                get: { rootCapture?.partialSaveWarning != nil },
                set: { if !$0 { rootCapture?.partialSaveWarning = nil } })) {
                Button("好") { rootCapture?.partialSaveWarning = nil }
            } message: {
                Text(rootCapture?.partialSaveWarning ?? "")
            }
            .bubuToast($captureToast)
    }

    @ViewBuilder
    private var tabsWithRecordAccessory: some View {
        if #available(iOS 26.1, *) {
            tabs.tabViewBottomAccessory(isEnabled: !isWide) {
                BubuRecordAccessory { openQuickCapture() }
            }
        } else if !isWide {
            tabs.tabViewBottomAccessory {
                BubuRecordAccessory { openQuickCapture() }
            }
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab("首页", systemImage: "house.fill", value: 0) {
                NavigationStack {
                    CaptureHomeView(openTimeline: { selection = 1 },
                                    quickCaptureTrigger: quickCaptureTrigger)
                }
            }

            Tab("时光", systemImage: "clock.fill", value: 1) {
                NavigationStack(path: $timelinePath) {
                    OnlineTimelineView()
                        .onAppear { openPendingTimelineEntryIfReady() }
                        // 通知/小组件/搜索直达的家人记录仍可打开，但不再作为时光主列表。
                        .navigationDestination(for: UUID.self) { TimelineEntryDestination(entryID: $0) }
                }
            }

            Tab("学习", systemImage: "graduationcap.fill", value: Self.learningTab) {
                NavigationStack { DailyLearningHomeView() }
            }

            Tab("成长", systemImage: "chart.xyaxis.line", value: 2) {
                NavigationStack { GrowthHomeView() }
            }

            Tab("幼儿园", systemImage: "house.lodge.fill", value: 3) {
                NavigationStack { MemoryJournalView() }
            }

            #if targetEnvironment(macCatalyst)
            Tab("档案馆", systemImage: "archivebox.fill", value: 4) {
                NavigationStack { MacArchiveWorkspaceView() }
            }
            #endif
        }
        .tint(env.theme.theme.tabTint)
        .accessibilityIdentifier("root.tabs")
    }

    private var keyboardShortcuts: some View {
        Group {
            // ⌘ 数字与视觉顺序一致：首页、时光、学习、成长、幼儿园（Mac 再加档案馆）。
            Button("") { selection = 0 }.keyboardShortcut("1", modifiers: .command)
            Button("") { selection = 1 }.keyboardShortcut("2", modifiers: .command)
            Button("") { selection = Self.learningTab }.keyboardShortcut("3", modifiers: .command)
            Button("") { selection = 2 }.keyboardShortcut("4", modifiers: .command)
            Button("") { selection = 3 }.keyboardShortcut("5", modifiers: .command)
            #if targetEnvironment(macCatalyst)
            Button("") { selection = 4 }.keyboardShortcut("6", modifiers: .command)
            #endif
            Button("") { openQuickCapture() }.keyboardShortcut("n", modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// 在哪个 Tab 点，就在哪个 Tab 上弹记录面板。首页仍交给首页自己的面板
    /// （保存后的「第一次」识别、首页贴纸都挂在那里）；其余页面用根部面板，不切 Tab。
    private func openQuickCapture() {
        if selection == 0 {
            quickCaptureTrigger += 1
        } else {
            presentRootCapture()
        }
        BubuHaptics.tapLight()
    }

    private func presentRootCapture() {
        if rootCapture == nil {
            rootCapture = CaptureModel(mediaStore: env.mediaStore, analyzer: env.photoAnalyzer,
                                       role: env.config.currentRole)
        }
        rootCapture?.role = env.config.currentRole
        rootCapture?.startQuickCapture()
    }

    private func consumePendingRoute() {
        if let tab = router.pendingTab {
            selection = tab == Self.learningTab ? tab : min(max(tab, 0), maximumSelectableTab)
            router.pendingTab = nil
        }
        if router.pendingEntryID != nil {
            selection = 1
            // 具体详情必须等时光 NavigationStack 真正出现并注册 destination 后再推入。
            // 冷启动时在这里立刻写 path 会得到一帧没有 destination 的白屏。
        }
        if router.pendingQuickCapture {
            // Siri / 小组件 / 控制中心：冷启动时首页可能还没挂载，统一走根部面板，
            // 不切 Tab、不等 350ms。
            router.pendingQuickCapture = false
            presentRootCapture()
        }
    }

    private func openPendingTimelineEntryIfReady() {
        guard selection == 1, let entryID = router.pendingEntryID else { return }
        router.pendingEntryID = nil
        Task { @MainActor in
            // 原生 Tab 切换与 NavigationStack 挂载分两次 transaction；等它完成后再导航。
            try? await Task.sleep(for: .milliseconds(650))
            guard selection == 1 else { return }
            timelinePath = [entryID]
        }
    }

    #if DEBUG
    private func openFirstMomentForUITest() {
        Task { @MainActor in
            // App 外层 .task 会先注入测试种子；这里略等一拍后从真实 SwiftData 取 id，
            // 因此测试不依赖模拟器是否残留上一轮随机 UUID。
            try? await Task.sleep(for: .milliseconds(500))
            var descriptor = FetchDescriptor<Entry>(
                predicate: #Predicate { !$0.isArchived },
                sortBy: [SortDescriptor(\Entry.happenedAt, order: .reverse)])
            descriptor.fetchLimit = 1
            guard let entryID = try? modelContext.fetch(descriptor).first?.id else { return }
            router.pendingTab = 1
            router.pendingEntryID = entryID
        }
    }
    #endif
}

/// 系统底部附件会在 Tab 展开/收缩间变形；内容跟随 placement 调整，避免压缩时塞两行文字。
private struct BubuRecordAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(AppEnvironment.self) private var env
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(BubuTheme.Font.scaled(20, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, env.theme.theme.actionFill)
                // 一行字，用 .primary/.secondary 让玻璃的 vibrancy 随底下内容自适应：
                // 固定暖棕压在照片上时对比度只有 2:1 左右。副标题已移到记录面板里。
                if placement == .expanded {
                    Text(BubuTheme.Copy.recordNow)
                        .font(BubuTheme.Font.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(BubuTheme.Font.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("记录")
                        .font(BubuTheme.Font.caption.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: placement == .expanded ? .infinity : nil,
                   minHeight: placement == .expanded ? 44 : 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("root.record")
        .accessibilityLabel("记录此刻")
    }
}

private struct PendingAsk: Identifiable {
    let question: String
    var id: String { question }
}
