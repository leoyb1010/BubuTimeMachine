import SwiftUI

// MARK: - 根导航
/// 5 个 Tab（姥姥首选第 1 个即可完成一切）。设置藏入右上角齿轮，保持首屏极简。
struct RootTabView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        TabView {
            NavigationStack {
                CaptureHomeView()
                    .navigationDestination(for: Entry.self) { EntryDetailView(entry: $0) }
            }
            .tabItem { Label("记录此刻", systemImage: "heart.circle.fill") }

            NavigationStack {
                TimelineView()
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
        .tint(env.theme.theme.primary)
    }
}
