import SwiftUI

/// 新的一天的精选到达时，屏幕上轻轻撒一把星星（约 2.8 秒，一次性）。
/// 纯 Canvas + TimelineView，无第三方库；Reduce Motion 下调用方不显示它。
struct WatchSparkleView: View {
    static let duration: TimeInterval = 2.8

    private struct Particle {
        let origin: CGPoint      // 0...1 相对坐标
        let velocity: CGVector   // 每秒移动的相对距离
        let size: CGFloat
        let spin: Double
        let delay: Double
        let color: Color
        let star: Bool
    }

    @State private var start = Date()
    private let particles: [Particle] = {
        var rng = SeededGenerator(seed: 0x6275_6275)
        let palette: [Color] = [
            Color(red: 0.949, green: 0.471, blue: 0.624),  // #F2789F
            Color(red: 0.882, green: 0.361, blue: 0.525),  // #E15C86
            Color(red: 1.000, green: 0.969, blue: 0.945),  // #FFF7F1
            Color(red: 1.000, green: 0.886, blue: 0.627),  // butter
        ]
        return (0..<34).map { i in
            let angle = Double.random(in: -Double.pi * 0.95 ... -Double.pi * 0.05, using: &rng)
            let speed = Double.random(in: 0.25...0.6, using: &rng)
            return Particle(
                origin: CGPoint(x: Double.random(in: 0.3...0.7, using: &rng), y: Double.random(in: 0.55...0.75, using: &rng)),
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                size: CGFloat.random(in: 3...7, using: &rng),
                spin: Double.random(in: -3...3, using: &rng),
                delay: Double.random(in: 0...0.5, using: &rng),
                color: palette[i % palette.count],
                star: i % 3 != 0)
        }
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                for particle in particles {
                    let t = elapsed - particle.delay
                    let life = Self.duration - 0.6
                    guard t > 0, t < life else { continue }
                    let progress = t / life
                    // 先升后缓落：一点重力，让星星像被轻轻抛起。
                    let x = particle.origin.x + particle.velocity.dx * t
                    let y = particle.origin.y + particle.velocity.dy * t + 0.18 * t * t
                    let point = CGPoint(x: x * size.width, y: y * size.height)
                    let fade = progress < 0.15 ? progress / 0.15 : max(0, 1 - (progress - 0.15) / 0.85)
                    var layer = context
                    layer.opacity = fade
                    layer.translateBy(x: point.x, y: point.y)
                    layer.rotate(by: .radians(particle.spin * t))
                    let s = particle.size * (0.7 + 0.3 * sin(t * 6))
                    if particle.star {
                        layer.fill(Self.sparkle(size: s), with: .color(particle.color))
                    } else {
                        layer.fill(Path(ellipseIn: CGRect(x: -s / 3, y: -s / 3, width: s / 1.5, height: s / 1.5)),
                                   with: .color(particle.color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 四角星：两条贝塞尔收腰的十字。
    private static func sparkle(size s: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -s))
        path.addQuadCurve(to: CGPoint(x: s, y: 0), control: .zero)
        path.addQuadCurve(to: CGPoint(x: 0, y: s), control: .zero)
        path.addQuadCurve(to: CGPoint(x: -s, y: 0), control: .zero)
        path.addQuadCurve(to: CGPoint(x: 0, y: -s), control: .zero)
        return path
    }
}

/// 确定性随机：每次撒的花样一致，不依赖系统随机源。
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
