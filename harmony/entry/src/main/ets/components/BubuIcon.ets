// MARK: - 布布统一功能图标
// 对齐 iOS 的 SF Symbols 语义，但在鸿蒙端用本地 Canvas 矢量绘制，避免 emoji 混搭。

import { BubuColor } from '../theme/BubuTheme';

export class BubuIconName {
  static readonly home: string = 'home';
  static readonly clock: string = 'clock';
  static readonly star: string = 'star';
  static readonly magic: string = 'magic';
  static readonly gear: string = 'gear';
  static readonly calendar: string = 'calendar';
  static readonly moon: string = 'moon';
  static readonly cloudSun: string = 'cloudSun';
  static readonly photo: string = 'photo';
  static readonly video: string = 'video';
  static readonly textBubble: string = 'textBubble';
  static readonly health: string = 'health';
  static readonly plus: string = 'plus';
  static readonly sparkles: string = 'sparkles';
  static readonly sync: string = 'sync';
  static readonly checkCloud: string = 'checkCloud';
  static readonly mic: string = 'mic';
  static readonly waveform: string = 'waveform';
  static readonly send: string = 'send';
  static readonly grid: string = 'grid';
}

@Component
export struct BubuIcon {
  name: string = BubuIconName.home;
  iconSize: number = 22;
  color: string = BubuColor.warmBrown;
  strokeWidth: number = 2.2;
  filled: boolean = false;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  build() {
    Canvas(this.ctx)
      .width(this.iconSize)
      .height(this.iconSize)
      .onReady(() => { this.draw(); })
      .hitTestBehavior(HitTestMode.None)
  }

  private draw(): void {
    const c = this.ctx;
    const w = c.width > 0 ? c.width : this.iconSize;
    const h = c.height > 0 ? c.height : this.iconSize;
    const s = Math.min(w, h);
    c.clearRect(0, 0, w, h);
    c.lineCap = 'round';
    c.lineJoin = 'round';
    c.lineWidth = this.strokeWidth;
    c.strokeStyle = this.color;
    c.fillStyle = this.color;
    switch (this.name) {
      case BubuIconName.home:
        this.home(c, s); break;
      case BubuIconName.clock:
        this.clock(c, s); break;
      case BubuIconName.star:
        this.star(c, s, this.filled); break;
      case BubuIconName.magic:
        this.magic(c, s); break;
      case BubuIconName.gear:
        this.gear(c, s); break;
      case BubuIconName.calendar:
        this.calendar(c, s); break;
      case BubuIconName.moon:
        this.moon(c, s); break;
      case BubuIconName.cloudSun:
        this.cloudSun(c, s); break;
      case BubuIconName.photo:
        this.photo(c, s); break;
      case BubuIconName.video:
        this.video(c, s); break;
      case BubuIconName.textBubble:
        this.textBubble(c, s); break;
      case BubuIconName.health:
        this.health(c, s); break;
      case BubuIconName.plus:
        this.plus(c, s); break;
      case BubuIconName.sparkles:
        this.sparkles(c, s); break;
      case BubuIconName.sync:
        this.sync(c, s); break;
      case BubuIconName.checkCloud:
        this.checkCloud(c, s); break;
      case BubuIconName.mic:
        this.mic(c, s); break;
      case BubuIconName.waveform:
        this.waveform(c, s); break;
      case BubuIconName.send:
        this.send(c, s); break;
      case BubuIconName.grid:
        this.grid(c, s); break;
      default:
        this.sparkles(c, s); break;
    }
  }

  private home(c: CanvasRenderingContext2D, s: number): void {
    c.beginPath();
    c.moveTo(s * 0.18, s * 0.50);
    c.lineTo(s * 0.50, s * 0.22);
    c.lineTo(s * 0.82, s * 0.50);
    c.stroke();
    c.beginPath();
    c.moveTo(s * 0.28, s * 0.48);
    c.lineTo(s * 0.28, s * 0.80);
    c.lineTo(s * 0.43, s * 0.80);
    c.lineTo(s * 0.43, s * 0.61);
    c.lineTo(s * 0.57, s * 0.61);
    c.lineTo(s * 0.57, s * 0.80);
    c.lineTo(s * 0.72, s * 0.80);
    c.lineTo(s * 0.72, s * 0.48);
    c.stroke();
  }

