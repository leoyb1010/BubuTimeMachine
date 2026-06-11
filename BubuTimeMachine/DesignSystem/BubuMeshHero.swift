import SwiftUI

// MARK: - 首页 Hero 呼吸背景（Wave J §2.2）
/// 用 iOS 18+ 原生 `MeshGradient` 取代平直双色渐变：3×3 控制点取当前主题 `meshPalette`，
/// 做极慢漂移（单循环 ~16s，位移 ≤ 0.06），肉眼像「光在纸上流动」，而非动画。
///
/// 性能纪律（§3.4）：
/// - 只放 hero 一处，**不进滚动区**；用 `TimelineView(.animation)` 以 ~20fps 驱动，不追 120fps；
/// - `reduceMotion` 时静止（控制点取静态相位）；
/// - 不叠加额外 blur/阴影，零每帧布局成本。
struct BubuMeshHero: View {
    let colors: [Color]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            mesh(phase: 0)
        } else {
            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: false)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                mesh(phase: t)
            }
        }
    }

    /// 3×3 网格：四角与四边固定，中心点与边中点随相位做小幅正弦漂移。
    private func mesh(phase: Double) -> some View {
        let pts = controlPoints(phase: phase)
        return MeshGradient(width: 3, height: 3, points: pts, colors: paddedColors)
            .ignoresSafeArea()
    }

    /// 至少 9 个颜色：不足时循环填充，保证主题只给 4–6 个也能铺满 3×3。
    private var paddedColors: [Color] {
        guard !colors.isEmpty else { return Array(repeating: .clear, count: 9) }
        return (0..<9).map { colors[$0 % colors.count] }
    }

    private func controlPoints(phase: Double) -> [SIMD2<Float>] {
        func drift(_ base: SIMD2<Float>, ampX: Float, ampY: Float, speed: Double, offset: Double) -> SIMD2<Float> {
            let dx = Float(sin(phase * speed + offset)) * ampX
            let dy = Float(cos(phase * speed + offset * 1.3)) * ampY
            return SIMD2(base.x + dx, base.y + dy)
        }
        let amp: Float = 0.06
        return [
            SIMD2(0, 0),
            drift(SIMD2(0.5, 0), ampX: amp, ampY: 0, speed: 0.18, offset: 0.0),
            SIMD2(1, 0),
            drift(SIMD2(0, 0.5), ampX: 0, ampY: amp, speed: 0.15, offset: 1.0),
            drift(SIMD2(0.5, 0.5), ampX: amp, ampY: amp, speed: 0.20, offset: 2.0),
            drift(SIMD2(1, 0.5), ampX: 0, ampY: amp, speed: 0.17, offset: 3.0),
            SIMD2(0, 1),
            drift(SIMD2(0.5, 1), ampX: amp, ampY: 0, speed: 0.16, offset: 4.0),
            SIMD2(1, 1),
        ]
    }
}
