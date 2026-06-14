// MARK: - 中文日期格式（对照 iOS DesignSystem/BubuDateFormat.swift）
// 统一中文界面的日期显示，避免跟随设备地区变成英文。纯函数。
// iOS 用 Date.FormatStyle(.locale(zh_CN))；HarmonyOS 用 @ohos.intl DateTimeFormat 固定 zh-CN。

import { intl } from '@kit.LocalizationKit';

export class BubuDateFormat {
  private static readonly zh = 'zh-CN';

  /// 缩写日期（如 2026年6月14日 / 6月14日，视系统而定）。对照 abbreviated date。
  static shortDate(date: Date): string {
    const fmt = new intl.DateTimeFormat(BubuDateFormat.zh,
      { year: 'numeric', month: 'short', day: 'numeric' });
    return fmt.format(date);
  }

  /// 长日期。对照 long date。
  static longDate(date: Date): string {
    const fmt = new intl.DateTimeFormat(BubuDateFormat.zh,
      { year: 'numeric', month: 'long', day: 'numeric' });
    return fmt.format(date);
  }

  /// 缩写日期 + 短时间。对照 abbreviated date + shortened time。
  static shortDateTime(date: Date): string {
    const fmt = new intl.DateTimeFormat(BubuDateFormat.zh,
      { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
    return fmt.format(date);
  }

  /// 短时间（时:分）。对照 shortened time。
  static shortTime(date: Date): string {
    const fmt = new intl.DateTimeFormat(BubuDateFormat.zh,
      { hour: '2-digit', minute: '2-digit' });
    return fmt.format(date);
  }

  /// 年月日。对照 .year().month().day()。
  static yearMonthDay(date: Date): string {
    const fmt = new intl.DateTimeFormat(BubuDateFormat.zh,
      { year: 'numeric', month: 'numeric', day: 'numeric' });
    return fmt.format(date);
  }

  /// 月日。对照 .month().day()。
  static monthDay(date: Date): string {
    const fmt = new intl.DateTimeFormat(BubuDateFormat.zh,
      { month: 'numeric', day: 'numeric' });
    return fmt.format(date);
  }
}
