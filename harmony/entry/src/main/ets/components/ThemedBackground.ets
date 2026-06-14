// MARK: - 主题感知背景（对照 iOS DesignSystem/ThemedBackground.swift）
// 全 App 统一的页面背景：跟随当前主题的渐变 + 柔光色球氛围 + 纸纹叠加。
// 深色（星夜）主题降低色球透明度，避免抢内容。
// SwiftUI ZStack → ArkUI Stack；LinearGradient → .linearGradient。

import { ThemeManager, BackgroundStyleKind } from '../theme/ThemeManager';
import { BubuColor } from '../theme/BubuTheme';
import { BubuBlobBackground } from './MacaronComponents';
import { PaperTextureOverlay } from './PaperTextureOverlay';

@Component
export struct ThemedBackground {
  // 由父页面注入当前主题管理器（对照 iOS @Environment(AppEnvironment.self)）。
  @ObjectLink theme: ThemeManager;

  build() {
    Stack() {
      // 1) 主题背景（纯色或双色渐变；深色主题用暖黑底）。
      if (this.theme.theme.isDark) {
        Column().width('100%').height('100%').backgroundColor(BubuColor.background)
      } else if (this.theme.theme.backgroundStyle.kind === BackgroundStyleKind.gradient) {
        Column()
          .width('100%').height('100%')
          .linearGradient({
            angle: 180,   // top → bottom
            colors: [
              [this.theme.theme.backgroundStyle.colorA, 0.0],
              [this.theme.theme.backgroundStyle.colorB, 1.0]
            ]
          })
      } else {
        Column().width('100%').height('100%')
          .backgroundColor(this.theme.theme.backgroundStyle.colorA)
      }

      // 2) 奶油马卡龙柔光氛围色球（静态、零每帧成本）。深色降透明度。
      BubuBlobBackground({ tint: this.theme.theme.primary })
        .opacity(this.theme.theme.isDark ? 0.35 : 1.0)

      // 3) 纸纹叠加（封顶 5%，姥姥大字号自动关闭——由调用方控制 largeText）。
      PaperTextureOverlay({ texture: this.theme.theme.paperTexture, isDark: this.theme.theme.isDark })
    }
    .width('100%')
    .height('100%')
  }
}
