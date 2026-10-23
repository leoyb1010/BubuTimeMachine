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

    // MARK: 方向（iPhone Duo WS0）
    /// iPhone 已放开横屏（Info.plist）。这里保留一个整体回退开关（高级设置里可关）：
    /// 关掉后 iPhone 锁回竖屏（横着拿的大屏 iPhone 也一样，不看 size class）；iPad / Mac 不受影响，
    /// Duo 内屏本来也不听 App 的方向设置。不按设备尺寸识别 Duo（Apple 明确不建议）。
    static let allowLandscapeKey = "bubu.layout.allowLandscape"

    /// 是否允许 iPhone 横屏，默认 true。
    static var allowsLandscape: Bool {
        UserDefaults.standard.object(forKey: allowLandscapeKey) as? Bool ?? true
    }

    /// 修改回退开关并立即生效：所有窗口重新询问支持的方向；关掉时正横着的 iPhone 马上转回竖屏。
    static func setAllowsLandscape(_ allowed: Bool) {
        UserDefaults.standard.set(allowed, forKey: allowLandscapeKey)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            #if !targetEnvironment(macCatalyst)
            if !allowed, UIDevice.current.userInterfaceIdiom == .phone {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
            #endif
        }
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
        return Self.allowsLandscape ? .allButUpsideDown : .portrait
    }
}
