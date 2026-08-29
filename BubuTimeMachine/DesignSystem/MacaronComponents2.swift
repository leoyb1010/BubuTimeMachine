import SwiftUI

// MARK: - 奶油马卡龙视觉组件库（补全包）
/// 严格照搬设计稿（奶油马卡龙 HTML）补齐的组件：药丸标签、点亮迸发、数字滚动、迷你星座。
/// 与 MacaronComponents.swift 同属视觉层，只负责外观/氛围，不持有业务逻辑。
/// 动画一律 reduceMotion 兜底；迸发只在一次性事件用，绝不在滚动区持续重绘。

// MARK: 药丸标签（对应设计稿 MTag）
struct BubuTag: View {
    let text: String
    var background: Color = BubuTheme.Color.cream2
    var foreground: Color = BubuTheme.Color.warmBrown

    var body: some View {
        Text(text)
            .font(BubuTheme.Font.scaled(12, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background(background, in: Capsule())
    }
}

// MARK: 点亮迸发（对应设计稿 MacBurst）——从中心放射的星点，一次性扩散+淡出
struct BubuBurst: View {
    var count: Int = 14
    var radius: CGFloat = 92
    var colors: [Color] = [BubuTheme.Color.primary, BubuTheme.Color.butter,
                           BubuTheme.Color.lav, BubuTheme.Color.mint, BubuTheme.Color.pink]

    @State private var fired = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let angle = (Double(i) / Double(count)) * 2 * .pi + Double(i) * 0.31
                let dist: CGFloat = fired ? radius * (0.78 + CGFloat(i % 3) * 0.12) : 0
                let s: CGFloat = 7 + CGFloat(i % 3) * 4
                BubuStarShape()
                    .fill(colors[i % colors.count])
                    .frame(width: s, height: s)
                    .offset(x: cos(angle) * dist, y: sin(angle) * dist)
                    .opacity(fired ? 0 : 1)
                    .scaleEffect(fired ? 0.4 : 0.3)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.0)) { fired = true }
        }
    }
}

/// 四角星形（迸发星点 / 通用）。
struct BubuStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        var p = Path()
        p.move(to: CGPoint(x: s * 0.5, y: 0))
        p.addQuadCurve(to: CGPoint(x: s, y: s * 0.5), control: CGPoint(x: s * 0.58, y: s * 0.42))
        p.addQuadCurve(to: CGPoint(x: s * 0.5, y: s), control: CGPoint(x: s * 0.58, y: s * 0.58))
        p.addQuadCurve(to: CGPoint(x: 0, y: s * 0.5), control: CGPoint(x: s * 0.42, y: s * 0.58))
        p.addQuadCurve(to: CGPoint(x: s * 0.5, y: 0), control: CGPoint(x: s * 0.42, y: s * 0.42))
        return p
    }
}
