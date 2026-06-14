// MARK: - 纸纹材质叠加（对照 iOS DesignSystem/PaperTextureOverlay.swift，Wave J §2.3）
// 给「时光机」纸的温度，而不是手机屏的玻璃感。
// - 纹理透明度封顶 5%；浅色主题 multiply、深色（星夜）用亮噪点 screen；
// - 静态平铺图，零每帧成本；姥姥模式（最大字号）下自动关闭。
// SwiftUI .blendMode(.multiply/.screen) → ArkUI Image.blendMode(BlendMode.MULTIPLY/SCREEN)。
// NOTE: 纸纹位图 paper-grain / paper-fiber / paper-fiber-light 需放入 resources/rawfile 或 media；
//       缺图时此组件渲染为空（不报错）。

import { PaperTexture } from '../theme/ThemeManager';

@Component
export struct PaperTextureOverlay {
  texture: PaperTexture = PaperTexture.grain;
  isDark: boolean = false;
  // 姥姥模式（最大字号）由调用方下传；为 true 时关闭纹理，对比度优先。
  largeText: boolean = false;

  private imageName(): string {
    // 对照 iOS imageName 映射。
    if (this.texture === PaperTexture.fiber) {
      return this.isDark ? 'paper-fiber-light' : 'paper-fiber';
    }
    if (this.texture === PaperTexture.grain) {
      return this.isDark ? 'paper-fiber-light' : 'paper-grain';
    }
    return 'paper-grain';
  }

  build() {
    // none 或大字号：不渲染纹理。
    if (this.texture !== PaperTexture.none && !this.largeText) {
      Image($rawfile(this.imageName() + '.png'))
        .width('100%')
        .height('100%')
        .objectRepeat(ImageRepeat.XY)         // 平铺（对照 resizingMode: .tile）
        .blendMode(this.isDark ? BlendMode.SCREEN : BlendMode.MULTIPLY)
        .opacity(this.isDark ? 0.05 : 0.04)
        .hitTestBehavior(HitTestMode.None)    // 不拦截手势（对照 allowsHitTesting(false)）
    }
  }
}
