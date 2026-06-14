import SwiftUI

// MARK: - 根导航
/// 5 个 Tab（姥姥首选第 1 个即可完成一切）。设置藏入右上角齿轮，保持首屏极简。
struct RootTabView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                NavigationStack {
                    // Entry 详情的 navigationDestination 已下沉到 CaptureHomeView，
                    // 以便与该页的 zoomNS 配对实现缩放共享元素转场。
                    CaptureHomeView(openTimeline: { selection = 1 })
                }
                .tabItem { Label("记录此刻", systemImage: "heart.circle.fill") }
                .tag(0)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack {
                    TimelineView()
                        .safeAreaPadding(.bottom, 84)
                }
                .tabItem { Label("时光", systemImage: "clock.fill") }
                .tag(1)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack {
                    MilestonesHomeView()
                        .safeAreaPadding(.bottom, 84)
                }
                .tabItem { Label("里程碑", systemImage: "star.fill") }
                .tag(2)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack {
                    AIStudioHomeView()
                        .safeAreaPadding(.bottom, 84)
                }
                .tabItem { Label("布布的故事", systemImage: "wand.and.stars.inverse") }
                .tag(3)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack {
                    CapsuleHomeView()
                        .safeAreaPadding(.bottom, 84)
                }
                .tabItem { Label("时间胶囊", systemImage: "envelope.fill") }
                .tag(4)
                .toolbar(.hidden, for: .tabBar)
            }
            .tint(env.theme.theme.tabTint)

            // 奶油马卡龙玻璃胶囊底栏（外观替换，路由仍由 selection 驱动，跳转逻辑不变）
            BubuGlassTabBar(selection: $selection, tint: env.theme.theme.primary, onCenterTap: {})
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            #if DEBUG
            if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-uitest-tab"),
               i + 1 < ProcessInfo.processInfo.arguments.count,
               let t = Int(ProcessInfo.processInfo.arguments[i + 1]) {
                selection = t
            }
            #endif
        }
    }
}
