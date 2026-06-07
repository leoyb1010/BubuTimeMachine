import SwiftUI

// MARK: - 根导航
/// 5 个 Tab（姥姥首选第 1 个即可完成一切）。设置藏入右上角齿轮，保持首屏极简。
struct RootTabView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                CaptureHomeView()
                    .navigationDestination(for: Entry.self) { EntryDetailView(entry: $0) }
            }
            .tabItem { Label("记录此刻", systemImage: "heart.circle.fill") }
            .tag(0)

            NavigationStack {
                TimelineView()
            }
            .tabItem { Label("时光轴", systemImage: "clock.fill") }
            .tag(1)

            NavigationStack {
                MilestonesHomeView()
            }
            .tabItem { Label("里程碑", systemImage: "star.fill") }
            .tag(2)

            NavigationStack {
                AIStudioHomeView()
            }
            .tabItem { Label("AI 工坊", systemImage: "wand.and.stars") }
            .tag(3)

            NavigationStack {
                CapsuleHomeView()
            }
            .tabItem { Label("时间胶囊", systemImage: "envelope.fill") }
            .tag(4)
        }
        .tint(env.theme.theme.primary)
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