  private clock(c: CanvasRenderingContext2D, s: number): void {
    c.beginPath();
    c.arc(s * 0.50, s * 0.50, s * 0.32, 0, 6.2832);
    c.stroke();
    c.beginPath();
    c.moveTo(s * 0.50, s * 0.31);
    c.lineTo(s * 0.50, s * 0.52);
    c.lineTo(s * 0.64, s * 0.61);
    c.stroke();
  }

  private star(c: CanvasRenderingContext2D, s: number, filled: boolean): void {
    const cx = s * 0.5;
    const cy = s * 0.52;
    const outer = s * 0.36;
    const inner = s * 0.16;
    c.beginPath();
    for (let i = 0; i < 10; i++) {
      const r = i % 2 === 0 ? outer : inner;
      const a = -Math.PI / 2 + i * Math.PI / 5;
      const x = cx + Math.cos(a) * r;
      const y = cy + Math.sin(a) * r;
      if (i === 0) c.moveTo(x, y); else c.lineTo(x, y);
    }
    c.closePath();
    if (filled) c.fill(); else c.stroke();
  }

  private magic(c: CanvasRenderingContext2D, s: number): void {
    c.beginPath();
    c.moveTo(s * 0.28, s * 0.76);
    c.lineTo(s * 0.74, s * 0.30);
    c.stroke();
    this.smallStar(c, s * 0.26, s * 0.28, s * 0.09);
    this.smallStar(c, s * 0.78, s * 0.74, s * 0.07);
  }

  private gear(c: CanvasRenderingContext2D, s: number): void {
    for (let i = 0; i < 8; i++) {
      const a = i * Math.PI / 4;
      c.beginPath();
      c.moveTo(s * 0.50 + Math.cos(a) * s * 0.30, s * 0.50 + Math.sin(a) * s * 0.30);
      c.lineTo(s * 0.50 + Math.cos(a) * s * 0.38, s * 0.50 + Math.sin(a) * s * 0.38);
      c.stroke();
    }
    c.beginPath();
    c.arc(s * 0.50, s * 0.50, s * 0.25, 0, 6.2832);
    c.stroke();
    c.beginPath();
    c.arc(s * 0.50, s * 0.50, s * 0.08, 0, 6.2832);
    c.stroke();
  }

  private calendar(c: CanvasRenderingContext2D, s: number): void {
    this.rectPath(c, s * 0.20, s * 0.25, s * 0.60, s * 0.55);
    c.stroke();
    c.beginPath();
    c.moveTo(s * 0.20, s * 0.40);
    c.lineTo(s * 0.80, s * 0.40);
    c.moveTo(s * 0.35, s * 0.18);
    c.lineTo(s * 0.35, s * 0.30);
    c.moveTo(s * 0.65, s * 0.18);
    c.lineTo(s * 0.65, s * 0.30);
    c.stroke();
  }

  private moon(c: CanvasRenderingContext2D, s: number): void {
    c.beginPath();
    c.arc(s * 0.52, s * 0.48, s * 0.31, Math.PI * 0.18, Math.PI * 1.58);
    c.arc(s * 0.61, s * 0.40, s * 0.25, Math.PI * 1.42, Math.PI * 0.24, true);
    c.closePath();
    c.fill();
    this.smallStar(c, s * 0.78, s * 0.25, s * 0.05);
  }

  private cloudSun(c: CanvasRenderingContext2D, s: number): void {
    c.beginPath();
    c.arc(s * 0.33, s * 0.34, s * 0.15, 0, 6.2832);
    c.stroke();
    c.beginPath();
    c.arc(s * 0.39, s * 0.64, s * 0.16, Math.PI, Math.PI * 1.95);
    c.arc(s * 0.56, s * 0.56, s * 0.18, Math.PI * 1.15, Math.PI * 2.00);
    c.arc(s * 0.68, s * 0.66, s * 0.12, Math.PI * 1.45, 0);
    c.lineTo(s * 0.34, s * 0.78);
    c.stroke();
  }

