import UIKit

// MARK: - App 图标随主题切换
/// 每套主题一枚备用图标；切换主题时同步换 Home Screen 图标。
/// 生日月可强制「生日彩带」图标。`setAlternateIconName(nil)` 回到主图标（飞碟·布布的时光机）。
@MainActor
enum AppIconManager {
    /// 主题 id → 备用图标名。珊瑚是主图标，传 nil 走默认。
    static func iconName(forThemeId id: String) -> String? {
        switch id {
        case "coral": return nil               // 默认主题用主图标（飞碟·布布的时光机）
        case "sky": return "AppIcon-sky"
        case "mint": return "AppIcon-mint"
        case "lavender": return "AppIcon-lavender"
        case "peach": return "AppIcon-peach"
        case "night": return "AppIcon-night"
        case "cream": return "AppIcon-cream"
        // 晚霞暂无专属图标素材，映射到色系最接近的蜜桃粉图标（P2i）
        case "dusk": return "AppIcon-peach"
        default: return nil
        }
    }

    /// 应用某主题对应的图标（若与当前不同才切，避免系统弹无谓提示）。
    /// 生日月（布布生日所在月）优先用生日图标。
    static func apply(themeId: String, isBirthdayMonth: Bool = false) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let target = isBirthdayMonth ? "AppIcon-birthday" : iconName(forThemeId: themeId)
        guard target != UIApplication.shared.alternateIconName else { return }
        UIApplication.shared.setAlternateIconName(target) { _ in
            // 失败静默：图标切换非关键路径，不打扰用户。
        }
    }
}
