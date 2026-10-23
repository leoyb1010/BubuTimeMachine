import SwiftUI

// MARK: - 宽屏自适应基建（iPad / 分屏 / 台前调度）
//
// 【一条必须守住的纪律】判断依据一律用 `horizontalSizeClass`，**绝不用 UIDevice.idiom**。
// 原因：iPad 分屏到 1/3 宽时系统给的是 compact，此时必须退回 iPhone 布局；
// 用设备类型判断会让分屏直接崩版。窄屏（iPhone 全部场景 + iPad 窄分屏）永远走原有布局。

/// 宽屏内容列：给纯阅读型页面加最大宽度并居中，窄屏完全透传（iPhone 一个像素不变）。
///
/// 为什么需要：全工程原本没有任何宽度上限（唯一一处有限 maxWidth 在庆祝动画里），
/// 所有页面都是 `VStack { ... }.frame(maxWidth: .infinity)`。
/// 在 13" iPad 上一行正文横跨 1024pt+，眼睛要来回扫，这是「像放大的手机」的首要来源。
private struct BubuContentColumn: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)   // 外层撑满以实现居中
        } else {
            content
        }
    }
}

extension View {
    /// 宽屏时收进居中内容列（默认 700pt，接近正文舒适行宽）；窄屏原样。
    func bubuContentColumn(_ maxWidth: CGFloat = 700) -> some View {
        modifier(BubuContentColumn(maxWidth: maxWidth))
    }
}

// MARK: - 自适应度量

/// 一组按宽度分档的布局常量。业务侧只问「几列」「多高」，不各自写 sizeClass 判断。
enum BubuAdaptive {
    /// 是否宽屏（regular 宽度）。分屏变窄时会自动变回 false。
    static func isWide(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
        sizeClass == .regular
    }

    /// 网格列数：窄屏用原有列数，宽屏用更多列。
    /// 宽屏不是「把格子撑大」而是「多放几个」——这是 iPad 布局的核心心智。
    static func columns(_ sizeClass: UserInterfaceSizeClass?, compact: Int, regular: Int) -> Int {
        isWide(sizeClass) ? regular : compact
    }

    /// 按宽度取值的通用二选一。
    static func value<T>(_ sizeClass: UserInterfaceSizeClass?, compact: T, regular: T) -> T {
        isWide(sizeClass) ? regular : compact
    }
}

// MARK: - BubuLayout：统一布局上下文（iPhone Duo WS0）
//
// 替代只看宽度的 BubuAdaptive.isWide。在每个 Tab 根、每个弹窗根用 `.bubuLayoutRoot()` 测一次，
// 子视图用 `@Environment(\.bubuLayout)` 读。没有「现在是什么姿态」的接口，布局只看：
// 尺寸（点数分档）、折痕保留区域（reservedRegions .division）、竖排栏在哪侧。
// 绝不按设备型号 / 屏幕尺寸识别 Duo（Apple 明确不建议）。
//
// 坐标约定：fold / panes 都在「最近的 bubuLayoutRoot」本地坐标系里；
// 子视图要比较位置时，量 `proxy.frame(in: .global)` 再用 `layout.rootRect(fromGlobal:)` 换算。
// 不用 `.named(coordinateSpaceName)`：Tab 根的布局根在 NavigationStack 外面，栈里的根页和 push 出来的页
// 各自由 UIKit 宿主承载，名字坐标系不保证能跨过这层边界（找不到时会悄悄退回成全局坐标）；
// 全局坐标在同一窗口里处处一致，换算只差布局根自己的全局原点。

