import UIKit

// MARK: - UIApplicationDelegate：启动期注册（前移自 SwiftUI 根视图 .task）
/// 为什么在这里而不是 WindowGroup 的 .task：App 被系统「后台冷启动」时——
/// 通知「回一句」被投递到 didReceive、BGTask 到点、WatchConnectivity 有消息——
/// 场景不会连接/渲染，WindowGroup 的 .task 不执行，于是通知回复代理/BGTask handler/WC session
/// 全都没注册。而 didFinishLaunching 无论前台还是后台冷启动都必定执行。
/// 三个注册对象都是 @MainActor 隔离；didFinishLaunching 在主线程被调用，用
/// MainActor.assumeIsolated 桥接，保证零并发告警。
final class BubuAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MainActor.assumeIsolated {
            // 通知直接回复：注册「回一句」类目 + 设为通知中心代理。
            // App 被杀后系统把回复通知拉到后台投递 didReceive，此时代理必须已就位，否则回复文字永久丢失。
            NotificationReplyHandler.shared.register()
            // 后台补拉：BGTaskScheduler.register 必须在 launch 完成前调用；
            // 真正跑同步的 runner 由 App 在 env/SyncEngine 就绪后经 BackgroundRefresher.setRunner(_:) 注入。
            BackgroundRefresher.register()
            // 手表连接：被 WatchConnectivity 后台唤醒时 session 需已激活。
            WatchConnectivityManager.shared.activate()
        }
        return true
    }
}
