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
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background(background, in: Capsule())
    }
}

// MARK: 数字滚动（对应设计稿 useCountUp，easeOutCubic）
/// 用法：BubuCountUp(value: 24) { n in Text("\(n)") } —— reduceMotion 时直接显示终值。
struct BubuCountUp<Content: View>: View {
    let value: Int
    var duration: Double = 1.1
    @ViewBuilder var content: (Int) -> Content

    @State private var shown: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content(shown)
            .onAppear {
                guard !reduceMotion, value > 0 else { shown = value; return }
                animate()
            }
            .onChange(of: value) { _, _ in
                guard !reduceMotion else { shown = value; return }
                animate()
            }
    }

    private func animate() {
        shown = 0
        let steps = min(value, 60)
        guard steps > 0 else { shown = value; return }
        for i in 1...steps {
            let p = Double(i) / Double(steps)
            let eased = 1 - pow(1 - p, 3)               // easeOutCubic
            let target = Int(round(Double(value) * eased))
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * p) {
                // 防止快速重入时旧动画覆盖新值
                if target >= shown || i == steps { shown = (i == steps) ? value : target }
            }
        }
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

// MARK: 迷你星座（对应设计稿 MacMiniConstellation）——首页双卡用
struct BubuMiniConstellation: View {
    /// 已点亮颗数（决定连线长度与亮点数）。
    var done: Int = 8
    var height: CGFloat = 64
    /// 锚点（设计稿 96×96 viewBox 的比例坐标）
    private let pts: [CGPoint] = [
        .init(x: 14, y: 46), .init(x: 40, y: 26), .init(x: 66, y: 50),
        .init(x: 30, y: 70), .init(x: 58, y: 74), .init(x: 82, y: 38)
    ]
    private let hues: [Double] = [20, 330, 50, 270, 150, 200]

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / 96
            let lit = min(done, pts.count)
            ZStack {
                // 连线（lav，连已点亮）
                if lit >= 2 {
                    Path { p in
                        for i in 0..<lit {
                            let pt = scaled(pts[i], scale)
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(BubuTheme.Color.lav.opacity(0.7),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                // 星点
                ForEach(pts.indices, id: \.self) { i in
                    let on = i < lit
                    let c = scaled(pts[i], scale)
                    ZStack {
                        if on {
                            Circle().fill(BubuTheme.Color.hue(hues[i % hues.count]))
                                .frame(width: 18 * scale, height: 18 * scale)
                                .opacity(0.4)
                        }
                        Circle().fill(on ? BubuTheme.Color.deepRose : Color(white: 0.86))
                            .frame(width: (on ? 9 : 5) * scale, height: (on ? 9 : 5) * scale)
                    }
                    .position(c)
                }
            }
        }
        .frame(height: height)
    }

    private func scaled(_ p: CGPoint, _ s: CGFloat) -> CGPoint {
        CGPoint(x: p.x * s, y: p.y * s)
    }
}
