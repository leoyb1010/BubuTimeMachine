import SwiftUI

// MARK: - 通用「即将到来」占位
/// 用于尚未深入的灵魂功能模块，保持温暖、不冷场。
struct ComingSoonView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ZStack {
            BubuTheme.Color.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: systemImage)
                    .font(BubuTheme.Font.scaled(60))
                    .foregroundStyle(BubuTheme.Color.primary.opacity(0.75))
                Text(title)
                    .font(BubuTheme.Font.title)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(message)
                    .font(BubuTheme.Font.body)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
        }
    }
}
