import SwiftUI

// MARK: - 统一状态页（读取中 / 空 / 离线 / 服务器没回应 / 出错）
/// 各页面以前各写一套空态和错误态，文案、图标、按钮都不统一。这里收成一个组件：
/// 软圆底 + 布布表情或 SF Symbol，一句标题，一句说明，可选一个重试（或自定义）按钮。
nonisolated enum BubuStateKind: Hashable, Sendable {
    case loading, empty, offline, serverDown, error

    /// 网络错误 → 合适的状态。
    init(_ error: LearningErrorKind) {
        switch error {
        case .offline: self = .offline
        case .serverUnreachable, .serviceUnavailable: self = .serverDown
        default: self = .error
        }
    }

    var defaultTitle: String {
        switch self {
        case .loading: "正在读取…"
        case .empty: "这里还空空的"
        case .offline: "现在没有网络"
        case .serverDown: "家里的服务器没有回应"
        case .error: "出了点小状况"
        }
    }

    var symbol: String {
        switch self {
        case .loading: "hourglass"
        case .empty: "sparkles"
        case .offline: "wifi.slash"
        case .serverDown: "server.rack"
        case .error: "exclamationmark.bubble"
        }
    }

    var identifier: String {
        switch self {
        case .loading: "loading"
        case .empty: "empty"
        case .offline: "offline"
        case .serverDown: "server-down"
        case .error: "error"
        }
    }
}

struct BubuStateView<Accessory: View>: View {
    let kind: BubuStateKind
    var title: String?
    let message: String
    var illustration: String?
    @ViewBuilder var accessory: Accessory

    init(_ kind: BubuStateKind, title: String? = nil, message: String, illustration: String? = nil,
         @ViewBuilder accessory: () -> Accessory) {
        self.kind = kind
        self.title = title
        self.message = message
        self.illustration = illustration
        self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            badge
            Text(title ?? kind.defaultTitle)
                .font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                .multilineTextAlignment(.center)
            Text(message)
                .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            accessory.padding(.top, BubuTheme.Spacing.xs)
        }
        .padding(.horizontal, BubuTheme.Spacing.l)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("state.\(kind.identifier)")
    }

    @ViewBuilder
    private var badge: some View {
        switch kind {
        case .empty:
            BubuEmptyIllustration(assetName: illustration ?? "BubuEmptyTimeline", fallbackExpression: .bye, size: 120)
        case .loading:
            circle(BubuTheme.Color.pinkSurface) { ProgressView().controlSize(.large).tint(BubuTheme.Color.deepRose) }
        default:
            circle(tint) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.deepRose)
            }
        }
    }

    private var tint: Color {
        switch kind {
        case .offline: BubuTheme.Color.skySurface
        case .serverDown: BubuTheme.Color.butterSurface
        default: BubuTheme.Color.peachSurface
        }
    }

    private func circle<Content: View>(_ fill: Color, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Circle().fill(fill)
            content()
        }
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
    }
}

extension BubuStateView where Accessory == EmptyView {
    init(_ kind: BubuStateKind, title: String? = nil, message: String, illustration: String? = nil) {
        self.init(kind, title: title, message: message, illustration: illustration) { EmptyView() }
    }
}

extension BubuStateView where Accessory == BubuStateRetryButton {
    /// 带一个主按钮（默认「重新加载」）。
    init(_ kind: BubuStateKind, title: String? = nil, message: String, illustration: String? = nil,
         actionTitle: String = "重新加载", action: @escaping () -> Void) {
        self.init(kind, title: title, message: message, illustration: illustration) {
            BubuStateRetryButton(title: actionTitle, action: action)
        }
    }
}

struct BubuStateRetryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.clockwise")
                .font(BubuTheme.Font.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 11)
                .background(BubuTheme.Color.actionFill, in: Capsule())
        }
        .buttonStyle(BubuPressableStyle())
        .accessibilityIdentifier("state.action")
    }
}
