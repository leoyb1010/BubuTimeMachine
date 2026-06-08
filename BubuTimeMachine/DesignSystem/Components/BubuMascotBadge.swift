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

    var body: some View {
        Image(resolved.assetName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .stroke(.white.opacity(0.9), lineWidth: 2)
            }
            .shadow(color: BubuTheme.Color.primary.opacity(0.18), radius: 8, y: 3)
            .accessibilityHidden(true)
    }
}
