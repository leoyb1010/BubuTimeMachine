// MARK: - 设计 token（对照 iOS DesignSystem/BubuTheme.swift 暖色系）
export class BubuColor {
  static readonly primary = '#F28C9E';        // 珊瑚粉
  static readonly warmBrown = '#5C473D';
  static readonly cream = '#FCF6EC';
  static readonly card = '#FFFFFF';
  static readonly secondaryText = '#8C8078';
  static readonly success = '#7FB069';
}

export class BubuRadius {
  static readonly card = 20;
  static readonly small = 14;
}

// 统一卡片阴影（对照 iOS bubuCardShadow）。按压反馈交给各组件的 clickEffect。
@Extend(Column)
export function bubuCardCol() {
  .backgroundColor(BubuColor.card)
  .borderRadius(BubuRadius.card)
  .shadow({ radius: 10, color: '#14000000', offsetY: 3 })
  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
}
