import SwiftUI

// MARK: - 动效 token
/// 全 App 只允许这五种曲线（见 DESIGN_UPGRADE.md §4.1）。
/// 新代码禁止裸写 .spring()/.easeInOut()——动效节奏是品牌的一部分，必须统一。
nonisolated enum BubuMotion {
    /// 日常反馈：按压、选中、chip 切换（≤0.3s 内完成感知）
    static let quick = Animation.spring(response: 0.25, dampingFraction: 0.85)
    /// 页面内元素入场 / 布局变化
    static let gentle = Animation.spring(response: 0.4, dampingFraction: 0.8)
    /// 主题切换、模式切换等全局变化
    static let smooth = Animation.smooth(duration: 0.4)
    /// 典礼感：胶囊开启、里程碑点亮（允许 0.8–2.5s）
    static let ceremony = Animation.spring(response: 0.6, dampingFraction: 0.75)
    /// 循环呼吸：等待、即将解锁的胶囊（reduceMotion 时必须整段移除）
    static let breathe = Animation.easeInOut(duration: 3).repeatForever(autoreverses: true)
}

// MARK: - 统一按压缩放
/// 卡片/统计卡等可点元素的标准按压反馈：轻微缩小，不拦截滚动。
struct BubuPressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(BubuMotion.quick, value: configuration.isPressed)
    }
}

// MARK: - 等待浮动
/// AI 思考/等待时的拟人化轻浮动（±4pt，2s 循环）。reduceMotion 时静止。
private struct BubuFloating: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .offset(y: up ? -4 : 4)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { up = true }
                }
        }
    }
}

extension View {
    nonisolated func bubuFloating() -> some View {
        modifier(BubuFloating())
    }
}

// MARK: - 首屏入场
/// 列表卡片错峰淡入（透明度 + 12pt 上移），每个视图自带状态、随挂载触发，
/// 不依赖父视图广播——LazyVStack 懒加载下也稳定。reduceMotion 时不做任何位移/动画。
private struct BubuEntranceEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var shown = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 12)
                .onAppear {
                    withAnimation(BubuMotion.gentle.delay(Double(min(index, 5)) * 0.05)) {
                        shown = true
                    }
                }
        }
    }
}

extension View {
    nonisolated func entranceEffect(index: Int) -> some View {
        modifier(BubuEntranceEffect(index: index))
    }
}
