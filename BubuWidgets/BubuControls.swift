import WidgetKit
import SwiftUI
import AppIntents

// MARK: - 控制中心 / 锁屏 / Action Button 控件
/// iOS 18+ ControlWidget：一个「记录布布」按钮，可放进控制中心、锁屏，或绑定到 Action Button。
/// 复用 App Intents 底座的 OpenRecordIntent —— 点一下直接打开 App 到记录入口。
struct BubuRecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.bubu.timemachine.control.record") {
            ControlWidgetButton(action: OpenRecordIntent()) {
                Label("记录布布", systemImage: "heart.circle.fill")
            }
        }
        .displayName("记录布布")
        .description("一键打开布布时光机，记录此刻。")
    }
}
