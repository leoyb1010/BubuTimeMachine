// MARK: - 成长星座盘（对照 iOS Features/Milestones/BubuConstellationView.swift）
// 把里程碑可视化成星座：已达成 = 发光大星（带光晕 + 连线），未达成 = 灰点。
// 只负责「展示方式」，里程碑数据与点亮逻辑由外部提供。
// iOS 用 GeometryReader + ZStack + Path 连线；ArkUI 用 Canvas 自绘连线 / 光晕 / 星体，
// 上层叠加可点击的标签按钮（点星进详情）。
// 布局math（锚点模板 + 黄金角螺旋）逐行对照 iOS layout()。

import { Milestone } from '../models/Models';
import { BubuColor } from '../theme/BubuTheme';
import { BubuSparkle } from '../components/MacaronComponents';

interface PtRatio { x: number; y: number; }
interface Pt { x: number; y: number; }

@Component
export struct BubuConstellationView {
  milestones: Milestone[] = [];           // 已筛选
  primary: string = BubuColor.primary;
  onTapStar: (m: Milestone) => void = () => {};

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  // 画布尺寸（onAreaChange 测得）。初值给一个合理默认，避免首帧 0。
  @State private boardW: number = 340;
  @State private boardH: number = 320;

  // 设计稿手工锚点（在画布上的比例坐标，错落有致，绝不挤成网格）。对照 iOS anchorTemplate。
  private static readonly anchorTemplate: PtRatio[] = [
    { x: 0.17, y: 0.09 }, { x: 0.44, y: 0.185 }, { x: 0.77, y: 0.12 },
    { x: 0.29, y: 0.34 }, { x: 0.62, y: 0.41 }, { x: 0.22, y: 0.57 },
    { x: 0.53, y: 0.63 }, { x: 0.79, y: 0.55 }, { x: 0.38, y: 0.815 },
    { x: 0.68, y: 0.87 }
  ];

  private isAchieved(m: Milestone): boolean {
    return m.happenedAt !== undefined && m.happenedAt !== null;
  }

  private achievedList(): Milestone[] {
    return this.milestones.filter((m: Milestone) => this.isAchieved(m));
  }

  // 星盘显示一部分未点亮星，避免 0 点亮时空白；已点亮星保持发光并连线。对照 iOS shown。
  private shown(): Milestone[] {
    const maxStars: number = 18;
    const lit: Milestone[] = this.achievedList().slice(0, maxStars);
    const locked: Milestone[] = this.milestones.filter((m: Milestone) => !this.isAchieved(m));
    return lit.concat(locked).slice(0, maxStars);
  }

  private totalCount(): number { return this.milestones.length; }

  // 首页式紧凑星盘高度（对照 iOS starboardHeight）。
  private starboardHeight(): number {
    return Math.max(300, Math.min(370, 260 + this.shown().length * 5));
  }

  // 锚点布局：前 10 用模板比例；超出部分用黄金角螺旋错落填充。对照 iOS layout()。
  private layout(count: number): Pt[] {
    const out: Pt[] = [];
    if (count <= 0) { return out; }
    const pad: number = 28;
    const w: number = this.boardW - pad * 2;
    const h: number = this.boardH - pad * 2;
    const anchors: PtRatio[] = BubuConstellationView.anchorTemplate;
    for (let i = 0; i < count; i++) {
      if (i < anchors.length) {
        const a: PtRatio = anchors[i];
        out.push({ x: pad + a.x * w, y: pad + a.y * h });
      } else {
        // 螺旋延展（黄金角 137.5°），落在下半区，避免与模板重叠。
        const k: number = i - anchors.length;
        const ang: number = k * 2.399963;
        const rad: number = 0.18 + 0.06 * (k % 5);
        const cx: number = 0.5 + Math.cos(ang) * rad;
        const cy: number = 0.5 + Math.sin(ang) * rad * 0.7;
        out.push({
          x: pad + Math.min(0.92, Math.max(0.08, cx)) * w,
          y: pad + Math.min(0.95, Math.max(0.05, cy)) * h
        });
      }
    }
    return out;
  }

