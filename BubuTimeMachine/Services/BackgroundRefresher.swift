import Foundation
import BackgroundTasks
import SwiftData
import UserNotifications
import OSLog

// MARK: - 后台补拉（R4 G-2）
/// App 进后台后，系统择机唤醒补一轮同步：家人白天发的照片，晚上打开 App 前就已经拉好。
/// BGAppRefresh 由系统按使用习惯调度（通常每天数次），失败/被杀不影响任何主流程。
@MainActor
enum BackgroundRefresher {
    static let refreshID = "com.bubu.timemachine.refresh"

    private static var syncRunner: (@MainActor () async -> Void)?

    /// 注册 BGTask handler：必须在 didFinishLaunching 完成前调用（从 AppDelegate 调用），
    /// 否则冷启动到后台时系统找不到 handler，且「launch 后再 register」会抛异常。
    /// 真正跑同步的 runner 由 App 在 env/SyncEngine 就绪后经 setRunner(_:) 注入。
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: nil) { task in
            Task { @MainActor in
                await handle(task: task)
            }
        }
    }

    /// env 就绪后注入真正「await 到一轮同步跑完」的 runner。
    static func setRunner(_ runner: @escaping @MainActor () async -> Void) {
        syncRunner = runner
    }

    /// 进后台时排下一次唤醒。
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)   // 最早半小时后
        try? BGTaskScheduler.shared.submit(request)
    }

    private static let log = Logger(subsystem: "com.bubu.timemachine", category: "BackgroundRefresher")

    private static func handle(task: BGTask) async {
        scheduleNext()   // 链式：每次醒来先排下一次
        // runner 尚未注入（纯后台冷启动、UI 场景未渲染，@State env 还没建好）：
        // 不再只能安全兜底成失败——直接用共享容器 + 本机配置构造一次性 SyncEngine 跑一轮真同步（见 makeColdStartRunner）。
        // 拿不到 runner 也拼不出一次性引擎（未配置服务器 / 共享库打不开）时，才如实上报失败让系统稍后重试
        // （切勿留空 expirationHandler / 直接 success，否则会被系统记为超时失败并降配额）。
        let runner = syncRunner ?? makeColdStartRunner()
        guard let runner else {
            task.setTaskCompleted(success: false)
            return
        }
        // 用可取消 Task 包住真实同步；到期回调取消它，再按是否被取消如实上报结果。
        let work = Task { @MainActor in await runner() }
        task.expirationHandler = { work.cancel() }
        await work.value
        task.setTaskCompleted(success: !work.isCancelled)
    }

    /// 冷启动兜底：仅凭 ServerConfig + 共享 ModelContainer + MediaStore 拼一个一次性 SyncEngine，
    /// 跑完一轮 syncOnce 即随作用域拆除。SyncEngine 的构造依赖恰好只有这三样（不依赖完整 AppEnvironment），
    /// 因此能低成本脱离 UI 层就地构造，无需改 env 所有权。
    /// 未配置服务器或共享库不可用时返回 nil（无事可做 / 无处可写），由调用方决定如何上报。
    private static func makeColdStartRunner() -> (@MainActor () async -> Void)? {
        let config = ServerConfig()
        guard config.isConfigured, let url = config.baseURL,
              let container = SharedModelContainer.sharedIfAvailable else {
            return nil
        }
        let client = PocketBaseClient(baseURL: url, identity: config.accountEmail, password: config.accountPassword)
        let engine = SyncEngine(apiClient: client, config: config, mediaStore: MediaStore())
        engine.attach(context: container.mainContext)
        log.info("BGTask 冷启动兜底：runner 未注入，用共享容器构造一次性 SyncEngine 跑一轮")
        return { await engine.syncOnce() }
    }
}

// MARK: - 备份提醒（R4 G-6 轻量版）
/// 自托管家庭的最后保险：每月 1 号提醒做一次全量导出备份（导出功能已有，就差想起来）。
@MainActor
enum BackupReminder {
    private static let id = "bubu.backup.monthly"

    static func scheduleIfAuthorized() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
        let pending = await center.pendingNotificationRequests()
        guard !pending.contains(where: { $0.identifier == id }) else { return }

        var comps = DateComponents()
        comps.day = 1; comps.hour = 10; comps.minute = 3
        let content = UNMutableNotificationContent()
        content.title = "给布布的时光做个备份 📦"
        content.body = "每月一次：到 设置 → 导出，把全部记录导出存到电脑或硬盘。自托管的最后一道保险。"
        content.sound = .default
        try? await center.add(UNNotificationRequest(
            identifier: id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }
}
