// MARK: - App 图标随主题切换（对照 iOS DesignSystem/AppIconManager.swift）
// 每套主题一枚备用图标；切换主题时同步换桌面图标。
// NOTE: HarmonyOS 的桌面图标切换机制与 iOS setAlternateIconName 不同——
//       需在 module.json5 声明多组 abilities/skills 或通过 LauncherAbility 动态换肤，
//       且通常需用户确认。此处保留 iOS 的「主题 id → 图标名」映射作为忠实端口的逻辑落点，
//       apply 为可编译桩，真正切换桌面图标的平台 API 待接入。

export class AppIconManager {
  /// 主题 id → 备用图标名。珊瑚是主图标，返回 null 走默认（飞碟·布布的时光机）。
  static iconName(themeId: string): string | null {
    switch (themeId) {
      case 'coral': return null;
      case 'sky': return 'AppIcon-sky';
      case 'mint': return 'AppIcon-mint';
      case 'lavender': return 'AppIcon-lavender';
      case 'peach': return 'AppIcon-peach';
      case 'night': return 'AppIcon-night';
      case 'cream': return 'AppIcon-cream';
      default: return null;
    }
  }

  /// 应用某主题对应的图标。生日月（布布生日所在月）优先用生日图标。
  /// 对照 iOS apply(themeId:isBirthdayMonth:)。
  static apply(themeId: string, isBirthdayMonth: boolean = false): void {
    const target: string | null = isBirthdayMonth ? 'AppIcon-birthday' : AppIconManager.iconName(themeId);
    // NOTE: HarmonyOS 桌面图标动态切换 API 待接入；当前仅记录目标，不实际切换。
    // 失败/未实现静默：图标切换非关键路径，不打扰用户。
    void target;
  }
}
