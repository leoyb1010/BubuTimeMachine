import SwiftUI

// MARK: - 布布主题
/// 「高级育儿日记本」质感的统一来源：柔和色板、字号阶梯、圆角、阴影、口语文案。
/// 适老化是一等公民：字号偏大、对比充足、留白舒展。
/// nonisolated：纯常量，可在任意上下文（含 @ViewBuilder Sendable 闭包）引用。
nonisolated enum BubuTheme {

    // MARK: 色板（柔和、温暖、低饱和）
    enum Color {
        /// 主色：温暖的珊瑚粉
        static let primary = SwiftUI.Color(red: 0.95, green: 0.55, blue: 0.62)
        /// 辅助：奶油底
        static let cream = SwiftUI.Color(red: 0.99, green: 0.97, blue: 0.94)
        /// 暖棕（文字/标题）
        static let warmBrown = SwiftUI.Color(red: 0.36, green: 0.30, blue: 0.27)
        /// 柔和次要文字
        static let secondaryText = SwiftUI.Color(red: 0.55, green: 0.50, blue: 0.47)
        /// 页面背景
        static let background = SwiftUI.Color(red: 0.98, green: 0.96, blue: 0.93)
        /// 卡片底
        static let card = SwiftUI.Color.white
        /// 柔绿（同步成功等正向状态）
        static let success = SwiftUI.Color(red: 0.55, green: 0.72, blue: 0.58)
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
    /// 柔和卡片阴影。nonisolated：可在 @ViewBuilder 闭包等非隔离上下文中使用。
    nonisolated func bubuCardShadow() -> some View {
        shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}