  private starColor(m: Milestone): string {
    let hash: number = 0;
    for (let i = 0; i < m.title.length; i++) {
      hash = (hash * 31 + m.title.charCodeAt(i)) | 0;
    }
    return BubuColor.hue(Math.abs(hash) % 360, 0.82);
  }

  // Canvas 绘制：连线 + 光晕 + 星体。对照 iOS constellationLines + ConstellationStar。
  private draw(): void {
    const c: CanvasRenderingContext2D = this.ctx;
    c.clearRect(0, 0, this.boardW, this.boardH);
    const shown: Milestone[] = this.shown();
    const positions: Pt[] = this.layout(shown.length);
    if (positions.length === 0) { return; }

    // 1) 已点亮星顺序连线（底层浅粉粗描边 + 上层 rose→lav 渐变细线，对照双层 path）。
    const litPts: Pt[] = [];
    for (let i = 0; i < shown.length; i++) {
      if (this.isAchieved(shown[i]) && i < positions.length) { litPts.push(positions[i]); }
    }
    if (litPts.length >= 2) {
      // 底层粗描边（浅粉，0.55 透明）
      c.lineWidth = 6;
      c.lineCap = 'round';
      c.lineJoin = 'round';
      c.strokeStyle = '#8CFFC2D6';
      c.beginPath();
      for (let k = 0; k < litPts.length; k++) {
        if (k === 0) { c.moveTo(litPts[k].x, litPts[k].y); } else { c.lineTo(litPts[k].x, litPts[k].y); }
      }
      c.stroke();
      // 上层渐变细线（primary → lav）
      const grad: CanvasGradient = c.createLinearGradient(
        litPts[0].x, litPts[0].y,
        litPts[litPts.length - 1].x, litPts[litPts.length - 1].y);
      grad.addColorStop(0, BubuColor.primary);
      grad.addColorStop(1, BubuColor.lav);
      c.lineWidth = 2.5;
      c.strokeStyle = grad;
      c.beginPath();
      for (let k = 0; k < litPts.length; k++) {
        if (k === 0) { c.moveTo(litPts[k].x, litPts[k].y); } else { c.lineTo(litPts[k].x, litPts[k].y); }
      }
      c.stroke();
    }

    // 2) 星体：点亮 = 发光大星（径向高光 + 光晕 + 白描边）；未点亮 = 灰点。
    for (let i = 0; i < shown.length; i++) {
      const m: Milestone = shown[i];
      const p: Pt = positions[i];
      const lit: boolean = this.isAchieved(m);
      const col: string = this.starColor(m);
      if (lit) {
        // 呼吸光晕（静态近似）
        c.save();
        c.globalAlpha = 0.4;
        c.fillStyle = col;
        c.beginPath();
        c.arc(p.x, p.y, 27, 0, 6.2832);
        c.fill();
        c.restore();
        // 径向高光球
        const rg: CanvasGradient = c.createRadialGradient(p.x - 5, p.y - 6, 1, p.x, p.y, 24);
        rg.addColorStop(0, '#FFFFFF');
        rg.addColorStop(1, col);
        c.fillStyle = rg;
        c.beginPath();
        c.arc(p.x, p.y, 24, 0, 6.2832);
        c.fill();
        c.lineWidth = 2;
        c.strokeStyle = '#FFFFFF';
        c.stroke();
      } else {
        c.fillStyle = BubuColor.softFill;
        c.beginPath();
        c.arc(p.x, p.y, 17, 0, 6.2832);
        c.fill();
        c.lineWidth = 1;
        c.strokeStyle = '#CCDBCCC2';
        c.stroke();
      }
      // emoji（点亮彩色大字，未点亮灰小字）
      c.save();
      c.globalAlpha = lit ? 1 : 0.45;
      c.font = lit ? '22px sans-serif' : '15px sans-serif';
      c.textAlign = 'center';
      c.textBaseline = 'middle';
      c.fillText(m.emoji, p.x, p.y);
      c.restore();
    }
  }

