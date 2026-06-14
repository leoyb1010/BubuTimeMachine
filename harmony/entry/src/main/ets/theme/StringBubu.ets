// MARK: - 字符串助手（对照 iOS DesignSystem/String+Bubu.swift）
// iOS 为 String 扩展 bubuTrimmed；ArkTS 不支持扩展原始类型，改为静态工具函数。

export class StringBubu {
  /// 去首尾空白与换行。全工程共享（对照 iOS String.bubuTrimmed）。
  static trimmed(s: string): string {
    return s.replace(/^[\s　]+|[\s　]+$/g, '');
  }
}

/// 便捷自由函数，调用更贴近 iOS 的 value.bubuTrimmed 语义。
export function bubuTrimmed(s: string): string {
  return StringBubu.trimmed(s);
}
