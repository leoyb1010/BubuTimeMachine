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
