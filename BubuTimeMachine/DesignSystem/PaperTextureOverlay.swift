import SwiftUI

// MARK: - 纸纹材质叠加（Wave J §2.3）
/// 给「时光机」纸的温度，而不是手机屏的玻璃感。
/// - 纹理透明度封顶 5%；浅色主题 `.multiply`，深色（星夜）用亮噪点 `.screen`；
/// - 静态平铺图，零每帧成本；reduceMotion 无关；
/// - 姥姥模式（最大字号）下自动关闭，对比度永远优先。
struct PaperTextureOverlay: ViewModifier {
    let texture: BubuThemeDefinition.PaperTexture
    let isDark: Bool
    @Environment(\.sizeCategory) private var sizeCategory

    func body(content: Content) -> some View {
        if texture == .none || sizeCategory >= .accessibilityMedium {
            content
        } else {
            content.overlay {
                tile
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var tile: some View {
        if let ui = UIImage(named: imageName) {
            Image(uiImage: ui)
                .resizable(resizingMode: .tile)
                .blendMode(isDark ? .screen : .multiply)
                .opacity(isDark ? 0.05 : 0.04)
        }
    }

    private var imageName: String {
        switch (texture, isDark) {
        case (.fiber, true):  return "paper-fiber-light"   // 深色用亮噪点
        case (.fiber, false): return "paper-fiber"
        case (.grain, true):  return "paper-fiber-light"
        case (.grain, false): return "paper-grain"
        case (.none, _):      return "paper-grain"
        }
    }
}

extension View {
    /// 叠加当前主题指定的纸纹（封顶 5% 透明度，姥姥大字号自动关闭）。
    func bubuPaperTexture(_ texture: BubuThemeDefinition.PaperTexture, isDark: Bool) -> some View {
        modifier(PaperTextureOverlay(texture: texture, isDark: isDark))
    }
}
