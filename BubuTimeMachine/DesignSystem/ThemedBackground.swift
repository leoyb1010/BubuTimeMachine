import SwiftUI

// MARK: - 主题感知背景
/// 全 App 统一的页面背景：跟随当前主题的渐变。深色主题自动反色文字。
struct ThemedBackground: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        background.ignoresSafeArea()
    }

    @ViewBuilder
    private var background: some View {
        switch env.theme.theme.backgroundStyle {
        case .solid(let hex):
            Color(hex: hex)
        case .gradient(let a, let b):
            LinearGradient(colors: [Color(hex: a), Color(hex: b)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - 主题色快捷读取
/// 让视图通过 env 读取当前主题色，集中一处，便于切换时全局生效。
extension AppEnvironment {
    var themePrimary: Color { theme.theme.primary }
    var themeSecondary: Color { theme.theme.secondary }
    var isDarkTheme: Bool { theme.theme.isDark }
    /// 主文字色：深色主题用奶白，浅色主题用暖棕。
    var primaryTextColor: Color {
        isDarkTheme ? Color(hex: "#F5F0E8") : BubuTheme.Color.warmBrown
    }
    var secondaryTextColor: Color {
        isDarkTheme ? Color(hex: "#B8B2C8") : BubuTheme.Color.secondaryText
    }
    var cardColor: Color {
        isDarkTheme ? Color(hex: "#33324A") : .white
    }
}
