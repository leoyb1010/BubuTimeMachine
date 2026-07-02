import SwiftUI

// MARK: - 根导航
/// 4 个页面 Tab + 中央记录键。时间胶囊收入「布布的魔法屋」，底栏保持轻量。
struct RootTabView: View {
    @Environment(AppEnvironment.self) private var env
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
            #endif
        }
    }

    private var tabBarSpacer: some View {
        Color.clear
            .frame(height: 92)
            .allowsHitTesting(false)
    }
}