nonisolated struct BubuLayout: Equatable, Sendable {
    /// 按点数分档。宽：<600 compact，<900 medium，其余 expanded；高：<480 compact，<900 medium，其余 expanded。
    enum SizeClass: Int, Comparable, Sendable {
        case compact, medium, expanded
        static func < (a: SizeClass, b: SizeClass) -> Bool { a.rawValue < b.rawValue }
    }

    /// 测量根的尺寸（含安全区）。未测量时为 .zero。
    var size: CGSize
    /// 测量根的安全区内边距（含竖排栏、状态栏、底栏）。
    var safeInsets: EdgeInsets
    /// 激活中的折痕区域（根本地坐标）；nil = 没有折痕 / 未半折 / 不支持。
    var fold: CGRect?
    /// 竖排栏所在侧；nil = 栏是水平的。
    var barEdge: HorizontalEdge?
    /// 布局根在全局坐标里的原点，用于把子视图的全局位置换算成根坐标。
    var origin: CGPoint

    static let coordinateSpaceName = "bubu.layout.root"
    /// 未放 bubuLayoutRoot 时的默认值：尺寸未知，不算矮屏、没有折痕。
    static let unknown = BubuLayout(size: .zero, safeInsets: EdgeInsets(), fold: nil, barEdge: nil)

    init(size: CGSize, safeInsets: EdgeInsets = EdgeInsets(), fold: CGRect? = nil, barEdge: HorizontalEdge? = nil,
         origin: CGPoint = .zero) {
        self.size = size
        self.safeInsets = safeInsets
        self.fold = fold
        self.barEdge = barEdge
        self.origin = origin
    }

    /// 子视图的全局 frame（`proxy.frame(in: .global)`）→ 布局根坐标，可直接和 fold / panes 比较。
    func rootRect(fromGlobal rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    var widthClass: SizeClass { Self.widthClass(for: size.width) }
    var heightClass: SizeClass { Self.heightClass(for: size.height) }
    /// 矮屏（高 < 480，如 Duo 合上横拿 / 普通 iPhone 横拿）。未测量（0）不算矮。
    var isShort: Bool { heightClass == .compact }
    /// 折痕方向：竖直 = 书本（左右两半），水平 = 桌面（上下两半）。
    var foldAxis: Axis? { fold.map { $0.height >= $0.width ? .vertical : .horizontal } }

    /// 安全区域（根本地坐标）。
    var safeRect: CGRect {
        CGRect(x: safeInsets.leading, y: safeInsets.top,
               width: max(0, size.width - safeInsets.leading - safeInsets.trailing),
               height: max(0, size.height - safeInsets.top - safeInsets.bottom))
    }

    /// 被折痕分开的安全区块；没有折痕（或折痕不在安全区内）时只有一块。
    var panes: [CGRect] {
        let safe = safeRect
        guard let fold, let axis = foldAxis, fold.intersects(safe) else { return safe.isEmpty ? [] : [safe] }
        // 先算折痕两侧的原始跨度再建 CGRect：CGRect 会把负宽高标准化成正数，事后看 width 分不出“这一侧不存在”。
        let parts: [CGRect]
        switch axis {
        case .vertical:
            let lead = fold.minX - safe.minX, trail = safe.maxX - fold.maxX
            parts = [lead > 0 ? CGRect(x: safe.minX, y: safe.minY, width: lead, height: safe.height) : nil,
                     trail > 0 ? CGRect(x: fold.maxX, y: safe.minY, width: trail, height: safe.height) : nil].compactMap { $0 }
        case .horizontal:
            let top = fold.minY - safe.minY, bottom = safe.maxY - fold.maxY
            parts = [top > 0 ? CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: top) : nil,
                     bottom > 0 ? CGRect(x: safe.minX, y: fold.maxY, width: safe.width, height: bottom) : nil].compactMap { $0 }
        }
        return parts.filter { $0.width > 0 && $0.height > 0 }
    }

    /// 矮屏取 short，否则取 regular。用于固定高度的大图、题图、地图。
    func bubuHeight(_ regular: CGFloat, short: CGFloat) -> CGFloat { isShort ? short : regular }

    static func widthClass(for width: CGFloat) -> SizeClass {
        width < 600 ? .compact : (width < 900 ? .medium : .expanded)
    }

    static func heightClass(for height: CGFloat) -> SizeClass {
        guard height > 0 else { return .medium }
        return height < 480 ? .compact : (height < 900 ? .medium : .expanded)
    }

    /// 调试用假折痕：24pt 宽，居中，贯穿整个根区域。
    static func fakeFold(axis: Axis, in size: CGSize, width: CGFloat = 24) -> CGRect {
        switch axis {
        case .vertical: CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        case .horizontal: CGRect(x: 0, y: (size.height - width) / 2, width: size.width, height: width)
        }
    }

    // MARK: 避折痕的列

    /// 一段水平区间（根坐标）被竖直折痕切开后的宽度：leading | gutter（折痕 + 两侧边距）| trailing。
    struct ColumnSplit: Equatable, Sendable {
        var leading: CGFloat
        var gutter: CGFloat
        var trailing: CGFloat
    }

    /// 列 [minX, minX+width]（根坐标）是否被**竖直**折痕切开；两侧都 ≥ minPane 才分栏。水平折痕不处理。
    func columnSplit(minX: CGFloat, width: CGFloat, margin: CGFloat = 12, minPane: CGFloat = 160) -> ColumnSplit? {
        guard let fold, foldAxis == .vertical, width > 0 else { return nil }
        let leading = fold.minX - margin - minX
        let trailing = minX + width - (fold.maxX + margin)
        guard leading >= minPane, trailing >= minPane else { return nil }
        return ColumnSplit(leading: leading, gutter: fold.width + margin * 2, trailing: trailing)
    }

    // MARK: 避折痕的网格

    struct FoldGridSpec: Equatable, Sendable {
        var count: Int
        var spacing: CGFloat
        /// 正中那道间距（第 count/2 列之后）；有竖直折痕时 = 折痕宽 + 两侧边距。
        var centerSpacing: CGFloat

        var gridItems: [GridItem] {
            (0..<count).map { index in
                GridItem(.flexible(), spacing: count.isMultiple(of: 2) && index == count / 2 - 1 ? centerSpacing : spacing)
            }
        }
    }

    /// 网格列数：窄屏且无折痕 = compactColumns；宽屏（medium+）或有竖直折痕时按 minItemWidth 取**偶数**列（≥2），
    /// 折痕激活时正中间距对齐折痕。纯函数，方便单测。
    static func foldGridSpec(width: CGFloat, widthClass: SizeClass, compactColumns: Int,
                             minItemWidth: CGFloat, spacing: CGFloat, foldGutter: CGFloat?,
                             maxColumns: Int = 8) -> FoldGridSpec {
        guard widthClass != .compact || foldGutter != nil else {
            return FoldGridSpec(count: max(1, compactColumns), spacing: spacing, centerSpacing: spacing)
        }
        let gutter = max(foldGutter ?? spacing, spacing)
        // n 个格子：n×min + (n−2)×spacing + gutter ≤ width
        let fit = Int(((width - gutter + spacing * 2) / (minItemWidth + spacing)).rounded(.down))
        var count = min(max(fit, 2), maxColumns)
        if !count.isMultiple(of: 2) { count -= 1 }
        return FoldGridSpec(count: max(count, 2), spacing: spacing, centerSpacing: gutter)
    }

    /// LazyVGrid 的列（宽度默认取安全区宽度）。
    func bubuFoldGrid(compactColumns: Int = 2, minItemWidth: CGFloat = 160, spacing: CGFloat = 12,
                      margin: CGFloat = 12, availableWidth: CGFloat? = nil) -> [GridItem] {
        let gutter = foldAxis == .vertical ? fold.map { $0.width + margin * 2 } : nil
        return Self.foldGridSpec(width: availableWidth ?? safeRect.width, widthClass: widthClass,
                                 compactColumns: compactColumns, minItemWidth: minItemWidth,
                                 spacing: spacing, foldGutter: gutter).gridItems
    }
}

