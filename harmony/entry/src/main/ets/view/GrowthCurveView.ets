import { util } from '@kit.ArkTS';
import { GrowthMeasurement, ChildProfile } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { SyncState } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';
import { WHOGrowthStandard, WHOMetric, WHOBand, ALL_WHO_METRICS, whoMetricTitle, whoMetricUnit } from './WHOGrowthStandard';

// MARK: - 成长曲线（对照 iOS Features/Health/GrowthCurveView.swift）
// iOS 用 Swift Charts 画"五条 WHO 百分位带 + 布布实测折线"；鸿蒙无官方图表，
// 用 Canvas + CanvasRenderingContext2D 自绘：P3–P97 填充带 + P15–P85 深一档填充带
// + P50 中位虚线 + 布布实测折线与圆点。指标分段切换（身高/体重/头围）。

// 布布的一个实测点：月龄 + 数值（对照 iOS (month, value)）。
interface Measurement {
  month: number;
  value: number;
}

@Component
export struct GrowthCurveView {
  @State data: GrowthMeasurement[] = [];
  @State profile: ChildProfile | null = null;
  @State metric: WHOMetric = WHOMetric.height;
  @State showAdd: boolean = false;
  @State heightStr: string = '';
  @State weightStr: string = '';
  @State headStr: string = '';

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  readonly allMetrics: WHOMetric[] = ALL_WHO_METRICS;

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.data = await AppDatabase.shared.fetchGrowth() ?? [];
    this.profile = await AppDatabase.shared.fetchChildProfile();
    this.redraw();
  }

  private measurementList(): GrowthMeasurement[] {
    return this.data ?? [];
  }

  // 当前指标对应的 WHO 百分位带（对照 iOS bands 计算属性）。
  private bands(): WHOBand[] {
    return WHOGrowthStandard.bands(this.metric, this.profile?.gender);
  }

  // 布布实测点：同月龄唯一，按月龄升序（对照 iOS measurements）。
  // 结构化 GrowthMeasurement 优先（measuredAt 升序后写覆盖 = 同月取最新）。
  private measurements(): Measurement[] {
    const profile = this.profile;
    if (!profile) return [];
    const merged: Map<number, number> = new Map();
    for (const m of this.measurementList()) {
      let value: number | undefined;
      switch (this.metric) {
        case WHOMetric.height: value = m.heightCm; break;
        case WHOMetric.weight: value = m.weightKg; break;
        case WHOMetric.head: value = m.headCircumferenceCm; break;
        default: value = undefined;
      }
      if (value === undefined || value === null) continue;
      const month = this.monthsBetween(profile.birthday, m.measuredAt);
      if (month < 0 || month > 60) continue;
      merged.set(month, value);
    }
    const months: number[] = Array.from(merged.keys()).sort((a, b) => a - b);
    return months.map((mo: number): Measurement => ({ month: mo, value: merged.get(mo) as number }));
  }

  // 历法月龄差（对照 iOS Calendar.dateComponents([.month]))。
  private monthsBetween(fromMs: number, toMs: number): number {
    const f = new Date(fromMs);
    const t = new Date(toMs);
    let months = (t.getFullYear() - f.getFullYear()) * 12 + (t.getMonth() - f.getMonth());
    if (t.getDate() < f.getDate()) months -= 1;
    return months;
  }

  build() {
    if (this.showAdd) {
      this.addPanel()
    } else {
      this.mainPage()
    }
  }

  @Builder
  mainPage() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Text('成长曲线').fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
          Blank()
          Button('+ 记一次').backgroundColor(BubuColor.primary).fontColor(Color.White)
            .onClick(() => { this.heightStr = ''; this.weightStr = ''; this.headStr = ''; this.showAdd = true; })
        }.width('100%')

        // 指标分段切换（对照 iOS Picker.segmented）
        Row() {
          ForEach(this.allMetrics, (m: WHOMetric) => {
            Text(whoMetricTitle(m))
              .fontSize(14)
              .fontWeight(this.metric === m ? FontWeight.Bold : FontWeight.Regular)
              .fontColor(this.metric === m ? Color.White : BubuColor.warmBrown)
              .backgroundColor(this.metric === m ? BubuColor.primary : 'transparent')
              .borderRadius(10)
              .padding({ top: 8, bottom: 8 })
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .onClick(() => { this.metric = m; this.redraw(); })
          }, (m: WHOMetric) => m)
        }
        .width('100%').padding(4).backgroundColor(BubuColor.softFill).borderRadius(12)

        // 图表卡片
        Column({ space: 10 }) {
          Canvas(this.ctx)
            .width('100%').height(260)
            .onReady(() => { this.drawChart(); })
          // 图例（对照 iOS legend）
          Row({ space: 14 }) {
            Row({ space: 5 }) {
              Row().width(16).height(10).borderRadius(3).backgroundColor('#33F28C9E')
              Text('P15–P85 多数同龄').fontSize(12).fontColor(BubuColor.secondaryText)
            }
            Row({ space: 5 }) {
              Row().width(16).height(10).borderRadius(3).backgroundColor(BubuColor.primary)
              Text('布布').fontSize(12).fontColor(BubuColor.secondaryText)
            }
          }
        }
        .width('100%').padding(14).backgroundColor(BubuColor.card).borderRadius(20)

        // 最近一次读数 + 百分位友好解读（对照 iOS latestReading）
        this.latestReading()

        // 数据列表
        if (this.measurementList().length > 0) {
          ForEach(this.measurementList(), (g: GrowthMeasurement) => {
            Row() {
              Text(this.dateText(g.measuredAt)).fontSize(12).fontColor(BubuColor.secondaryText)
              Blank()
              Text(this.rowSummary(g)).fontSize(13).fontColor(BubuColor.warmBrown)
            }.width('100%').padding(10).backgroundColor(BubuColor.card).borderRadius(10)
          }, (g: GrowthMeasurement) => g.id)
        }

        Text('曲线基于 WHO 0–5 岁生长标准，仅供家庭参考，不替代医生评估。')
          .fontSize(12).fontColor(BubuColor.secondaryText).width('100%').margin({ top: 4 })
      }
      .padding(16).width('100%')
    }
    .backgroundColor(BubuColor.cream).width('100%').height('100%')
  }

  @Builder
  latestReading() {
    if (this.measurements().length > 0) {
      Column() {
        Row({ space: 12 }) {
          Text('😊').fontSize(34)
          Column({ space: 3 }) {
            Text(this.latestText())
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
            Text(this.percentileText())
              .fontSize(12).fontColor(BubuColor.primary)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }.width('100%')
      }
      .width('100%').padding(16).backgroundColor('#14F28C9E').borderRadius(20)
    } else {
      Text(`还没有${whoMetricTitle(this.metric)}记录。点「+ 记一次」记一条，曲线就会画出来。`)
        .fontSize(13).fontColor(BubuColor.secondaryText).width('100%')
    }
  }

  // 最近一次读数文案
  private latestText(): string {
    const ms = this.measurements();
    if (ms.length === 0) return '';
    const last = ms[ms.length - 1];
    return `最近一次：${this.formatted(last.value)} ${whoMetricUnit(this.metric)}（${last.month} 月龄）`;
  }

  private percentileText(): string {
    const ms = this.measurements();
    if (ms.length === 0) return '';
    const last = ms[ms.length - 1];
    const pct = WHOGrowthStandard.percentile(this.metric, this.profile?.gender, last.month, last.value);
    if (pct === null) return '';
    const verb = this.metric === WHOMetric.weight ? '重' : (this.metric === WHOMetric.height ? '高' : '大');
    return `P${pct} · 比同龄约 ${pct}% 的小朋友${verb}`;
  }

  private rowSummary(g: GrowthMeasurement): string {
    const parts: string[] = [];
    if (g.heightCm !== undefined && g.heightCm !== null) parts.push(`${g.heightCm}cm`);
    if (g.weightKg !== undefined && g.weightKg !== null) parts.push(`${g.weightKg}kg`);
    if (g.headCircumferenceCm !== undefined && g.headCircumferenceCm !== null) parts.push(`头围${g.headCircumferenceCm}cm`);
    return parts.length === 0 ? '-' : parts.join(' · ');
  }

  private formatted(v: number): string {
    return v === Math.round(v) ? `${Math.round(v)}` : v.toFixed(1);
  }

  private redraw(): void {
    // onReady 之后 ctx 可用；切换指标后重绘。
    this.drawChart();
  }

  // MARK: - Canvas 自绘（对照 iOS Chart：AreaMark 带 + LineMark 中位虚线 + 布布折线+点）
  private drawChart(): void {
    const c = this.ctx;
    const w = c.width;
    const h = c.height;
    if (w <= 0 || h <= 0) return;
    c.clearRect(0, 0, w, h);

    const bands = this.bands();
    if (bands.length === 0) return;
    const measurements = this.measurements();

    const padL = 36;
    const padR = 14;
    const padT = 12;
    const padB = 22;
    const plotW = w - padL - padR;
    const plotH = h - padT - padB;

    // X 轴：0–60 月龄
    const minMonth = 0;
    const maxMonth = 60;
    // Y 轴：覆盖所有带 + 实测点
    let minV = bands[0].p3;
    let maxV = bands[0].p97;
    for (const b of bands) {
      if (b.p3 < minV) minV = b.p3;
      if (b.p97 > maxV) maxV = b.p97;
    }
    for (const m of measurements) {
      if (m.value < minV) minV = m.value;
      if (m.value > maxV) maxV = m.value;
    }
    const vSpan = Math.max(1, maxV - minV);
    minV = minV - vSpan * 0.05;
    maxV = maxV + vSpan * 0.05;
    const range = Math.max(1, maxV - minV);

    const xOf = (month: number): number => padL + ((month - minMonth) / (maxMonth - minMonth)) * plotW;
    const yOf = (value: number): number => padT + plotH - ((value - minV) / range) * plotH;

    // P3–P97 外带（浅填充）
    this.fillBand(c, bands, xOf, yOf, (b: WHOBand) => b.p3, (b: WHOBand) => b.p97, '#14F28C9E');
    // P15–P85 内带（深一档）
    this.fillBand(c, bands, xOf, yOf, (b: WHOBand) => b.p15, (b: WHOBand) => b.p85, '#1FF28C9E');

    // P50 中位虚线
    c.strokeStyle = '#80F28C9E';
    c.lineWidth = 1;
    c.setLineDash([4, 3]);
    c.beginPath();
    bands.forEach((b: WHOBand, i: number) => {
      const x = xOf(b.month);
      const y = yOf(b.p50);
      if (i === 0) c.moveTo(x, y); else c.lineTo(x, y);
    });
    c.stroke();
    c.setLineDash([]);

    // 布布实测折线
    if (measurements.length > 0) {
      c.strokeStyle = BubuColor.primary;
      c.lineWidth = 2.5;
      c.beginPath();
      measurements.forEach((m: Measurement, i: number) => {
        const x = xOf(m.month);
        const y = yOf(m.value);
        if (i === 0) c.moveTo(x, y); else c.lineTo(x, y);
      });
      c.stroke();
      // 圆点
      c.fillStyle = BubuColor.primary;
      for (const m of measurements) {
        c.beginPath();
        c.arc(xOf(m.month), yOf(m.value), 4, 0, 6.2832);
        c.fill();
      }
    }

    // Y 轴刻度文字（min / mid / max）
    c.fillStyle = BubuColor.secondaryText;
    c.font = '10vp sans-serif';
    c.fillText(this.formatted(maxV), 2, padT + 8);
    c.fillText(this.formatted((minV + maxV) / 2), 2, padT + plotH / 2 + 4);
    c.fillText(this.formatted(minV), 2, padT + plotH);
    // X 轴月龄标注
    c.fillText('0', padL - 2, h - 6);
    c.fillText('30月', padL + plotW / 2 - 12, h - 6);
    c.fillText('60月', w - padR - 22, h - 6);
  }

  // 填充一条上下界百分位带（用上界正向 + 下界逆向闭合多边形）。
  private fillBand(c: CanvasRenderingContext2D, bands: WHOBand[],
    xOf: (m: number) => number, yOf: (v: number) => number,
    lower: (b: WHOBand) => number, upper: (b: WHOBand) => number, color: string): void {
    c.fillStyle = color;
    c.beginPath();
    bands.forEach((b: WHOBand, i: number) => {
      const x = xOf(b.month);
      const y = yOf(upper(b));
      if (i === 0) c.moveTo(x, y); else c.lineTo(x, y);
    });
    for (let i = bands.length - 1; i >= 0; i--) {
      const b = bands[i];
      c.lineTo(xOf(b.month), yOf(lower(b)));
    }
    c.closePath();
    c.fill();
  }

  @Builder
  addPanel() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Button('返回').backgroundColor('#F3F3F3').fontColor(BubuColor.warmBrown)
          .onClick(() => { this.showAdd = false; })
        Text('记一次身高体重').fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Blank()
      }.width('100%')

      Row() {
        Text('身高(cm)').fontSize(15).fontColor(BubuColor.warmBrown)
        Blank()
        TextInput({ text: $$this.heightStr, placeholder: '如 78.5' })
          .type(InputType.NUMBER_DECIMAL).width(140).textAlign(TextAlign.End)
      }.width('100%').padding(12).backgroundColor(BubuColor.card).borderRadius(12)

      Row() {
        Text('体重(kg)').fontSize(15).fontColor(BubuColor.warmBrown)
        Blank()
        TextInput({ text: $$this.weightStr, placeholder: '如 10.2' })
          .type(InputType.NUMBER_DECIMAL).width(140).textAlign(TextAlign.End)
      }.width('100%').padding(12).backgroundColor(BubuColor.card).borderRadius(12)

      Row() {
        Text('头围(cm)').fontSize(15).fontColor(BubuColor.warmBrown)
        Blank()
        TextInput({ text: $$this.headStr, placeholder: '如 46.5' })
          .type(InputType.NUMBER_DECIMAL).width(140).textAlign(TextAlign.End)
      }.width('100%').padding(12).backgroundColor(BubuColor.card).borderRadius(12)

      Button('保存').width('100%').backgroundColor(BubuColor.primary).fontColor(Color.White)
        .onClick(() => { this.save(); })
    }
    .padding(20).width('100%').height('100%').backgroundColor(BubuColor.cream)
  }

  private async save(): Promise<void> {
    const hv = parseFloat(this.heightStr);
    const wv = parseFloat(this.weightStr);
    const hc = parseFloat(this.headStr);
    if (isNaN(hv) && isNaN(wv) && isNaN(hc)) {
      promptAction.showToast({ message: '先填身高、体重或头围' });
      return;
    }
    const now = Date.now();
    const g: GrowthMeasurement = {
      id: util.generateRandomUUID(true),
      measuredAt: now,
      heightCm: isNaN(hv) ? undefined : hv,
      weightKg: isNaN(wv) ? undefined : wv,
      headCircumferenceCm: isNaN(hc) ? undefined : hc,
      source: 'manual',
      syncState: SyncState.local,
      createdAt: now,
      updatedAt: now
    };
    await AppDatabase.shared.insertGrowth(g);
    this.showAdd = false;
    await this.reload();
    promptAction.showToast({ message: '已记录 📈' });
  }

  private dateText(ms: number): string {
    const d = new Date(ms);
    return `${d.getFullYear()}.${d.getMonth() + 1}.${d.getDate()}`;
  }
}