  // 叠加的可点击标签 + 命中区（对照 iOS starView 标签 + Button）。
  @Builder
  private starLabels() {
    Stack() {
      ForEach(this.shown(), (m: Milestone, idx: number) => {
        this.labelFor(m, idx)
      }, (m: Milestone) => m.id)
    }
    .width('100%').height('100%')
  }

  @Builder
  private labelFor(m: Milestone, idx: number) {
    Column() {
      // 透明命中圆（点星进详情）
      Stack() {
        if (this.isAchieved(m) || this.shown().length <= 12) {
          Text(m.title)
            .fontSize(11).fontWeight(FontWeight.Bold)
            .fontColor(this.isAchieved(m) ? BubuColor.warmBrown : BubuColor.secondaryText)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width(78).textAlign(TextAlign.Center)
            .margin({ top: 30 })
        }
      }
      .width(78).height(60)
    }
    .position(this.labelPos(idx))
    .onClick(() => { this.onTapStar(m); })
  }

  private labelPos(idx: number): Position {
    const positions: Pt[] = this.layout(this.shown().length);
    const p: Pt = idx < positions.length ? positions[idx] : { x: this.boardW / 2, y: this.boardH / 2 };
    // 标签盒 78×60，命中区以星点为中心。
    return { x: p.x - 39, y: p.y - 30 };
  }

  build() {
    Column({ space: 12 }) {
      // 标题行（对照 iOS HStack：已点亮 N/总 + 还有 M 颗）
      Row() {
        Text(`✦ 已点亮 ${this.achievedList().length} / ${this.totalCount()} 颗星`)
          .fontSize(15).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Blank()
        Text(`还有 ${Math.max(0, this.totalCount() - this.achievedList().length)} 颗等你点亮 ♡`)
          .fontSize(12).fontWeight(FontWeight.Medium).fontColor(BubuColor.secondaryText)
      }.width('100%')

      if (this.milestones.length === 0) {
        // 空态（对照 iOS empty VStack）
        Column({ space: 8 }) {
          Text('✦').fontSize(40).fontColor('#80F28C9E')
          Text('还没有点亮的星').fontSize(14).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
          Text('去「奖章墙」点亮布布的第一次，这里就会升起一颗星')
            .fontSize(12).fontColor(BubuColor.secondaryText).textAlign(TextAlign.Center)
        }
        .width('100%').padding({ top: 40, bottom: 40 })
      } else {
        // 星盘（Canvas 自绘 + 标签覆盖）
        Stack() {
          // 渐变底（lav/sky/cream2，对照 iOS LinearGradient）
          Column()
            .width('100%').height('100%')
            .linearGradient({
              angle: 180,
              colors: [
                ['#33DCC9FF', 0.0],
                ['#2EC4E4FF', 0.5],
                ['#4DFCEDE4', 1.0]
              ]
            })
            .borderRadius(28)
          Canvas(this.ctx)
            .width('100%').height('100%')
            .onReady(() => { this.draw(); })
          this.starLabels()
          // 右上角闪烁星
          BubuSparkle({ starSize: 12, color: '#FFFFFF' })
            .position({ x: this.boardW - 26, y: 14 })
        }
        .width('100%').height(this.starboardHeight())
        .borderRadius(28).clip(true)
        .onAreaChange((_o: Area, n: Area) => {
          const w: number = n.width as number;
          const h: number = n.height as number;
          if (w > 0 && h > 0 && (Math.abs(w - this.boardW) > 0.5 || Math.abs(h - this.boardH) > 0.5)) {
            this.boardW = w;
            this.boardH = h;
            this.draw();
          }
        })

        Text('轻点亮起的星星，回到那一刻 ♡')
          .fontSize(12).fontColor(BubuColor.secondaryText)
      }
    }
    .width('100%')
  }
}
