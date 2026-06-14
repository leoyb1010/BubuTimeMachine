// MARK: - 奶油马卡龙视觉组件库（对照 iOS DesignSystem/MacaronComponents.swift）
// 全局换皮的可复用视觉层。只负责「外观/氛围」，不持有业务逻辑。
// 性能纪律：背景动效低频，绝不在滚动区跑持续重绘。

import { BubuColor, BubuRadius, BubuShadow } from '../theme/BubuTheme';

// MARK: 柔光大色块（背景氛围）——对照 iOS BubuBlob
@Component
export struct BubuBlob {
  color: string = BubuColor.primary;
  blobSize: number = 260;
  blobOpacity: number = 0.5;

  build() {
    // 圆形柔光：blur 模拟马卡龙色球。hitTestBehavior None 不拦截手势。
    Circle()
      .width(this.blobSize)
      .height(this.blobSize)
      .fill(this.color)
      .blur(46)
      .opacity(this.blobOpacity)
      .hitTestBehavior(HitTestMode.None)
  }
}

// MARK: 一整屏柔光氛围背景——对照 iOS BubuBlobBackground
// 几个马卡龙色球漂在奶油底上。静态（不动），零每帧成本。
@Component
export struct BubuBlobBackground {
  tint: string = BubuColor.primary;
  includeBase: boolean = true;

  build() {
    Stack() {
      // 奶油底
      if (this.includeBase) {
        Column().width('100%').height('100%').backgroundColor(BubuColor.background)
      }
      // 几个色球，按比例定位（用 RelativeContainer 太重，这里用 position 百分比近似）
      BubuBlob({ color: BubuColor.peach, blobSize: 280, blobOpacity: 0.45 })
        .position({ x: '4%', y: '6%' })
      BubuBlob({ color: BubuColor.lav, blobSize: 260, blobOpacity: 0.35 })
        .position({ x: '70%', y: '18%' })
      BubuBlob({ color: this.tint, blobSize: 240, blobOpacity: 0.30 })
        .position({ x: '60%', y: '82%' })
      BubuBlob({ color: BubuColor.mint, blobSize: 200, blobOpacity: 0.22 })
        .position({ x: '2%', y: '74%' })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}

// MARK: 闪烁小星——对照 iOS BubuSparkle
// 四角星，呼吸闪烁（透明度 + 缩放 + 微旋）。reduceMotion 时静止。
@Component
export struct BubuSparkle {
  starSize: number = 12;
  color: string = '#FFFFFF';
  animated: boolean = true;
  delay: number = 0;
  // reduceMotion 由调用方传入（HarmonyOS 无逐一对应环境变量，从 AccessibilityKit 读取后下传）。
  reduceMotion: boolean = false;
  @State private on: boolean = false;

  aboutToAppear(): void {
    if (!this.animated || this.reduceMotion) return;
    // 循环呼吸：easeInOut 1.3s 往返。delay 用 setTimeout 错峰。
    setTimeout(() => {
      animateTo({
        duration: 1300,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate
      }, () => { this.on = true; });
    }, this.delay * 1000);
  }

  build() {
    // 用对角线菱形近似四角星（Path 在 ArkUI 较繁，菱形 + 旋转给到神似）。
    Polygon()
      .width(this.starSize)
      .height(this.starSize)
      .points([
        [this.starSize * 0.5, 0],
        [this.starSize, this.starSize * 0.5],
        [this.starSize * 0.5, this.starSize],
        [0, this.starSize * 0.5]
      ])
      .fill(this.color)
      .opacity(this.animated && !this.reduceMotion ? (this.on ? 1 : 0.35) : 0.9)
      .scale({ x: this.animated && !this.reduceMotion ? (this.on ? 1.1 : 0.7) : 1,
               y: this.animated && !this.reduceMotion ? (this.on ? 1.1 : 0.7) : 1 })
      .rotate({ angle: this.animated && !this.reduceMotion ? (this.on ? 20 : 0) : 0 })
      .hitTestBehavior(HitTestMode.None)
  }
}

// MARK: 进度环——对照 iOS BubuProgressRing
@Component
export struct BubuProgressRing {
  value: number = 0;
  total: number = 0;
  ringSize: number = 64;
  stroke: number = 8;
  color: string = BubuColor.primary;
  track: string = BubuColor.cream2;

  private progress(): number {
    return this.total <= 0 ? 0 : this.value / this.total;
  }

  build() {
    Stack() {
      // 轨道
      Circle()
        .width(this.ringSize)
        .height(this.ringSize)
        .fill('#00000000')
        .stroke(this.track)
        .strokeWidth(this.stroke)
      // 进度（Progress Ring 类型，平滑动画）
      Progress({ value: this.progress() * 100, total: 100, type: ProgressType.Ring })
        .width(this.ringSize)
        .height(this.ringSize)
        .color(this.color)
        .style({ strokeWidth: this.stroke })
        .animation({ duration: 1000, curve: Curve.EaseOut })
    }
    .width(this.ringSize)
    .height(this.ringSize)
  }
}

// MARK: - 卡片样式（@Styles，对照 iOS bubuMacaronCard / bubuPrimaryButton）
// 统一的奶油卡片外观：白底、马卡龙圆角、暖玫瑰柔影。
@Styles
function bubuMacaronCardStyle() {
  .padding(16)
  .backgroundColor(BubuColor.card)
  .borderRadius(BubuRadius.card)
  .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
}
