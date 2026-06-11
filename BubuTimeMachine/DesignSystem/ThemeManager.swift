import SwiftUI
import UIKit
import Observation

// MARK: - 主题定义
/// 一套完整的视觉主题：不止主色辅色，而是「渗进每个像素」的完整语义包。
/// 新增字段让主题决定卡片/填充/发丝线的色相、首页 mesh 控制点、强调渐变、纸纹与水印。
struct BubuThemeDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let primaryHex: String
    let secondaryHex: String
    let backgroundStyle: BackgroundStyle

    // 新增 —— 让主题渗进每个像素（Wave J §2.1）
    /// 卡片/softFill/hairline 的色相偏移基色：表面色统一向它做 5–8% 偏移，6 套主题立刻「套色彻底」。
    let surfaceTintHex: String
    /// 首页 hero 区 MeshGradient 的控制点颜色（4–6 个）。
    let meshPalette: [String]
    /// 主按钮/进度环的强调渐变对。
    let accentStartHex: String
    let accentEndHex: String
    /// 纸纹质感。
    let paperTexture: PaperTexture
    /// tab bar 选中色（nil 则用 primary）。
    let tabTintHex: String?

    enum BackgroundStyle: Hashable, Sendable {
        case solid(String)                      // 纯色 hex
        case gradient(String, String)           // 双色渐变 hex
    }

    enum PaperTexture: String, Hashable, Sendable {
        case none, grain, fiber
    }

    var primary: Color { Color(hex: primaryHex) }
    var secondary: Color { Color(hex: secondaryHex) }
    var surfaceTint: Color { Color(hex: surfaceTintHex) }
    var meshColors: [Color] { meshPalette.map { Color(hex: $0) } }
    var accentGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: accentStartHex), Color(hex: accentEndHex)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var tabTint: Color { tabTintHex.map { Color(hex: $0) } ?? primary }

    static let all: [BubuThemeDefinition] = [
        .init(id: "coral", name: "珊瑚暖阳", primaryHex: "#F28C9E", secondaryHex: "#F2B705",
              backgroundStyle: .gradient("#FFF5F0", "#FDEDE6"),
              surfaceTintHex: "#F28C9E",
              meshPalette: ["#FFE3D5", "#FFD0C2", "#FFC2A8", "#FFB59E", "#FFE8C2", "#FFF5EC"],
              accentStartHex: "#F28C9E", accentEndHex: "#F2B705", paperTexture: .grain, tabTintHex: nil),
        .init(id: "sky", name: "晴空蓝", primaryHex: "#5B8DEF", secondaryHex: "#73C2FB",
              backgroundStyle: .gradient("#F0F6FF", "#E6F0FD"),
              surfaceTintHex: "#5B8DEF",
              meshPalette: ["#DCEBFF", "#C8DEFF", "#B5D4FF", "#A8CBFB", "#D6F0FF", "#EEF6FF"],
              accentStartHex: "#5B8DEF", accentEndHex: "#73C2FB", paperTexture: .grain, tabTintHex: nil),
        .init(id: "mint", name: "薄荷绿", primaryHex: "#5BB98C", secondaryHex: "#9BE0C0",
              backgroundStyle: .gradient("#F0FBF5", "#E6F7EE"),
              surfaceTintHex: "#5BB98C",
              meshPalette: ["#D8F3E5", "#C2EDD6", "#AEE6C8", "#9BE0C0", "#D6F5EC", "#EEFBF4"],
              accentStartHex: "#5BB98C", accentEndHex: "#9BE0C0", paperTexture: .grain, tabTintHex: nil),
        .init(id: "lavender", name: "薰衣草", primaryHex: "#8E7CC3", secondaryHex: "#C3B1E1",
              backgroundStyle: .gradient("#F6F2FF", "#EFE8FD"),
              surfaceTintHex: "#8E7CC3",
              meshPalette: ["#EAE2FB", "#DCD0F5", "#CFC0EF", "#C3B1E1", "#E8DEFB", "#F4EFFE"],
              accentStartHex: "#8E7CC3", accentEndHex: "#C3B1E1", paperTexture: .grain, tabTintHex: nil),
        .init(id: "peach", name: "蜜桃粉", primaryHex: "#FF9F8E", secondaryHex: "#FFD3C2",
              backgroundStyle: .gradient("#FFF4F0", "#FFE9E2"),
              surfaceTintHex: "#FF9F8E",
              meshPalette: ["#FFE3DA", "#FFD6C8", "#FFC8B8", "#FFBBA8", "#FFE8D8", "#FFF4EE"],
              accentStartHex: "#FF9F8E", accentEndHex: "#FFD3C2", paperTexture: .grain, tabTintHex: nil),
        .init(id: "night", name: "星夜", primaryHex: "#F2B705", secondaryHex: "#F28C9E",
              backgroundStyle: .gradient("#2B2A3D", "#1E1D2B"),
              surfaceTintHex: "#8E7CC3",
              meshPalette: ["#2B2A3D", "#322F47", "#3A3656", "#28304D", "#3D3358", "#222134"],
              accentStartHex: "#F2B705", accentEndHex: "#F28C9E", paperTexture: .fiber, tabTintHex: "#F2B705"),
        // 新增精品主题（Wave J §2.4）
        .init(id: "cream", name: "奶油绘本", primaryHex: "#8A6B52", secondaryHex: "#C2A079",
              backgroundStyle: .gradient("#FBF6EC", "#F4EADB"),
              surfaceTintHex: "#C2A079",
              meshPalette: ["#F4EAD9", "#EFE0C9", "#E8D4B5", "#E0C9A3", "#F2E8D6", "#FBF6EC"],
              accentStartHex: "#8A6B52", accentEndHex: "#C2A079", paperTexture: .fiber, tabTintHex: "#8A6B52"),
        .init(id: "dusk", name: "晚霞", primaryHex: "#F2748C", secondaryHex: "#8E6FC9",
              backgroundStyle: .gradient("#FFF0F3", "#F3ECFD"),
              surfaceTintHex: "#C46FA8",
              meshPalette: ["#FFD7DF", "#FFC2D0", "#F2A8C2", "#D98ABF", "#B57CD6", "#8E6FC9"],
              accentStartHex: "#F2748C", accentEndHex: "#8E6FC9", paperTexture: .grain, tabTintHex: "#C46FA8"),
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

    /// 把自身向 `other` 混合 `fraction`（0…1），用于表面色按主题做 5–8% 色相偏移。
    /// 纯 sRGB 线性插值，nonisolated 可在任意上下文调用。
    func mix(with other: Color, by fraction: Double) -> Color {
        let f = min(max(fraction, 0), 1)
        let a = UIColor(self), b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(.sRGB,
                     red: Double(ar + (br - ar) * f),
                     green: Double(ag + (bg - ag) * f),
                     blue: Double(ab + (bb - ab) * f),
                     opacity: Double(aa + (ba - aa) * f))
    }
}
