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

        /// 主色：温暖的珊瑚粉；深色模式下保持粉色按钮识别度。
        static let primary = dynamic(
            light: UIColor(red: 0.95, green: 0.55, blue: 0.62, alpha: 1),
            dark: UIColor(red: 1.00, green: 0.48, blue: 0.60, alpha: 1)
        )
        /// 辅助：奶油底 / 深色柔棕底。
        static let cream = dynamic(
            light: UIColor(red: 0.99, green: 0.97, blue: 0.94, alpha: 1),
            dark: UIColor(red: 0.19, green: 0.16, blue: 0.15, alpha: 1)
        )
        /// 暖棕（文字/标题）。深色模式用暖米白，避免系统自动白字撞浅背景。
        static let warmBrown = dynamic(
            light: UIColor(red: 0.36, green: 0.30, blue: 0.27, alpha: 1),
            dark: UIColor(red: 0.94, green: 0.86, blue: 0.78, alpha: 1)
        )
        /// 柔和次要文字。
        static let secondaryText = dynamic(
            light: UIColor(red: 0.55, green: 0.50, blue: 0.47, alpha: 1),
            dark: UIColor(red: 0.73, green: 0.66, blue: 0.60, alpha: 1)
        )
        /// 页面背景。
        static let background = dynamic(
            light: UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1),
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
    }

    // MARK: 字号阶梯（偏大，适老）
    enum Font {
        static let hugeTitle = SwiftUI.Font.system(size: 34, weight: .bold, design: .rounded)
        static let title = SwiftUI.Font.system(size: 26, weight: .bold, design: .rounded)
        static let headline = SwiftUI.Font.system(size: 21, weight: .semibold, design: .rounded)
        static let body = SwiftUI.Font.system(size: 18, weight: .regular, design: .rounded)
        static let caption = SwiftUI.Font.system(size: 15, weight: .regular, design: .rounded)
    }

    // MARK: 圆角
    enum Radius {
        static let card: CGFloat = 22
        static let button: CGFloat = 28
        static let small: CGFloat = 14
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
    /// 柔和卡片阴影。深色模式下阴影更轻，主要靠卡片色和描边分层。
    nonisolated func bubuCardShadow() -> some View {
        shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
    }
}
