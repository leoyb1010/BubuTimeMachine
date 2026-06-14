// MARK: - 奶油马卡龙视觉组件库 · 补全包（对照 iOS DesignSystem/MacaronComponents2.swift）
// 药丸标签、数字滚动、点亮迸发、迷你星座。只负责外观/氛围，不持有业务逻辑。
// 动画一律 reduceMotion 兜底；迸发只在一次性事件用。

import { BubuColor } from '../theme/BubuTheme';

// MARK: 药丸标签（对照设计稿 MTag / iOS BubuTag）
@Component
export struct BubuTag {
  text: string = '';
  bg: string = BubuColor.cream2;
  fg: string = BubuColor.warmBrown;

  build() {
    Text(this.text)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.fg)
      .height(24)
      .padding({ left: 11, right: 11 })
      .backgroundColor(this.bg)
      .borderRadius(12)
  }
}

// MARK: 数字滚动（对照设计稿 useCountUp，easeOutCubic / iOS BubuCountUp）
// 用法：BubuCountUp({ value: 24 })——显示从 0 滚到终值。reduceMotion 时直接显示终值。
@Component
export struct BubuCountUp {
  value: number = 0;
  duration: number = 1.1;     // 秒
  fontSize: number = 28;
  fontColor: string = BubuColor.warmBrown;
  reduceMotion: boolean = false;
  @State private shown: number = 0;

  aboutToAppear(): void {
    this.animate();
  }

  // value 变化时重跑（ArkUI 用 @Watch；这里在 build 内不便监听，靠父组件重建近似）。
  private animate(): void {
    if (this.reduceMotion || this.value <= 0) { this.shown = this.value; return; }
    this.shown = 0;
    const steps: number = Math.min(this.value, 60);
    if (steps <= 0) { this.shown = this.value; return; }
    for (let i = 1; i <= steps; i++) {
      const p: number = i / steps;
      const eased: number = 1 - Math.pow(1 - p, 3);   // easeOutCubic
      const target: number = Math.round(this.value * eased);
      setTimeout(() => {
        this.shown = (i === steps) ? this.value : target;
      }, this.duration * 1000 * p);
    }
  }

  build() {
    Text(this.shown.toString())
      .fontSize(this.fontSize)
      .fontWeight(FontWeight.Bolder)
      .fontColor(this.fontColor)
  }
}

// MARK: 点亮迸发（对照设计稿 MacBurst / iOS BubuBurst）
// 从中心放射的星点，一次性扩散 + 淡出。只在一次性事件用。
@Component
export struct BubuBurst {
  count: number = 14;
  radius: number = 92;
  colors: string[] = [BubuColor.primary, BubuColor.butter, BubuColor.lav, BubuColor.mint, BubuColor.pink];
  reduceMotion: boolean = false;
  @State private fired: boolean = false;

  aboutToAppear(): void {
    if (this.reduceMotion) return;
    animateTo({ duration: 1000, curve: Curve.EaseOut }, () => { this.fired = true; });
  }

  @Builder
  private particle(i: number) {
    // 角度与距离按索引散开（对照 iOS 的 angle/dist 公式）。
    Polygon()
      .width(7 + (i % 3) * 4)
      .height(7 + (i % 3) * 4)
      .points([[0.5, 0], [1, 0.5], [0.5, 1], [0, 0.5]])
      .fill(this.colors[i % this.colors.length])
      .translate({
        x: Math.cos((i / this.count) * 2 * Math.PI + i * 0.31) *
           (this.fired ? this.radius * (0.78 + (i % 3) * 0.12) : 0),
        y: Math.sin((i / this.count) * 2 * Math.PI + i * 0.31) *
           (this.fired ? this.radius * (0.78 + (i % 3) * 0.12) : 0)
      })
      .opacity(this.fired ? 0 : 1)
      .scale({ x: this.fired ? 0.4 : 0.3, y: this.fired ? 0.4 : 0.3 })
  }

  build() {
    Stack() {
      ForEach(rangeArray(this.count), (i: number) => {
        this.particle(i);
      }, (i: number) => i.toString())
    }
    .hitTestBehavior(HitTestMode.None)
  }
}

// MARK: 迷你星座（对照设计稿 MacMiniConstellation / iOS BubuMiniConstellation）
// 首页双卡用。已点亮颗数决定连线长度与亮点数。
@Component
export struct BubuMiniConstellation {
  done: number = 8;
  consSize: number = 64;
  // 锚点（设计稿 96×96 viewBox 比例坐标）。
  private readonly pts: Array<[number, number]> = [
    [14, 46], [40, 26], [66, 50], [30, 70], [58, 74], [82, 38]
  ];
  private readonly hues: number[] = [20, 330, 50, 270, 150, 200];
  private readonly motifs: string[] = ['♥', '🐶', '🧸', '✿', '★', '🐾'];

  build() {
    Stack() {
      ForEach(rangeArray(this.pts.length), (i: number) => {
        this.starDot(i);
      }, (i: number) => i.toString())
    }
    .width(this.consSize)
    .height(this.consSize)
  }

  @Builder
  private starDot(i: number) {
    Text(this.motifs[i % this.motifs.length])
      .fontSize(i < Math.min(this.done, this.pts.length) ? 13 : 9)
      .fontWeight(FontWeight.Bolder)
      .fontColor(i < Math.min(this.done, this.pts.length)
        ? BubuColor.deepRose : BubuColor.secondaryText)
      .textAlign(TextAlign.Center)
      .width(i < Math.min(this.done, this.pts.length) ? 23 : 14)
      .height(i < Math.min(this.done, this.pts.length) ? 23 : 14)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .position({
        x: this.pts[i][0] / 96 * this.consSize,
        y: this.pts[i][1] / 96 * this.consSize
      })
  }
}

// 工具：生成 [0, n) 数组（ArkUI ForEach 需要数组数据源）。
export function rangeArray(n: number): number[] {
  const arr: number[] = [];
  for (let i = 0; i < n; i++) { arr.push(i); }
  return arr;
}
