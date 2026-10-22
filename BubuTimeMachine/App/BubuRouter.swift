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
        if route == .moment {
            if let rawID = url.pathComponents.dropFirst().first,
               let id = UUID(uuidString: rawID) {
                pendingEntryID = id
            }
        }
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

    static let scheme = "bubu"

    init?(host: String?) {
        guard let host, let route = BubuRoute(rawValue: host) else { return nil }
        self = route
    }

    /// 对应 RootTabView 的 selection。
    var tabIndex: Int {
        switch self {
        case .identity, .record: return 0
        case .moment, .online: return 1
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
