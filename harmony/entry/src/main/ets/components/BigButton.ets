// MARK: - 超大主按钮（适老）（对照 iOS DesignSystem/BigButton.swift）
// 首页主动作按钮。马卡龙渐变、大字、轻点缩放反馈。
// SwiftUI Button + LinearGradient → ArkUI 可点 Column + .linearGradient + clickEffect。

import { BubuColor, BubuFont, BubuRadius, BubuShadow, BubuGradient } from '../theme/BubuTheme';

@Component
export struct BigButton {
  title: string = '';
  // SF Symbol 名在 iOS；HarmonyOS 用 emoji/字符或资源图标占位。
  iconText: string = '♡';
  onTap: () => void = () => {};
  @State private pressed: boolean = false;

  build() {
    Column({ space: 16 }) {
      Text(this.iconText)
        .fontSize(58)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
      Text(this.title)
        .fontSize(BubuFont.title)
        .fontWeight(FontWeight.Bolder)
        .fontColor('#FFFFFF')
      Text('轻点打开 · 上下滑动浏览')
        .fontSize(BubuFont.caption)
        .fontColor('#FFFFFF')
        .opacity(0.86)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height(176)
    .linearGradient({
      angle: BubuGradient.angleTopLeadingToBottomTrailing,
      // 对照 iOS：primary → primary.opacity(0.82)。#D1 ≈ 82% alpha 前缀。
      colors: [[BubuColor.primary, 0.0], ['#D1F28C9E', 1.0]]
    })
    .borderRadius(BubuRadius.button)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
    // 只在明确点按时做轻微缩放反馈（对照 BigButtonStyle，不拦截滚动）。
    .scale({ x: this.pressed ? 0.98 : 1, y: this.pressed ? 0.98 : 1 })
    .animation({ duration: 150, curve: Curve.EaseOut })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) { this.pressed = true; }
      else if (e.type === TouchType.Up || e.type === TouchType.Cancel) { this.pressed = false; }
    })
    .onClick(() => { this.onTap(); })
  }
}
