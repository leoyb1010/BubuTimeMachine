import { util } from '@kit.ArkTS';
import { GrowthMeasurement } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { SyncState } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';

// MARK: - 成长曲线（对照 iOS GrowthCurveView）
// 鸿蒙无官方图表，用 Canvas 自绘身高/体重折线。
@Component
export struct GrowthCurveView {
  @State data: GrowthMeasurement[] = [];
  @State showAdd: boolean = false;
  @State heightStr: string = '';
  @State weightStr: string = '';

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.data = await AppDatabase.shared.fetchGrowth();
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Text('成长曲线').fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
          Blank()
          Button('+ 记一次').backgroundColor(BubuColor.primary)
            .onClick(() => { this.heightStr = ''; this.weightStr = ''; this.showAdd = true; })
        }.width('100%')

        if (this.data.length === 0) {
          Text('记录身高体重，看布布一点点长大').fontSize(13).fontColor(BubuColor.secondaryText).margin({ top: 24 })
        } else {
          Text('身高 (cm)').fontSize(13).fontColor(BubuColor.primary).width('100%')
          Canvas(this.ctx)
            .width('100%').height(180).backgroundColor(BubuColor.card).borderRadius(12)
            .onReady(() => { this.drawChart('height'); })

          // 数据列表
          ForEach(this.data, (g: GrowthMeasurement) => {
            Row() {
              Text(this.dateText(g.measuredAt)).fontSize(12).fontColor(BubuColor.secondaryText)
              Blank()
              Text(`${g.heightCm ? g.heightCm + 'cm' : '-'} · ${g.weightKg ? g.weightKg + 'kg' : '-'}`)
                .fontSize(13).fontColor(BubuColor.warmBrown)
            }.width('100%').padding(10).backgroundColor(BubuColor.card).borderRadius(10)
          }, (g: GrowthMeasurement) => g.id)
        }
      }
      .padding(16).width('100%')
    }
    .backgroundColor(BubuColor.cream).width('100%').height('100%')
    .bindSheet($$this.showAdd, this.addSheet(), { height: 280 })
  }

  // 自绘折线
  private drawChart(field: string): void {
    const c = this.ctx;
    const w = c.width;
    const h = c.height;
    c.clearRect(0, 0, w, h);
    const vals: number[] = this.data.map(g => (g.heightCm ?? 0)).filter(v => v > 0);
    if (vals.length < 1) return;
    const minV = Math.min(...vals) - 2;
    const maxV = Math.max(...vals) + 2;
    const range = Math.max(1, maxV - minV);
    const pad = 24;
    c.strokeStyle = BubuColor.primary;
    c.lineWidth = 3;
    c.beginPath();
    vals.forEach((v, i) => {
      const x = pad + (vals.length === 1 ? (w - 2 * pad) / 2 : (i / (vals.length - 1)) * (w - 2 * pad));
      const y = h - pad - ((v - minV) / range) * (h - 2 * pad);
      if (i === 0) c.moveTo(x, y); else c.lineTo(x, y);
    });
    c.stroke();
    // 点
    c.fillStyle = BubuColor.primary;
    vals.forEach((v, i) => {
      const x = pad + (vals.length === 1 ? (w - 2 * pad) / 2 : (i / (vals.length - 1)) * (w - 2 * pad));
      const y = h - pad - ((v - minV) / range) * (h - 2 * pad);
      c.beginPath();
      c.arc(x, y, 4, 0, 6.2832);
      c.fill();
    });
  }

  @Builder
  addSheet() {
    Column({ space: 14 }) {
      Text('记一次身高体重').fontSize(18).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Row() {
        Text('身高(cm)').fontSize(15).fontColor(BubuColor.warmBrown)
        Blank()
        TextInput({ text: $$this.heightStr, placeholder: '如 78.5' }).type(InputType.NUMBER_DECIMAL).width(140).textAlign(TextAlign.End)
      }.width('100%').padding(12).backgroundColor(BubuColor.card).borderRadius(12)
      Row() {
        Text('体重(kg)').fontSize(15).fontColor(BubuColor.warmBrown)
        Blank()
        TextInput({ text: $$this.weightStr, placeholder: '如 10.2' }).type(InputType.NUMBER_DECIMAL).width(140).textAlign(TextAlign.End)
      }.width('100%').padding(12).backgroundColor(BubuColor.card).borderRadius(12)
      Button('保存').width('100%').backgroundColor(BubuColor.primary).onClick(() => { this.save(); })
    }
    .padding(20).width('100%')
  }

  private async save(): Promise<void> {
    const h = parseFloat(this.heightStr);
    const w = parseFloat(this.weightStr);
    const now = Date.now();
    const g: GrowthMeasurement = {
      id: util.generateRandomUUID(true),
      measuredAt: now,
      heightCm: isNaN(h) ? undefined : h,
      weightKg: isNaN(w) ? undefined : w,
      syncState: SyncState.local,
      createdAt: now
    };
    await AppDatabase.shared.insertGrowth(g);
    this.showAdd = false;
    await this.reload();
    this.drawChart('height');
    promptAction.showToast({ message: '已记录 📈' });
  }

  private dateText(ms: number): string {
    const d = new Date(ms);
    return `${d.getFullYear()}.${d.getMonth() + 1}.${d.getDate()}`;
  }
}
