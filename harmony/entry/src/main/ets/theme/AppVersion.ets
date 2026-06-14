// MARK: - 应用版本号（对照 iOS DesignSystem/AppVersion.swift）
// 统一从 bundleManager 读取版本信息，供「设置页版本行 / 更新记录 / 升级弹窗」复用。
// iOS 从 Bundle Info.plist 读取；HarmonyOS 用 @kit.AbilityKit bundleManager。
// NOTE: bundleManager 读取为异步；这里在 initialize 时缓存，访问器返回缓存值。

import { bundleManager } from '@kit.AbilityKit';

export class AppVersion {
  private static cachedMarketing: string = '1.0.0';
  private static cachedBuild: string = '1';

  // 在 Ability 启动时调用一次，缓存版本信息。
  static async initialize(): Promise<void> {
    try {
      const info = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      AppVersion.cachedMarketing = info.versionName ?? '1.0.0';
      AppVersion.cachedBuild = info.versionCode !== undefined ? info.versionCode.toString() : '1';
    } catch (e) {
      // 读取失败保留默认值
    }
  }

  /// 营销版本号，如 "1.2.0"（对照 CFBundleShortVersionString）。
  static get marketing(): string { return AppVersion.cachedMarketing; }

  /// 构建号，如 "2026061303"（对照 CFBundleVersion）。
  static get build(): string { return AppVersion.cachedBuild; }

  /// 展示用："v1.2.0"。
  static get displayShort(): string { return 'v' + AppVersion.cachedMarketing; }

  /// 展示用（带构建号）："v1.2.0 (2026061303)"。
  static get displayFull(): string {
    return 'v' + AppVersion.cachedMarketing + ' (' + AppVersion.cachedBuild + ')';
  }
}
