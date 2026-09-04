import SwiftUI

// MARK: - 布布吉祥物徽章
/// 显示单张布布表情贴纸（绝不显示整张合集）。
/// - `expression`：直接指定表情；
/// - `mood`：按心情自动选表情；
/// - 都不传：用默认开心表情，并叠加 logo 质感的圆角描边。
struct BubuMascotBadge: View {
    var size: CGFloat = 54
    var expression: BubuExpression? = nil
    var mood: Mood? = nil

    private var resolved: BubuExpression {
        expression ?? BubuExpression.forMood(mood)
    }

    /// 是否让她动起来。默认动；出图（ImageRenderer 渲染分享卡/给老师的一页）
    /// 和列表里高密度重复出现的场合可以关掉。
    var isAlive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        sticker
            .shadow(color: BubuTheme.Color.primary.opacity(0.18), radius: 8, y: 3)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var sticker: some View {
        if isAlive && !reduceMotion {
            base.phaseAnimator(Breath.allCases) { view, phase in
                view
                    .scaleEffect(phase == .inhale ? 1.035 : 1, anchor: .bottom)
                    .rotationEffect(.degrees(phase == .tilt ? 2.5 : 0), anchor: .bottom)
            } animation: { phase in
                switch phase {
                case .rest:   .easeInOut(duration: 1.7)
                case .inhale: .easeInOut(duration: 1.5)
                case .tilt:   .spring(response: 0.55, dampingFraction: 0.62)
                }
            }
        } else {
            base
        }
    }

    private var base: some View {
        Image(resolved.assetName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .stroke(.white.opacity(0.9), lineWidth: 2)
            }
    }

    /// 呼吸 → 吸气 → 歪头，循环。幅度刻意压得很小（缩放 3.5%、旋转 2.5°）：
    /// 她在 37 个位置同时出现，任何一处夸张都会变成满屏乱动。
    /// anchor 取 .bottom 让她像坐在那儿，而不是原地缩放。
    private enum Breath: CaseIterable { case rest, inhale, tilt }
}
