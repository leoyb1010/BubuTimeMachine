import SwiftUI

// MARK: - iPhone Duo API 集中封装（WS0）
//
// 全工程**唯一**允许直接引用 iOS 27.1 Duo 专属接口的文件：
//   ArrangementView、GeometryProxy.reservedRegions、onHingeChange / DeviceHinge、
//   \.toolbarVerticalEdge、axisBehavior、toolbarVerticalBehavior、toolbarVerticalCompressionBehavior。
// 门禁：`#if !targetEnvironment(macCatalyst) && compiler(>=6.4)` + `if #available(iOS 27.1, *)`
// （沿用 BubuIOS27Compatibility.swift 的写法）。Mac Catalyst 用的 macOS 27.0 SDK 没有这些符号；
// 部署目标仍是 iOS 26，老系统 / Catalyst 一律走无操作兜底。业务代码只调用下面的 bubu* 包装。
//
// 【ArrangementView 纪律（Apple 明确要求）】
// - BubuArrangement 只放在「不滚动的页面根部」（答题、相框、故事阅读、认一认、照片详情）；
// - 永远不放进 ScrollView / List / NavigationSplitView；
// - 它里面也不套 NavigationStack / NavigationSplitView / TabView 等导航容器。
// 滚动页面里的避折痕用 BubuAdaptiveLayout.swift 的 bubuColumn / bubuFoldGrid（手工分栏）。
//
// 【铰链】bubuOnHingeChange 只能驱动音效、小动画等效果，**不能驱动布局**；
// 布局一律看 BubuLayout（尺寸 + 折痕保留区域）。

/// 工具栏项在竖排栏里的轴向（对应 ToolbarItemAxisBehavior）。
enum BubuToolbarAxisBehavior: Sendable {
    case automatic
    /// 不进竖排栏（留在顶部横条或溢出菜单），如进度条、长文字项。
    case horizontalOnly
    /// 优先进竖排栏。
    case verticalPreferred
}

/// 竖排栏放不下时先保谁（对应 ToolbarVerticalCompressionBehavior）。
enum BubuToolbarVerticalCompression: Sendable {
    case automatic
    case prefersTabBar
    case prefersToolbarItems
}

/// 铰链状态（对应 DeviceHinge.Status）。
enum BubuHingeStatus: Sendable, Equatable {
    case closed
    case partiallyOpen
    case fullyOpen
}

/// BubuArrangement 的排列样式（对应 ArrangementViewStyle）。
enum BubuArrangementStyle: Sendable {
    case automatic
    /// 两块分开放，有折痕时各占一侧。
    case split
    /// 副内容叠在主内容上；有折痕时分到两侧。
    case overlay
}

// MARK: - 保留区域（折痕 / 遮挡）

nonisolated enum BubuDuo {
    /// proxy 本地坐标系里**激活中**的折痕（division）区域；不支持的系统 / 设备返回空。
    static func activeDivisionFrames(in proxy: GeometryProxy) -> [CGRect] {
        #if !targetEnvironment(macCatalyst) && compiler(>=6.4)
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
        }
        #endif
        return []
    }

    /// proxy 本地坐标系里激活中的遮挡（occlusion，如摄像头区域）区域。
    static func activeOcclusionFrames(in proxy: GeometryProxy) -> [CGRect] {
        #if !targetEnvironment(macCatalyst) && compiler(>=6.4)
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
        }
        #endif
        return []
    }

    /// BubuArrangement 兜底排列方向：只给一个轴就听它的；两个轴都允许时宽 ≥ 高 用左右。
    static func arrangementIsHorizontal(size: CGSize, axes: Axis.Set) -> Bool {
        if axes == .horizontal { return true }
        if axes == .vertical { return false }
        return size.width >= size.height
    }
}

// MARK: - 工具栏

