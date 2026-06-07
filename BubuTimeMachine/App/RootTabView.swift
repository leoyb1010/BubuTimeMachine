import SwiftUI

// MARK: - 根导航
/// 5 个 Tab（姥姥首选第 1 个即可完成一切）。设置藏入时光轴右上角齿轮，保持首屏极简。
struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                CaptureHomeView()
            }
            .tabItem { Label("记录此刻", systemImage: "heart.circle.fill") }

            NavigationStack {
                TimelineView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink {
                                SettingsView()
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
            }
            .tabItem { Label("时光轴", systemImage: "clock.fill") }

            NavigationStack {
                MilestonesHomeView()
            }
            .tabItem { Label("里程碑", systemImage: "star.fill") }

            NavigationStack {
                AIStudioHomeView()
            }
            .tabItem { Label("AI 工坊", systemImage: "wand.and.stars") }

            NavigationStack {
                CapsuleHomeView()
            }
            .tabItem { Label("时间胶囊", systemImage: "envelope.fill") }
        }
        .tint(BubuTheme.Color.primary)
    }
}