nonisolated private struct BubuLayoutKey: EnvironmentKey {
    static let defaultValue = BubuLayout.unknown
}

extension EnvironmentValues {
    var bubuLayout: BubuLayout {
        get { self[BubuLayoutKey.self] }
        set { self[BubuLayoutKey.self] = newValue }
    }
}

// MARK: - DEBUG 启动参数：-uitest-layout WxH / -uitest-fake-fold h|v

nonisolated enum BubuLayoutDebug {
    /// `-uitest-layout 466x678`：把场景根内容限制在 W×H（左上角），真实按这个尺寸排版。
    static func parseForcedSize(_ arguments: [String]) -> CGSize? {
        guard let index = arguments.firstIndex(of: "-uitest-layout"), index + 1 < arguments.count else { return nil }
        let parts = arguments[index + 1].lowercased()
            .replacingOccurrences(of: "×", with: "x")
            .split(separator: "x")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }

    /// `-uitest-fake-fold v|h`：在每个布局根中间注入 24pt 宽的激活折痕（v = 竖直书本，h = 水平桌面）。
    static func parseFakeFold(_ arguments: [String]) -> Axis? {
        guard let index = arguments.firstIndex(of: "-uitest-fake-fold"), index + 1 < arguments.count else { return nil }
        switch arguments[index + 1].lowercased() {
        case "v", "vertical": return .vertical
        case "h", "horizontal": return .horizontal
        default: return nil
        }
    }

    #if DEBUG
    static let forcedSize = parseForcedSize(ProcessInfo.processInfo.arguments)
    static let fakeFoldAxis = parseFakeFold(ProcessInfo.processInfo.arguments)
    #else
    static let forcedSize: CGSize? = nil
    static let fakeFoldAxis: Axis? = nil
    #endif
}

