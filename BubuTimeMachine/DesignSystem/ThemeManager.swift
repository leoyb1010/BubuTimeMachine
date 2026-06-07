import SwiftUI
import Observation

// MARK: - 主题定义
/// 一套完整的视觉主题：主色、辅色、背景风格。专属布布，可切换。
struct BubuThemeDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let primaryHex: String
    let secondaryHex: String
    let backgroundStyle: BackgroundStyle

    enum BackgroundStyle: Hashable, Sendable {
        case solid(String)                      // 纯色 hex
        case gradient(String, String)           // 双色渐变 hex
    }

    var primary: Color { Color(hex: primaryHex) }
    var secondary: Color { Color(hex: secondaryHex) }

    static let all: [BubuThemeDefinition] = [
        .init(id: "coral", name: "珊瑚暖阳", primaryHex: "#F28C9E", secondaryHex: "#F2B705",
              backgroundStyle: .gradient("#FFF5F0", "#FDEDE6")),
        .init(id: "sky", name: "晴空蓝", primaryHex: "#5B8DEF", secondaryHex: "#73C2FB",
              backgroundStyle: .gradient("#F0F6FF", "#E6F0FD")),
        .init(id: "mint", name: "薄荷绿", primaryHex: "#5BB98C", secondaryHex: "#9BE0C0",
              backgroundStyle: .gradient("#F0FBF5", "#E6F7EE")),
        .init(id: "lavender", name: "薰衣草", primaryHex: "#8E7CC3", secondaryHex: "#C3B1E1",
              backgroundStyle: .gradient("#F6F2FF", "#EFE8FD")),
        .init(id: "peach", name: "蜜桃粉", primaryHex: "#FF9F8E", secondaryHex: "#FFD3C2",
              backgroundStyle: .gradient("#FFF4F0", "#FFE9E2")),
        .init(id: "night", name: "星夜", primaryHex: "#F2B705", secondaryHex: "#F28C9E",
              backgroundStyle: .gradient("#2B2A3D", "#1E1D2B")),
    ]

    static let `default` = all[0]

    /// 背景是否偏暗（决定文字用浅色还是深色）。
    var isDark: Bool { id == "night" }
}

// MARK: - 首页背景模式
enum HeroBackgroundMode: String, CaseIterable, Sendable {
    case theme = "主题背景"
    case photo = "布布照片"
}

// MARK: - 主题管理器
/// 持有当前主题、首页背景偏好，持久化到 UserDefaults。全局注入。
@Observable
@MainActor
final class ThemeManager {
    var currentThemeId: String {
        didSet { UserDefaults.standard.set(currentThemeId, forKey: Self.themeKey) }
    }
    var heroModeRaw: String {
        didSet { UserDefaults.standard.set(heroModeRaw, forKey: Self.heroKey) }
    }

    var theme: BubuThemeDefinition {
        BubuThemeDefinition.all.first { $0.id == currentThemeId } ?? .default
    }

    var heroMode: HeroBackgroundMode {
        get { HeroBackgroundMode(rawValue: heroModeRaw) ?? .theme }
        set { heroModeRaw = newValue.rawValue }
    }

    private static let themeKey = "bubu.theme.id"
    private static let heroKey = "bubu.theme.heroMode"

    init() {
        self.currentThemeId = UserDefaults.standard.string(forKey: Self.themeKey)
            ?? BubuThemeDefinition.default.id
        self.heroModeRaw = UserDefaults.standard.string(forKey: Self.heroKey)
            ?? HeroBackgroundMode.theme.rawValue
    }

    func select(_ theme: BubuThemeDefinition) {
        withAnimation(.smooth(duration: 0.4)) {
            currentThemeId = theme.id
        }
    }
}

// MARK: - Color hex 工具
extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((rgb >> 24) & 0xFF) / 255
            g = Double((rgb >> 16) & 0xFF) / 255
            b = Double((rgb >> 8) & 0xFF) / 255
            a = Double(rgb & 0xFF) / 255
        } else {
            r = Double((rgb >> 16) & 0xFF) / 255
            g = Double((rgb >> 8) & 0xFF) / 255
            b = Double(rgb & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
