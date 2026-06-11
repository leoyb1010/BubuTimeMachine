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
        .bubuPaperTexture(env.theme.theme.paperTexture, isDark: scheme == .dark || env.isDarkTheme)
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

    // MARK: 主题渗透表面色（Wave J §2.1）
    /// 卡片底：在基础卡片色上向主题 surfaceTint 偏移 ~6%，让每套主题「套色彻底」。
    var themedCard: Color {
        BubuTheme.Color.card.mix(with: theme.theme.surfaceTint, by: isDarkTheme ? 0.05 : 0.06)
    }
    /// 轻填充（未选中 chip / 文本框）：偏移 ~8%。
    var themedSoftFill: Color {
        BubuTheme.Color.softFill.mix(with: theme.theme.surfaceTint, by: 0.08)
    }
    /// 发丝线：偏移 ~8%。
    var themedHairline: Color {
        BubuTheme.Color.hairline.mix(with: theme.theme.surfaceTint, by: 0.08)
    }
    /// 主按钮/进度环强调渐变。
    var accentGradient: LinearGradient { theme.theme.accentGradient }
}
