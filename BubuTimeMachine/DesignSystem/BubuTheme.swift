import SwiftUI
import UIKit

// MARK: - 布布主题
/// 「高级育儿日记本」质感的统一来源：柔和色板、字号阶梯、圆角、阴影、口语文案。
/// 适老化是一等公民：字号偏大、对比充足、留白舒展。
/// nonisolated：纯常量，可在任意上下文（含 @ViewBuilder Sendable 闭包）引用。
nonisolated enum BubuTheme {

    // MARK: 色板（柔和、温暖、低饱和）
    enum Color {
        private static func dynamic(light: UIColor, dark: UIColor) -> SwiftUI.Color {
            SwiftUI.Color(UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            })
        }

        /// 主色：奶油马卡龙 rose（#F2789F）；深色模式保持识别度。
        static let primary = dynamic(
            light: UIColor(red: 0.949, green: 0.471, blue: 0.624, alpha: 1),   // #F2789F
            dark: UIColor(red: 1.00, green: 0.52, blue: 0.66, alpha: 1)
        )
        /// 强调深色端 deeprose（#E15C86）：主按钮渐变尾色 / 凸起记录键。
        static let deepRose = dynamic(
            light: UIColor(red: 0.882, green: 0.361, blue: 0.525, alpha: 1),   // #E15C86
            dark: UIColor(red: 0.95, green: 0.42, blue: 0.58, alpha: 1)
        )
        /// 辅助：奶油底 cream（#FFF7F1）/ 深色柔棕底。
        static let cream = dynamic(
            light: UIColor(red: 1.000, green: 0.969, blue: 0.945, alpha: 1),   // #FFF7F1
            dark: UIColor(red: 0.19, green: 0.16, blue: 0.15, alpha: 1)
        )
        /// 次奶油底 cream2（#FCEDE4）：选中态 / 嵌套层底。
        static let cream2 = dynamic(
            light: UIColor(red: 0.988, green: 0.929, blue: 0.894, alpha: 1),   // #FCEDE4
            dark: UIColor(red: 0.24, green: 0.20, blue: 0.18, alpha: 1)
        )
        /// 暖棕（文字/标题）ink（#5A3D34）。深色用暖米白。
        static let warmBrown = dynamic(
            light: UIColor(red: 0.353, green: 0.239, blue: 0.204, alpha: 1),   // #5A3D34
            dark: UIColor(red: 0.94, green: 0.86, blue: 0.78, alpha: 1)
        )
        /// 次要文字：必须在奶油底上通过 WCAG AA，对老人机大字模式仍清晰。
        static let secondaryText = dynamic(
            light: UIColor(red: 0.455, green: 0.326, blue: 0.278, alpha: 1),   // #745347
            dark: UIColor(red: 0.80, green: 0.73, blue: 0.67, alpha: 1)
        )
        /// 页面背景（奶油基底，略带粉调）。
        static let background = dynamic(
            light: UIColor(red: 1.000, green: 0.969, blue: 0.945, alpha: 1),   // #FFF7F1
            dark: UIColor(red: 0.10, green: 0.085, blue: 0.08, alpha: 1)
        )
        /// 卡片底。
        static let card = dynamic(
            light: UIColor.white,
            dark: UIColor(red: 0.15, green: 0.125, blue: 0.115, alpha: 1)
        )
        /// 稍高一层的卡片底。
        static let elevatedCard = dynamic(
            light: UIColor.white,
            dark: UIColor(red: 0.19, green: 0.155, blue: 0.145, alpha: 1)
        )
        /// 轻填充，用于未选中 chip / 文本框。
        static let softFill = dynamic(
            light: UIColor(red: 0.96, green: 0.91, blue: 0.88, alpha: 1),
            dark: UIColor(red: 0.24, green: 0.19, blue: 0.18, alpha: 1)
        )
        /// 分隔线。
        static let hairline = dynamic(
            light: UIColor(red: 0.86, green: 0.80, blue: 0.76, alpha: 1),
            dark: UIColor(red: 0.36, green: 0.30, blue: 0.28, alpha: 1)
        )
        /// 柔绿（同步成功等正向状态）
        static let success = dynamic(
            light: UIColor(red: 0.55, green: 0.72, blue: 0.58, alpha: 1),
            dark: UIColor(red: 0.46, green: 0.78, blue: 0.55, alpha: 1)
        )
        static let danger = dynamic(
            light: UIColor(red: 0.86, green: 0.23, blue: 0.28, alpha: 1),
            dark: UIColor(red: 1.0, green: 0.42, blue: 0.48, alpha: 1)
        )
        /// 暖橙（同步重试中 / 需要注意，如备份过期）。禁止页面裸写 .orange。
        static let warning = dynamic(
            light: UIColor(red: 0.93, green: 0.62, blue: 0.23, alpha: 1),
            dark: UIColor(red: 0.98, green: 0.72, blue: 0.36, alpha: 1)
        )
        /// 柔蓝（AI 处理中 / 信息提示）。禁止页面裸写 .blue。
        static let info = dynamic(
            light: UIColor(red: 0.36, green: 0.55, blue: 0.80, alpha: 1),
            dark: UIColor(red: 0.50, green: 0.68, blue: 0.92, alpha: 1)
        )

        // MARK: 马卡龙副色板（记忆色相 / 渐变 / 星座盘星点）
        static let peach  = SwiftUI.Color(red: 1.000, green: 0.827, blue: 0.745) // #FFD3BE
        static let pink   = SwiftUI.Color(red: 1.000, green: 0.761, blue: 0.839) // #FFC2D6
        static let lav    = SwiftUI.Color(red: 0.863, green: 0.788, blue: 1.000) // #DCC9FF
        static let mint   = SwiftUI.Color(red: 0.749, green: 0.922, blue: 0.827) // #BFEBD3
        static let butter = SwiftUI.Color(red: 1.000, green: 0.886, blue: 0.627) // #FFE2A0
        static let sky    = SwiftUI.Color(red: 0.769, green: 0.894, blue: 1.000) // #C4E4FF

        /// 由色相（0–360）生成一抹柔和马卡龙色，用于按记忆/里程碑上色（对照设计稿 HUE()）。
        static func hue(_ h: Double, lightness: Double = 0.86, saturation: Double = 0.90) -> SwiftUI.Color {
            SwiftUI.Color(hue: (h.truncatingRemainder(dividingBy: 360)) / 360.0,
                          saturation: saturation, brightness: lightness)
        }
    }

    // MARK: 字号阶梯（偏大，适老；马卡龙加重标题字）
    enum Font {
        static let hugeTitle = SwiftUI.Font.system(.largeTitle, design: .rounded).weight(.heavy)
        static let title = SwiftUI.Font.system(.title, design: .rounded).weight(.heavy)
        static let headline = SwiftUI.Font.system(.title3, design: .rounded).weight(.bold)
        static let body = SwiftUI.Font.system(.body, design: .rounded)
        static let caption = SwiftUI.Font.system(.subheadline, design: .rounded).weight(.medium)
    }

    // MARK: 圆角（马卡龙更圆润）
    enum Radius {
        static let card: CGFloat = 28
        static let button: CGFloat = 28
        static let small: CGFloat = 16
    }

    // MARK: 马卡龙渐变（主按钮 / Hero / 凸起键）
    enum Gradient {
        /// 主按钮：rose → deeprose。
        static var primaryButton: LinearGradient {
            LinearGradient(colors: [Color.primary, Color.deepRose],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        /// Hero 卡：peach → pink → lav。
        static var hero: LinearGradient {
            LinearGradient(colors: [Color.peach, Color.pink, Color.lav],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: 间距
    enum Spacing {
        static let section: CGFloat = 28
        static let item: CGFloat = 16
    }

    // MARK: 口语文案常量（错误永不报代码，永不吓人）
    enum Copy {
        static let recordNow = "记录此刻"
        static let speakToBubu = "直接说给布布听"
        static let emptyTimeline = "还没有记录呢\n点上面的「记录此刻」，留住布布的第一个瞬间吧"
        static let saving = "正在保存…"
        static let savedLocally = "已经存在手机里啦"
    }
}

// MARK: - 阴影修饰
extension View {
    /// 柔和卡片阴影（马卡龙暖玫瑰投影，比纯黑更通透柔和）。
    nonisolated func bubuCardShadow() -> some View {
        shadow(color: SwiftUI.Color(red: 0.71, green: 0.47, blue: 0.43).opacity(0.20),
               radius: 14, x: 0, y: 8)
    }
}
