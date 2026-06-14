// MARK: - 液态玻璃表面（对照 iOS DesignSystem/BubuLiquidGlass.swift）
// iOS 26 用系统 Liquid Glass（glassEffect）；HarmonyOS 用 backgroundBlurStyle + 圆角 + 描边近似。
// SwiftUI .ultraThinMaterial → ArkUI BlurStyle.Thin/Regular。
// 用法（@Extend，链式套在容器上）：Column(){...}.bubuGlassSurface()

import { BubuRadius } from '../theme/BubuTheme';

// 常规玻璃表面：薄模糊 + 马卡龙圆角 + 半透明白描边（对照 bubuGlassSurface）。
@Extend(Column)
export function bubuGlassSurface() {
  .borderRadius(BubuRadius.card)
  .backgroundBlurStyle(BlurStyle.Thin)
  .border({ width: 1, color: '#76FFFFFF' })   // white opacity 0.46 近似
}

// 更厚的玻璃（弹层/卡片，对照 CeremonyAnimation 的 ultraThinMaterial + stroke）。
@Extend(Column)
export function bubuGlassCard() {
  .borderRadius(32)
  .backgroundBlurStyle(BlurStyle.Regular)
  .border({ width: 1, color: '#76FFFFFF' })
  .shadow({ radius: 24, color: '#24000000', offsetY: 12 })
}

// Stack 版玻璃表面（ZStack 场景用）。
@Extend(Stack)
export function bubuGlassStack() {
  .borderRadius(BubuRadius.card)
  .backgroundBlurStyle(BlurStyle.Thin)
  .border({ width: 1, color: '#76FFFFFF' })
}

// 可跨文件复用的玻璃容器（@Extend 在本 ArkUI 版本不能跨文件链用，故另提供 @Component 包裹）。
// 用法：BubuGlassPanel() { 内容 }
@Component
export struct BubuGlassPanel {
  @BuilderParam content: () => void;
  thick: boolean = false;

  build() {
    Column() {
      this.content()
    }
    .borderRadius(this.thick ? 32 : BubuRadius.card)
    .backgroundBlurStyle(this.thick ? BlurStyle.Regular : BlurStyle.Thin)
    .border({ width: 1, color: '#76FFFFFF' })
  }
}
