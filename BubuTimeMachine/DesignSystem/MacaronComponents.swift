import SwiftUI

// MARK: - 奶油马卡龙视觉组件库
/// 全局换皮的可复用视觉层。这些组件只负责「外观/氛围」，不持有业务逻辑，
/// 由各页面包裹/调用，不改任何功能与数据。
/// 性能纪律：背景动效低频、reduceMotion 关闭，绝不在滚动区跑持续重绘。

// MARK: 柔光大色块（背景氛围）
struct BubuBlob: View {
    var color: Color
    var size: CGFloat = 260
    var opacity: Double = 0.5

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 46)
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}

/// 一整屏的柔光氛围背景：几个马卡龙色球漂在奶油底上。静态（不动），零每帧成本。
struct BubuBlobBackground: View {
    var tint: Color = BubuTheme.Color.primary

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BubuTheme.Color.background
                BubuBlob(color: BubuTheme.Color.peach, size: geo.size.width * 0.75, opacity: 0.45)
                    .position(x: geo.size.width * 0.12, y: geo.size.height * 0.10)
                BubuBlob(color: BubuTheme.Color.lav, size: geo.size.width * 0.70, opacity: 0.35)
                    .position(x: geo.size.width * 0.92, y: geo.size.height * 0.22)
                BubuBlob(color: tint.opacity(0.6), size: geo.size.width * 0.65, opacity: 0.30)
                    .position(x: geo.size.width * 0.80, y: geo.size.height * 0.92)
                BubuBlob(color: BubuTheme.Color.mint, size: geo.size.width * 0.55, opacity: 0.22)
                    .position(x: geo.size.width * 0.10, y: geo.size.height * 0.80)
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}

// MARK: 闪烁小星
struct BubuSparkle: View {
    var size: CGFloat = 12
    var color: Color = .white
    var animated: Bool = true
    var delay: Double = 0

    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var star: Path {
        // 四角星
        Path { p in
            let s = size
            p.move(to: CGPoint(x: s * 0.5, y: 0))
            p.addQuadCurve(to: CGPoint(x: s, y: s * 0.5), control: CGPoint(x: s * 0.58, y: s * 0.42))
            p.addQuadCurve(to: CGPoint(x: s * 0.5, y: s), control: CGPoint(x: s * 0.58, y: s * 0.58))
            p.addQuadCurve(to: CGPoint(x: 0, y: s * 0.5), control: CGPoint(x: s * 0.42, y: s * 0.58))
            p.addQuadCurve(to: CGPoint(x: s * 0.5, y: 0), control: CGPoint(x: s * 0.42, y: s * 0.42))
        }
    }

    var body: some View {
        star
            .fill(color)
            .frame(width: size, height: size)
            .opacity(animated && !reduceMotion ? (on ? 1 : 0.35) : 0.9)
            .scaleEffect(animated && !reduceMotion ? (on ? 1.1 : 0.7) : 1)
            .rotationEffect(.degrees(animated && !reduceMotion ? (on ? 20 : 0) : 0))  // 贴合 macTwinkle
            .onAppear {
                guard animated, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true).delay(delay)) {
                    on = true
                }
            }
            .allowsHitTesting(false)
    }
}

// MARK: 进度环
struct BubuProgressRing: View {
    var value: Int
    var total: Int
    var size: CGFloat = 64
    var stroke: CGFloat = 8
    var color: Color = BubuTheme.Color.primary
    var track: Color = BubuTheme.Color.cream2

    private var p: Double { total <= 0 ? 0 : Double(value) / Double(total) }

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: p)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.0), value: p)
        }
        .frame(width: size, height: size)
    }
}

// MARK: 梦幻奶油渐变照片占位（无图时更美）
struct BubuDreamPhoto: View {
    var hue: Double = 28
    var height: CGFloat = 160
    var cornerRadius: CGFloat = 24
    var motif: String = "♡"

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [BubuTheme.Color.hue(hue, lightness: 0.90),
                         BubuTheme.Color.hue((hue + 38).truncatingRemainder(dividingBy: 360), lightness: 0.84),
                         BubuTheme.Color.hue((hue + 70).truncatingRemainder(dividingBy: 360), lightness: 0.88)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Text(motif)
                .font(.system(size: height * 0.45, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
            BubuSparkle(size: 12, color: .white.opacity(0.9))
                .position(x: 24, y: 20)
            BubuSparkle(size: 8, color: .white.opacity(0.7), delay: 0.7)
                .position(x: 14, y: height - 18)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: 卡片修饰（马卡龙圆角 + 柔影）——可链式套在任意视图上
extension View {
    /// 统一的奶油卡片外观：白底、马卡龙圆角、暖玫瑰柔影。
    func bubuMacaronCard(radius: CGFloat = BubuTheme.Radius.card,
                         padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .bubuCardShadow()
    }

    /// 主按钮的马卡龙渐变胶囊外观。
    func bubuPrimaryButton() -> some View {
        self
            .font(BubuTheme.Font.body.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(BubuTheme.Gradient.primaryButton, in: Capsule())
            .shadow(color: BubuTheme.Color.deepRose.opacity(0.45), radius: 12, y: 6)
    }
}
