import SwiftUI

// MARK: - 超大主按钮（适老）
/// 首页主动作按钮。用标准 Button：在 ScrollView 里滚动时不会误触，
/// 手指放在按钮上也能正常上下滑动（系统自动区分点按与滚动）。
struct BigButton: View {
    let title: String
    let systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(BubuTheme.Font.scaled(58, weight: .medium))
                Text(title)
                    .font(BubuTheme.Font.title)
                Text("轻点打开 · 上下滑动浏览")
                    .font(BubuTheme.Font.caption)
                    .opacity(0.86)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 176)
            .background(
                LinearGradient(
                    colors: [BubuTheme.Color.primary,
                             BubuTheme.Color.primary.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.button, style: .continuous))
            .bubuCardShadow()
        }
        .buttonStyle(BigButtonStyle())
    }
}

/// 只在明确点按时做轻微缩放反馈，不拦截滚动手势。
private struct BigButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    BigButton(title: "记录此刻", systemImage: "heart.circle.fill") {}
        .padding()
        .background(BubuTheme.Color.background)
}