  private photo(c: CanvasRenderingContext2D, s: number): void {
    this.rectPath(c, s * 0.18, s * 0.24, s * 0.64, s * 0.52);
    c.stroke();
    c.beginPath();
    c.arc(s * 0.66, s * 0.38, s * 0.06, 0, 6.2832);
    c.fill();
    c.beginPath();
    c.moveTo(s * 0.25, s * 0.70);
    c.lineTo(s * 0.42, s * 0.53);
    c.lineTo(s * 0.54, s * 0.65);
    c.lineTo(s * 0.64, s * 0.57);
    c.lineTo(s * 0.78, s * 0.72);
    c.stroke();
  }

  private video(c: CanvasRenderingContext2D, s: number): void {
    this.rectPath(c, s * 0.18, s * 0.30, s * 0.46, s * 0.42);
    c.stroke();
    c.beginPath();
    c.moveTo(s * 0.64, s * 0.43);
    c.lineTo(s * 0.82, s * 0.34);
    c.lineTo(s * 0.82, s * 0.68);
    c.lineTo(s * 0.64, s * 0.59);
    c.stroke();
  }

  private textBubble(c: CanvasRenderingContext2D, s: number): void {
    this.rectPath(c, s * 0.18, s * 0.24, s * 0.64, s * 0.46);
    c.stroke();
    c.beginPath();
    c.moveTo(s * 0.36, s * 0.70);
    c.lineTo(s * 0.27, s * 0.82);
    c.lineTo(s * 0.51, s * 0.70);
    c.moveTo(s * 0.33, s * 0.40);
    c.lineTo(s * 0.67, s * 0.40);
    c.moveTo(s * 0.33, s * 0.55);
    c.lineTo(s * 0.58, s * 0.55);
    c.stroke();
  }

  private health(c: CanvasRenderingContext2D, s: number): void {
    this.rectPath(c, s * 0.24, s * 0.24, s * 0.52, s * 0.52);
    c.stroke();
    c.beginPath();
    c.moveTo(s * 0.50, s * 0.36);
    c.lineTo(s * 0.50, s * 0.64);
    c.moveTo(s * 0.36, s * 0.50);
    c.lineTo(s * 0.64, s * 0.50);
    c.stroke();
  }

  private plus(c: CanvasRenderingContext2D, s: number): void {
    c.beginPath();
    c.moveTo(s * 0.50, s * 0.25);
    c.lineTo(s * 0.50, s * 0.75);
    c.moveTo(s * 0.25, s * 0.50);
    c.lineTo(s * 0.75, s * 0.50);
    c.stroke();
  }

  private sparkles(c: CanvasRenderingContext2D, s: number): void {
    this.smallStar(c, s * 0.42, s * 0.43, s * 0.18);
    this.smallStar(c, s * 0.72, s * 0.24, s * 0.08);
    this.smallStar(c, s * 0.76, s * 0.70, s * 0.06);
  }

  private sync(c: CanvasRenderingContext2D, s: number): void {
    c.beginPath();
    c.arc(s * 0.50, s * 0.50, s * 0.30, Math.PI * 0.25, Math.PI * 1.30);
    c.stroke();
    c.beginPath();
    c.moveTo(s * 0.22, s * 0.42);
    c.lineTo(s * 0.19, s * 0.66);
    c.lineTo(s * 0.40, s * 0.57);
    c.stroke();
    c.beginPath();
    c.arc(s * 0.50, s * 0.50, s * 0.30, Math.PI * 1.25, Math.PI * 2.30);
    c.stroke();
    c.beginPath();
    c.moveTo(s * 0.78, s * 0.58);
    c.lineTo(s * 0.81, s * 0.34);
    c.lineTo(s * 0.60, s * 0.43);
    c.stroke();
  }

