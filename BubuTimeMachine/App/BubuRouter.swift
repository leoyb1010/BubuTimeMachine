import SwiftUI

// MARK: - 全局路由（桌面小组件 / 通知 deep link → 定位到具体 Tab）
/// 小组件点击走 `bubu://<host>` 深链。App 在 `onOpenURL` 里解析成 `BubuRoute` 写进这里，
/// `RootTabView` 观察 `pendingTab` 完成切换。保持极简：只负责"切到哪个 Tab"，页内导航仍由各页自理。
@Observable
@MainActor
final class BubuRouter {
    /// 待处理的目标 Tab（被 RootTabView 消费后置回 nil）。
    var pendingTab: Int?
    /// 待触发「快速记录」信号（小组件/控件按钮打开 App 后直达记录，被首页消费后置回 false）。
    var pendingQuickCapture = false
    /// Spotlight / App Entity 指向的具体时光；RootTabView 消费后推入时光导航栈。
    var pendingEntryID: UUID?
    /// 小组件/手表“今日精选”指向的第二大脑素材；在线时光消费后打开详情。
    var pendingOnlineID: String?
    /// Siri / 链接指定的日期（yyyy-MM-dd）：时光跳到那个月，每日学习切到那一天。
    var pendingTimelineDay: String?
    var pendingLearningDay: String?
    /// Siri「问问布布时光」带来的问题，由 RootTabView 打开布布问答。
    var pendingAsk: String?

    /// 解析 deep link。识别不了的 URL 安全忽略（不跳转、不崩）。
    func handle(_ url: URL) {
        guard url.scheme == BubuRoute.scheme, let route = BubuRoute(host: url.host) else { return }
        pendingTab = route.tabIndex
        pendingQuickCapture = (route == .record)
        pendingEntryID = nil
        pendingOnlineID = nil
        if route == .online, let rawID = url.pathComponents.dropFirst().first,
           rawID.range(of: "^[a-f0-9]{24}$", options: .regularExpression) != nil {
            pendingOnlineID = rawID
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let day = query.first { $0.name == "date" }?.value
            .flatMap { $0.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil ? $0 : nil }
        if route == .moment { pendingTimelineDay = day }
        if route == .learning { pendingLearningDay = day }
        if route == .ask, let question = query.first(where: { $0.name == "q" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines), !question.isEmpty {
            pendingAsk = String(question.prefix(200))
        }
        if route == .moment {
            if let rawID = url.pathComponents.dropFirst().first,
               let id = UUID(uuidString: rawID) {
                pendingEntryID = id
            }
        }
    }
}

// MARK: - 每个窗口的路由接线（多窗口）
/// router 是 per-scene 的（见 SceneRoot），深链只进收到它的那个窗口，两个窗口不会同时跳页。
/// 剩下两处要指定「哪个窗口」：
/// - 深链投递：用户正在看的窗口（appearsActive）声明优先接收，其余窗口仍允许接收——
///   系统不会把小组件深链塞给背后那个窗口，也不会另开新窗口；
/// - 控制中心 / Action Button 的「记一笔」是跨进程共享标志（SharedDefaults.pendingRecord），不属于任何窗口：
///   多窗口时只由正在看的窗口认领；只有一个前台窗口时照旧直接认领。
extension View {
    func bubuSceneRouting(_ router: BubuRouter) -> some View {
        modifier(BubuSceneRouting(router: router))
    }
}

private struct BubuSceneRouting: ViewModifier {
    let router: BubuRouter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        content
            .environment(router)
            .onOpenURL { router.handle($0) }
            .handlesExternalEvents(preferring: appearsActive ? ["*"] : [], allowing: ["*"])
            .onAppear { claimPendingRecord() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { claimPendingRecord() }
            }
            .onChange(of: appearsActive) { _, active in
                if active { claimPendingRecord() }
            }
    }

    private func claimPendingRecord() {
        guard SharedDefaults.pendingRecord else { return }
        let foreground = UIApplication.shared.connectedScenes.filter { $0.activationState == .foregroundActive }
        guard appearsActive || foreground.count <= 1 else { return }
        SharedDefaults.pendingRecord = false
        router.pendingQuickCapture = true
    }
}

// MARK: - 深链路由表
enum BubuRoute: String {
    case identity   // 身份卡 → 首页
    case moment     // 今日时光 → 时光轴
    case growth     // 成长一览 → 成长域
    case record     // 记一笔 → 首页并拉起快速记录
    case online     // 今日精选 → 在线时光详情
    case learning   // 每日学习
    case ask        // 布布问答（Siri）→ 时光并打开问答

    static let scheme = "bubu"

    init?(host: String?) {
        guard let host, let route = BubuRoute(rawValue: host) else { return nil }
        self = route
    }

    /// 对应 RootTabView 的 selection。
    var tabIndex: Int {
        switch self {
        case .identity, .record: return 0
        case .moment, .online, .ask: return 1
        case .growth: return 2
        case .learning: return RootTabView.learningTab
        }
    }

    /// 供小组件构造 `.widgetURL`。
    var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }

    nonisolated static func onlineURL(id: String) -> URL {
        URL(string: "bubu://online/\(id)")!
    }

    nonisolated static func momentURL(id: UUID) -> URL {
        URL(string: "bubu://moment/\(id.uuidString)")!
    }
}
