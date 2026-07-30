import SwiftUI

@main
struct BubuWatchApp: App {
    @State private var connector = WatchConnector()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(connector)
                .task { connector.activate() }
        }
        // 进前台对账：补发缓存记录 + 重发上次失败/未激活遗留的待传语音（P0-2 / W-P1-1）。
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { connector.reconcilePending() }
        }
    }
}

// MARK: - 根导航（纵向分页：概览 / 时光机 / 记录 / 打卡 / 最近）
struct WatchRootView: View {
    @Environment(WatchConnector.self) private var connector
    @State private var selection = WatchRootView.initialTab

    /// 模拟器截图核验用：`-watch-tab N` 直达第 N 页（手表 UI 无法脚本点击）。仅 DEBUG。
    private static var initialTab: Int {
        #if DEBUG
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-watch-tab"),
           i + 1 < ProcessInfo.processInfo.arguments.count,
           let tab = Int(ProcessInfo.processInfo.arguments[i + 1]) {
            return tab
        }
        #endif
        return 0
    }

    var body: some View {
        TabView(selection: $selection) {
            WatchOverviewView().tag(0)
            WatchTimeMachineView().tag(1)   // 表冠时光机：拧表冠穿越回忆
            WatchRecordView().tag(2)
            WatchQuickLogView().tag(3)
            WatchRecentView().tag(4)
        }
        .tabViewStyle(.verticalPage)
        .overlay(alignment: .top) {
            if let label = connector.lastSentLabel {
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(WatchTheme.rose, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: connector.lastSentLabel)
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
