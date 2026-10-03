import SwiftUI

@main
struct BubuWatchApp: App {
    @State private var connector = WatchConnector()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(connector)
                .modifier(WatchReadingPreviewOverrides())
                .task { connector.activate() }
        }
        // 进前台对账：补发缓存记录 + 重发上次失败/未激活遗留的待传语音（P0-2 / W-P1-1）。
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { connector.reconcilePending() }
        }
    }
}

enum WatchReadingRoute: Hashable { case memories, recent, story(WatchMemory) }

// MARK: - 只读导航：主页 → 回忆 / 最近，系统返回与表冠各司其职。
struct WatchRootView: View {
    @State private var path = WatchRootView.initialPath

    /// 模拟器截图核验用：`-watch-tab N` 直达第 N 页（手表 UI 无法脚本点击）。仅 DEBUG。
    private static var initialPath: [WatchReadingRoute] {
        #if DEBUG
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-watch-tab"),
           i + 1 < ProcessInfo.processInfo.arguments.count,
           let tab = Int(ProcessInfo.processInfo.arguments[i + 1]) {
            return tab == 1 ? [.memories] : ([2, 4].contains(tab) ? [.recent] : [])
        }
        #endif
        return []
    }

    var body: some View {
        NavigationStack(path: $path) {
            WatchOverviewView()
                .navigationDestination(for: WatchReadingRoute.self) { route in
                    switch route {
                    case .memories: WatchTimeMachineView()
                    case .recent: WatchRecentView()
                    case .story(let memory): WatchStoryView(memory: memory)
                    }
                }
        }
        .tint(WatchTheme.rose)
        .onOpenURL { url in
            guard url.scheme == "bubuwatch" else { return }
            switch url.host {
            case "timemachine", "memories": path = [.memories]
            case "recent": path = [.recent]
            // Old complications may still link to record; open the read-only home.
            case "overview", "record": path = []
            default: break
            }
        }
    }
}

// MARK: - 手表配色（与 App 马卡龙一致，深底适配表盘）
enum WatchTheme {
    static let rose = Color(red: 0.95, green: 0.52, blue: 0.66)
    static let deepRose = Color(red: 0.90, green: 0.42, blue: 0.56)
    static let mint = Color(red: 0.46, green: 0.78, blue: 0.55)
    static let sky = Color(red: 0.50, green: 0.68, blue: 0.92)
    static let butter = Color(red: 1.0, green: 0.80, blue: 0.42)
    static let lav = Color(red: 0.72, green: 0.66, blue: 0.95)
}