  private checkCloud(c: CanvasRenderingContext2D, s: number): void {
    c.beginPath();
    c.arc(s * 0.37, s * 0.60, s * 0.14, Math.PI, Math.PI * 1.85);
    c.arc(s * 0.52, s * 0.50, s * 0.17, Math.PI * 1.18, Math.PI * 2.00);
    c.arc(s * 0.67, s * 0.62, s * 0.11, Math.PI * 1.48, 0);
    c.lineTo(s * 0.35, s * 0.75);
    c.stroke();
    c.beginPath();
    c.moveTo(s * 0.39, s * 0.58);
    c.lineTo(s * 0.48, s * 0.67);
    c.lineTo(s * 0.67, s * 0.43);
    c.stroke();
  }

  private mic(c: CanvasRenderingContext2D, s: number): void {
    this.rectPath(c, s * 0.39, s * 0.18, s * 0.22, s * 0.42);
    c.stroke();
    c.beginPath();
    c.arc(s * 0.50, s * 0.52, s * 0.24, 0, Math.PI);
    c.moveTo(s * 0.50, s * 0.76);
    c.lineTo(s * 0.50, s * 0.86);
    c.moveTo(s * 0.38, s * 0.86);
    c.lineTo(s * 0.62, s * 0.86);
    c.stroke();
  }

  private waveform(c: CanvasRenderingContext2D, s: number): void {
    const bars: number[] = [0.24, 0.48, 0.70, 0.40, 0.60];
    for (let i = 0; i < bars.length; i++) {
      const x = s * (0.22 + i * 0.14);
      const half = s * bars[i] * 0.28;
      c.beginPath();
      c.moveTo(x, s * 0.50 - half);
      c.lineTo(x, s * 0.50 + half);
      c.stroke();
    }
  }

  private send(c: CanvasRenderingContext2D, s: number): void {
    c.beginPath();
    c.moveTo(s * 0.20, s * 0.74);
    c.lineTo(s * 0.80, s * 0.20);
    c.lineTo(s * 0.63, s * 0.82);
    c.lineTo(s * 0.48, s * 0.56);
    c.closePath();
    if (this.filled) c.fill(); else c.stroke();
  }

  private grid(c: CanvasRenderingContext2D, s: number): void {
    const start = s * 0.22;
    const gap = s * 0.22;
    const size = s * 0.13;
    for (let row = 0; row < 3; row++) {
      for (let col = 0; col < 3; col++) {
        this.rectPath(c, start + col * gap, start + row * gap, size, size);
        if (this.filled) c.fill(); else c.stroke();
      }
    }
  }

  private smallStar(c: CanvasRenderingContext2D, cx: number, cy: number, r: number): void {
    c.beginPath();
    c.moveTo(cx, cy - r);
    c.lineTo(cx + r * 0.32, cy - r * 0.32);
    c.lineTo(cx + r, cy);
    c.lineTo(cx + r * 0.32, cy + r * 0.32);
    c.lineTo(cx, cy + r);
    c.lineTo(cx - r * 0.32, cy + r * 0.32);
    c.lineTo(cx - r, cy);
    c.lineTo(cx - r * 0.32, cy - r * 0.32);
    c.closePath();
    c.fill();
  }

  private rectPath(c: CanvasRenderingContext2D, x: number, y: number, w: number, h: number): void {
    c.beginPath();
    c.moveTo(x, y);
    c.lineTo(x + w, y);
    c.lineTo(x + w, y + h);
    c.lineTo(x, y + h);
    c.closePath();
  }
}

@Component
export struct BubuIconBadge {
  name: string = BubuIconName.sparkles;
  badgeSize: number = 36;
  iconSize: number = 18;
  color: string = BubuColor.deepRose;
  fill: string = '#33F28C9E';
  radius: number = 14;
  strokeWidth: number = 2.1;
  filled: boolean = false;

  build() {
    Stack() {
      BubuIcon({
        name: this.name,
        iconSize: this.iconSize,
        color: this.color,
        strokeWidth: this.strokeWidth,
        filled: this.filled
      })
    }
    .width(this.badgeSize)
    .height(this.badgeSize)
    .alignContent(Alignment.Center)
    .backgroundColor(this.fill)
    .borderRadius(this.radius)
  }
}
