import SwiftUI

// MARK: - 首页 Hero 静态网格背景（Wave J §2.2 / 性能修订）
/// 用 iOS 18+ 原生 `MeshGradient` 取代平直双色渐变：3×3 控制点取当前主题 `meshPalette`，
/// 渲染成一张静态、带自然不对称感的柔和渐变。
///
/// 性能纪律（修订）：
/// - **静态渲染**：原先 `TimelineView(.animation)` 以 ~20fps 持续驱动会让屏幕永不 idle，
///   并强迫上层所有玻璃/材质卡片每帧重新采样背景——这是首页不丝滑的主因之一。
///   「光在纸上流动」的微动收益远小于持续重绘的成本，故改为一次性静态渲染。
/// - 取一个固定的非零相位，让控制点保持自然偏移，避免死板的正交网格观感；
/// - 不叠加额外 blur/阴影，零每帧成本。
struct BubuMeshHero: View {
    let colors: [Color]

    /// 固定相位：让 3×3 控制点有自然的不对称漂移，但不随时间变化。
    private static let staticPhase: Double = 1.7

    var body: some View {
        mesh(phase: Self.staticPhase)
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
