import SwiftUI

// MARK: - 主题感知背景
/// 全 App 统一的页面背景：跟随当前主题的渐变。深色主题自动反色文字。
struct ThemedBackground: View {
    var body: some View {
        BubuThemedBackground().ignoresSafeArea()
    }
}

// MARK: - 深色模式感知的页面背景
/// 关键修复：主题的 `backgroundStyle` 是写死的浅色渐变 hex，不会跟随系统深色模式。
/// 这里在系统深色模式下强制用动态的 `BubuTheme.Color.background`（暖黑棕），
/// 只有浅色模式才用主题渐变；从而让所有页面背景在深色模式下真正变暗，
/// 配合已是动态色的文字 token，消除「浅底浅字」。
/// 用户手动选「星夜」深色主题时，浅色系统下仍走其暗渐变，符合预期。
struct BubuThemedBackground: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if scheme == .dark {
                BubuTheme.Color.background
            } else {
                switch env.theme.theme.backgroundStyle {
                case .solid(let hex):
                    Color(hex: hex)
                case .gradient(let a, let b):
                    LinearGradient(colors: [Color(hex: a), Color(hex: b)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
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
