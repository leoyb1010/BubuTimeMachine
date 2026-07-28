import SwiftUI

// MARK: - 根导航
/// 4 个页面 Tab + 中央记录键。时间胶囊收入「布布的魔法屋」，底栏保持轻量。
struct RootTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(BubuRouter.self) private var router
    @State private var selection = 0
    @State private var quickCaptureTrigger = 0
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// 宽屏（iPad 全屏/半屏）走侧栏，窄屏（iPhone 全部场景 + iPad 1/3 分屏）走原底栏。
    /// 判断依据必须是 sizeClass 而非设备类型——分屏变窄要能自动退回手机布局。
    private var isWide: Bool { BubuAdaptive.isWide(sizeClass) }

    var body: some View {
        Group {
            if isWide { splitLayout } else { tabLayout }
        }
        // 完整版 App 的 Dynamic Type 上限：4 Tab + 卡片 + 玻璃底栏属密集布局，
        // 收紧到 accessibility1（无障碍档中最小的一档，body 已约 1.6×）——在「字尽量大」与
        // 「不破版」之间取的保守安全档；younger 家人才走完整版，极端无障碍档少见。
        // 老人主要走 SimpleMode，其上限在 RootView 放宽到 accessibility3。
        // iPad 外接键盘快捷键：⌘1–4 切页、⌘N 记一笔。窄屏无键盘时这些按钮不显示、零成本。
        .background {
            Group {
                Button("") { selection = 0 }.keyboardShortcut("1", modifiers: .command)
                Button("") { selection = 1 }.keyboardShortcut("2", modifiers: .command)
                Button("") { selection = 2 }.keyboardShortcut("3", modifiers: .command)
                Button("") { selection = 3 }.keyboardShortcut("4", modifiers: .command)
                Button("") { selection = 0; quickCaptureTrigger += 1 }
                    .keyboardShortcut("n", modifiers: .command)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .ignoresSafeArea(.keyboard)
        .onAppear {
            #if DEBUG
            if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-uitest-tab"),
               i + 1 < ProcessInfo.processInfo.arguments.count,
               let t = Int(ProcessInfo.processInfo.arguments[i + 1]) {
                selection = min(max(t, 0), 3)
            }
            // 联调：-uitest-openurl bubu://moment 直接走深链路由，绕过系统 openurl 确认框。
            if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-uitest-openurl"),
               i + 1 < ProcessInfo.processInfo.arguments.count,
               let url = URL(string: ProcessInfo.processInfo.arguments[i + 1]) {
                router.handle(url)
            }
            #endif
            consumePendingRoute()
        }
        // 小组件点击时 App 已在前台的情况：onOpenURL 更新 pendingTab，这里响应切 Tab。
        .onChange(of: router.pendingTab) { _, _ in consumePendingRoute() }
        // 控制中心/Action Button 在 App 已运行时只置 pendingQuickCapture 不动 pendingTab：
        // 必须单独监听，否则不拉起面板、残留标志还会在之后点小组件时误弹（R4 P2-38）
        .onChange(of: router.pendingQuickCapture) { _, _ in consumePendingRoute() }
    }


    // MARK: 宽屏：侧栏 + 详情列
    //
    // 侧栏替代的是【底栏】，页面整体进详情列——列表与详情仍在同一个 NavigationStack 内，
    // 所以缩略图进详情的 zoom 共享元素转场在 iPad 上照常工作（不必像通常的双栏那样牺牲它）。
    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: Binding(get: { Optional(selection) },
                                    set: { if let v = $0 { selection = v } })) {
                Section {
                    sidebarRow(0, "首页", "house.fill")
                    sidebarRow(1, "时光", "clock.fill")
                    sidebarRow(2, "里程碑", "star.fill")
                    sidebarRow(3, "魔法屋", "wand.and.stars.inverse")
                }
                Section {
                    Button {
                        selection = 0
                        quickCaptureTrigger += 1
                    } label: {
                        Label("记一笔", systemImage: "plus.circle.fill")
                            .foregroundStyle(env.theme.theme.primary)
                            .font(BubuTheme.Font.body.weight(.semibold))
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("布布")
            .scrollContentBackground(.hidden)
            .background(BubuTheme.Color.background.ignoresSafeArea())
        } detail: {
            NavigationStack {
                switch selection {
                case 1: TimelineView()
                case 2: MilestonesHomeView()
                case 3: AIStudioHomeView()
                default:
                    CaptureHomeView(openTimeline: { selection = 1 },
                                    quickCaptureTrigger: quickCaptureTrigger)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func sidebarRow(_ tag: Int, _ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(BubuTheme.Font.body)
            .tag(tag)
    }

    // MARK: 窄屏：原有 Tab + 玻璃底栏（iPhone 一个像素不变）
    private var tabLayout: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                NavigationStack {
                    // Entry 详情的 navigationDestination 已下沉到 CaptureHomeView，
                    // 以便与该页的 zoomNS 配对实现缩放共享元素转场。
                    CaptureHomeView(openTimeline: { selection = 1 },
                                    quickCaptureTrigger: quickCaptureTrigger)
                }
                .safeAreaInset(edge: .bottom) { tabBarSpacer }
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(0)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack {
                    TimelineView()
                }
                .safeAreaInset(edge: .bottom) { tabBarSpacer }
                .tabItem { Label("时光", systemImage: "clock.fill") }
                .tag(1)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack {
                    MilestonesHomeView()
                }
                .safeAreaInset(edge: .bottom) { tabBarSpacer }
                .tabItem { Label("里程碑", systemImage: "star.fill") }
                .tag(2)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack {
                    AIStudioHomeView()
                }
                .safeAreaInset(edge: .bottom) { tabBarSpacer }
                .tabItem { Label("魔法屋", systemImage: "wand.and.stars.inverse") }
                .tag(3)
                .toolbar(.hidden, for: .tabBar)
            }
            .tint(env.theme.theme.tabTint)
            BubuGlassTabBar(selection: $selection, tint: env.theme.theme.primary) {
                selection = 0
                quickCaptureTrigger += 1
            }
        }
    }

    /// 消费一次待处理的深链目标 Tab / 快速记录信号（消费后置回，避免重复触发）。
    private func consumePendingRoute() {
        if let tab = router.pendingTab {
            selection = min(max(tab, 0), 3)
            router.pendingTab = nil
        }
        if router.pendingQuickCapture {
            selection = 0
            router.pendingQuickCapture = false
            // 延迟一拍：确保首页已切换并注册好 onChange 监听后再拉起记录（冷启动 deep link 时机安全）。
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                quickCaptureTrigger += 1
            }
        }
    }

    private var tabBarSpacer: some View {
        Color.clear
            .frame(height: 92)
            .allowsHitTesting(false)
    }
}
