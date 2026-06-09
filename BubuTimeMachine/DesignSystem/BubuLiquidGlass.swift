import SwiftUI

// MARK: - iOS 26 Liquid Glass
/// 统一封装系统 Liquid Glass。项目目标是 iOS 26，这里仍保留 fallback，
/// 方便预览或临时降低部署目标时不打断 UI。
extension View {
    @ViewBuilder
    nonisolated func bubuGlassSurface(
        cornerRadius: CGFloat = BubuTheme.Radius.card,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            let glass = (tint.map { Glass.regular.tint($0.opacity(0.18)) } ?? Glass.regular)
                .interactive(interactive)
            self.glassEffect(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    @MainActor
    func bubuGlassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.buttonStyle(.plain)
        }
    }
}