extension ToolbarContent {
    /// 设置工具栏项在竖排栏里的轴向；iOS 27.1 以下 / Catalyst 原样返回。
    @ToolbarContentBuilder
    func bubuAxisBehavior(_ behavior: BubuToolbarAxisBehavior) -> some ToolbarContent {
        #if !targetEnvironment(macCatalyst) && compiler(>=6.4)
        if #available(iOS 27.1, *) {
            switch behavior {
            case .automatic: self.axisBehavior(.automatic)
            case .horizontalOnly: self.axisBehavior(.horizontalOnly)
            case .verticalPreferred: self.axisBehavior(.verticalPreferred)
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

extension View {
    /// 竖排栏空间不够时优先保留底栏还是工具栏按钮。
    @ViewBuilder
    func bubuToolbarVerticalCompression(_ behavior: BubuToolbarVerticalCompression) -> some View {
        #if !targetEnvironment(macCatalyst) && compiler(>=6.4)
        if #available(iOS 27.1, *) {
            switch behavior {
            case .automatic: self.toolbarVerticalCompressionBehavior(.automatic)
            case .prefersTabBar: self.toolbarVerticalCompressionBehavior(.prefersTabBar)
            case .prefersToolbarItems: self.toolbarVerticalCompressionBehavior(.prefersToolbarItems)
            }
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// disabled = true 时本页工具栏不竖排（保持水平）。
    @ViewBuilder
    func bubuToolbarVertical(disabled: Bool) -> some View {
        #if !targetEnvironment(macCatalyst) && compiler(>=6.4)
        if #available(iOS 27.1, *) {
            self.toolbarVerticalBehavior(disabled ? .disabled : .automatic)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// 大图延伸到竖排栏 / 侧栏下面（backgroundExtensionEffect，iOS 26 起，Catalyst 同样可用）。
    func bubuBackgroundExtension(_ isEnabled: Bool = true) -> some View {
        backgroundExtensionEffect(isEnabled: isEnabled)
    }

    /// 读取竖排栏在哪一侧（nil = 栏是水平的 / 系统不支持）。首帧即回调一次。
    @ViewBuilder
    func bubuOnToolbarVerticalEdgeChange(_ action: @escaping (HorizontalEdge?) -> Void) -> some View {
        #if !targetEnvironment(macCatalyst) && compiler(>=6.4)
        if #available(iOS 27.1, *) {
            self.modifier(BubuToolbarVerticalEdgeReader(action: action))
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// 铰链变化（仅用于效果：音效 / 小动画）。无铰链的设备与旧系统永不回调。
    @ViewBuilder
    func bubuOnHingeChange(isEnabled: Bool = true,
                           _ action: @escaping (_ status: BubuHingeStatus, _ angle: Angle) -> Void) -> some View {
        #if !targetEnvironment(macCatalyst) && compiler(>=6.4)
        if #available(iOS 27.1, *) {
            self.onHingeChange(isEnabled: isEnabled) { _, newContext in
                guard let hinge = newContext.hinge else { return }
                let status: BubuHingeStatus
                if hinge.status == .closed {
                    status = .closed
                } else if hinge.status == .partiallyOpen {
                    status = .partiallyOpen
                } else {
                    status = .fullyOpen
                }
                action(status, hinge.angle)
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if !targetEnvironment(macCatalyst) && compiler(>=6.4)
@available(iOS 27.1, *)
private struct BubuToolbarVerticalEdgeReader: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var edge
    let action: (HorizontalEdge?) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: edge, initial: true) { _, newEdge in action(newEdge) }
    }
}
#endif

// MARK: - ArrangementView 包装

/// 不滚动页面根部的「主 + 副」两块排列。iOS 27.1 用系统 ArrangementView（自动按折痕分到两侧）；
/// 旧系统 / Catalyst 退回按宽高比的 HStack / VStack（overlay 退回 ZStack 叠放）。
/// axes：允许的分割方向。`.horizontal` = 左右，`.vertical` = 上下（桌面姿态上图下按钮），两者都给 = 按形状自动。
/// ⚠️ 只放在页面根部；不要放进 ScrollView / List / NavigationSplitView，里面不套导航容器。
struct BubuArrangement<Primary: View, Secondary: View>: View {
    private let axes: Axis.Set
    private let style: BubuArrangementStyle
    private let primary: Primary
    private let secondary: Secondary

    init(axes: Axis.Set = [.horizontal, .vertical],
         style: BubuArrangementStyle = .split,
         @ViewBuilder primary: () -> Primary,
         @ViewBuilder secondary: () -> Secondary) {
        self.axes = axes
        self.style = style
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        #if !targetEnvironment(macCatalyst) && compiler(>=6.4)
        if #available(iOS 27.1, *) {
            system
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    #if !targetEnvironment(macCatalyst) && compiler(>=6.4)
    @available(iOS 27.1, *)
    @ViewBuilder
    private var system: some View {
        let arrangement = ArrangementView { primary } secondary: { secondary }
        switch style {
        case .automatic:
            arrangement.arrangementViewStyle(AutomaticArrangementViewStyle())
        case .split:
            arrangement.arrangementViewStyle(SplitArrangementViewStyle().axes(axes))
        case .overlay:
            arrangement.arrangementViewStyle(OverlayArrangementViewStyle().axes(axes))
        }
    }
    #endif

    private var fallback: some View {
        GeometryReader { proxy in
            let horizontal = BubuDuo.arrangementIsHorizontal(size: proxy.size, axes: axes)
            if style == .overlay {
                ZStack(alignment: horizontal ? .trailing : .bottom) {
                    primary.frame(maxWidth: .infinity, maxHeight: .infinity)
                    secondary
                }
            } else {
                let layout = horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                layout {
                    primary.frame(maxWidth: .infinity, maxHeight: .infinity)
                    secondary.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
