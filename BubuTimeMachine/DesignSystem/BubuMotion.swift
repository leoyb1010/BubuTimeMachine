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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? scale : 1))
            // 取自 leotexiao Squish Button 的“快压、弹回”，原生端收敛振幅到 3%，
            // 高频按钮不会夸张；减少动态效果开启时完全静止。
            .animation(
                reduceMotion
                    ? nil
                    : (configuration.isPressed
                        ? .easeOut(duration: 0.08)
                        : .spring(response: 0.42, dampingFraction: 0.72)),
                value: configuration.isPressed
            )
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

// MARK: - Tab 内容切换过渡
/// 切 Tab 时以前只有 haptic + 底栏图标弹跳，内容区是硬切——两个页面的观感差异全靠瞬间替换，
/// 显得生硬。这里给被选中的页面一次极轻的入场（透明度 + 10pt 上移）。
///
/// 为什么不换掉 TabView 做真正的横向转场：TabView 负责保活各 Tab 的 NavigationStack、
/// 滚动位置与懒加载状态。为一个过渡把它换成 ZStack，代价是每次切页丢状态，得不偿失。
/// reduceMotion 时完全静止。
private struct BubuTabContentTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool
    @State private var settled = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .opacity(settled ? 1 : 0)
                .offset(y: settled ? 0 : 10)
                .onChange(of: isActive) { _, active in
                    guard active else { return }
                    settled = false
                    withAnimation(BubuMotion.gentle) { settled = true }
                }
        }
    }
}

extension View {
    /// 被选中时播一次轻入场。`isActive` 由 Tab selection 驱动。
    nonisolated func bubuTabContentTransition(isActive: Bool) -> some View {
        modifier(BubuTabContentTransition(isActive: isActive))
    }
}