// MARK: - 布局根

nonisolated private struct BubuLayoutGeometry: Equatable, Sendable {
    var size: CGSize
    var safeInsets: EdgeInsets
    var folds: [CGRect]
    var origin: CGPoint = .zero
}

private struct BubuLayoutRoot: ViewModifier {
    @State private var geometry = BubuLayoutGeometry(size: .zero, safeInsets: EdgeInsets(), folds: [])
    @State private var barEdge: HorizontalEdge?

    private var layout: BubuLayout {
        let fold = BubuLayoutDebug.fakeFoldAxis.map { BubuLayout.fakeFold(axis: $0, in: geometry.size) }
            ?? geometry.folds.first
        return BubuLayout(size: geometry.size, safeInsets: geometry.safeInsets, fold: fold, barEdge: barEdge,
                          origin: geometry.origin)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.bubuLayout, layout)
            .coordinateSpace(.named(BubuLayout.coordinateSpaceName))
            .onGeometryChange(for: BubuLayoutGeometry.self) { proxy in
                BubuLayoutGeometry(size: proxy.size, safeInsets: proxy.safeAreaInsets,
                                   folds: BubuDuo.activeDivisionFrames(in: proxy),
                                   origin: proxy.frame(in: .global).origin)
            } action: { geometry = $0 }
            .bubuOnToolbarVerticalEdgeChange { barEdge = $0 }
    }
}

