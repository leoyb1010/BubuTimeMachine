import SwiftUI

// MARK: - 根导航
/// 4 个页面 Tab + 中央记录键。时间胶囊收入「布布的魔法屋」，底栏保持轻量。
struct RootTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(BubuRouter.self) private var router
    @State private var selection = 0
    @State private var quickCaptureTrigger = 0

    var body: some View {
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

            // 奶油马卡龙玻璃胶囊底栏（外观替换，路由仍由 selection 驱动，跳转逻辑不变）
            BubuGlassTabBar(selection: $selection, tint: env.theme.theme.primary) {
                selection = 0
                quickCaptureTrigger += 1
            }
        }
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
