// MARK: - App 图标随主题切换（对照 iOS DesignSystem/AppIconManager.swift）
// 每套主题一枚备用图标；切换主题时同步换桌面图标。
// HarmonyOS API 26 使用 app.json5 alternateIcons + bundleManager.setAlternateIcon。

import { bundleManager } from '@kit.AbilityKit';

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
      case 'dusk': return 'AppIcon-peach';
      default: return null;
    }
  }

  /// 应用某主题对应的图标。生日月（布布生日所在月）优先用生日图标。
  /// 对照 iOS apply(themeId:isBirthdayMonth:)。
  static async apply(themeId: string, isBirthdayMonth: boolean = false): Promise<void> {
    const target: string | null = isBirthdayMonth ? 'AppIcon-birthday' : AppIconManager.iconName(themeId);
    try {
      await bundleManager.setAlternateIcon(target ?? '');
    } catch (e) {
      // 图标是非关键路径；桌面不支持或设置失败时不影响主题本身。
    }
  }
}