#if DEBUG
/// `-uitest-layout WxH`：场景根内容被限制在 W×H（左上角，真实窗口内），并按该尺寸覆盖 size class
/// （宽 ≥ 600 regular，高 < 480 垂直 compact），让 iPad 模拟器能自动跑 Duo 各姿态尺寸矩阵。
/// `-uitest-fake-fold` 时在中间画一条半透明红带，截图里能看到假折痕位置。
private struct BubuDebugLayoutFrame: ViewModifier {
    func body(content: Content) -> some View {
        if let size = BubuLayoutDebug.forcedSize {
            content
                .environment(\.horizontalSizeClass, size.width >= 600 ? .regular : .compact)
                .environment(\.verticalSizeClass, size.height < 480 ? .compact : .regular)
                .frame(width: size.width, height: size.height)
                .overlay { foldMarker(in: size) }
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.gray.opacity(0.35).ignoresSafeArea())
        } else if BubuLayoutDebug.fakeFoldAxis != nil {
            content.overlay { GeometryReader { foldMarker(in: $0.size) } }
        } else {
            content
        }
    }

    @ViewBuilder
    private func foldMarker(in size: CGSize) -> some View {
        if let axis = BubuLayoutDebug.fakeFoldAxis {
            let rect = BubuLayout.fakeFold(axis: axis, in: size)
            Color.red.opacity(0.25)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
#endif

extension View {
    /// 在 Tab 根 / 弹窗根测量并下发 `\.bubuLayout`（同时建立 BubuLayout.coordinateSpaceName 坐标系）。
    func bubuLayoutRoot() -> some View {
        modifier(BubuLayoutRoot())
    }

    /// 仅 DEBUG：处理 `-uitest-layout` / `-uitest-fake-fold` 的场景级外框。只在场景根用一次。
    @ViewBuilder
    func bubuDebugLayoutFrame() -> some View {
        #if DEBUG
        modifier(BubuDebugLayoutFrame())
        #else
        self
        #endif
    }

    /// 矮屏时把最大高度换成 short。
    func bubuMaxHeight(regular: CGFloat, short: CGFloat) -> some View {
        modifier(BubuMaxHeight(regular: regular, short: short))
    }

    /// 避折痕的阅读列（只用于滚动页面，不用 ArrangementView）：
    /// - 没有折痕：和 bubuContentColumn(maxWidth) 完全一样（窄屏透传，宽屏居中限宽）；
    /// - 竖直折痕切过本列：主内容放折痕前一侧，后一侧留空（不让内容跨折痕）；
    /// - 水平折痕：不处理（滚动内容允许滚过折痕）。
    func bubuColumn(maxWidth: CGFloat = 700) -> some View {
        modifier(BubuFoldColumn(maxWidth: maxWidth, secondary: EmptyView(), hasSecondary: false))
    }

    /// 同上；竖直折痕时 secondary 放在折痕后一侧。**没有折痕时不显示 secondary。**
    func bubuColumn<Secondary: View>(maxWidth: CGFloat = 700,
                                     @ViewBuilder secondary: () -> Secondary) -> some View {
        modifier(BubuFoldColumn(maxWidth: maxWidth, secondary: secondary(), hasSecondary: true))
    }
}

private struct BubuMaxHeight: ViewModifier {
    @Environment(\.bubuLayout) private var layout
    let regular: CGFloat
    let short: CGFloat

    func body(content: Content) -> some View {
        content.frame(maxHeight: layout.bubuHeight(regular, short: short))
    }
}

/// 列的水平区间（全局坐标）。
nonisolated private struct BubuHorizontalSpan: Equatable, Sendable {
    var minX: CGFloat
    var width: CGFloat
}

private struct BubuFoldColumn<Secondary: View>: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.bubuLayout) private var layout
    @State private var span: BubuHorizontalSpan?
    let maxWidth: CGFloat
    let secondary: Secondary
    let hasSecondary: Bool

    func body(content: Content) -> some View {
        let split = span.flatMap { layout.columnSplit(minX: $0.minX - layout.origin.x, width: $0.width) }
        let wide = sizeClass == .regular
        // 结构恒定（同一个 HStack、content 永远是第一个子视图）：开合时 content 不重建、不丢状态。
        // 无折痕时两层 frame 与 bubuContentColumn 一致；窄屏为 nil frame（透传）。
        HStack(alignment: .top, spacing: 0) {
            content
                .frame(width: split?.leading)
                .frame(maxWidth: split == nil && wide ? maxWidth : nil)
            if let split {
                Color.clear.frame(width: split.gutter, height: 1)
                    .accessibilityHidden(true)
                Group {
                    if hasSecondary { secondary } else { Color.clear.frame(height: 1).accessibilityHidden(true) }
                }
                .frame(width: split.trailing)
            }
        }
        .frame(maxWidth: split != nil || wide ? .infinity : nil, alignment: split == nil ? .center : .leading)
        .onGeometryChange(for: BubuHorizontalSpan.self) { proxy in
            let frame = proxy.frame(in: .global)
            return BubuHorizontalSpan(minX: frame.minX, width: frame.width)
        } action: { span = $0 }
    }
}
