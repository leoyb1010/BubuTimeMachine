import { HealthRecord } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { HealthRecordKind, ALL_HEALTH_KINDS, healthKindMeta } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { GrowthCurveView } from './GrowthCurveView';
import { VaccineView } from './VaccineView';
import { HealthRecordSheet, HealthDraftUtil } from './HealthRecordSheet';

// MARK: - 布布健康（对照 iOS Features/Health/HealthHomeView.swift）
// 顶部说明卡 + 成长曲线/疫苗入口 + 7 类快速记录入口 + 今天 + 最近记录 + 免责声明。
@Component
export struct HealthHomeView {
  @State records: HealthRecord[] = [];
  @State composingKind: HealthRecordKind | null = null;
  @State showGrowth: boolean = false;
  @State showVaccine: boolean = false;
  @State private viewportW: number = 0;

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.records = await AppDatabase.shared.fetchHealth() ?? [];
  }

  private recordList(): HealthRecord[] {
    return this.records ?? [];
  }

  private todayRecordList(): HealthRecord[] {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    return this.recordList().filter((r: HealthRecord) => r.recordedAt >= start.getTime());
  }

  // 今日喝水累计（传给记录表的喝水录入器）。
  private todayWaterTotal(): number {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    let total = 0;
    for (const r of this.recordList()) {
      if (r.kind === HealthRecordKind.water && r.recordedAt >= start.getTime() && r.amountValue !== undefined && r.amountValue !== null) {
        total += r.amountValue;
      }
    }
    return total;
  }

  private isNarrow(): boolean {
    return this.viewportW > 0 && this.viewportW < 320;
  }

  build() {
    if (this.showGrowth) {
      Column() {
        this.panelHeader('成长曲线', () => { this.showGrowth = false; })
        GrowthCurveView().layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.showVaccine) {
      Column() {
        this.panelHeader('疫苗接种', () => { this.showVaccine = false; })
        VaccineView().layoutWeight(1)
      }.width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.composingKind !== null) {
      HealthRecordSheet({
        kind: this.composingKind,
        todayWaterTotal: this.todayWaterTotal(),
        onDone: () => { this.composingKind = null; this.reload(); },
        onCancel: () => { this.composingKind = null; }
      })
    } else {
      this.mainPage()
    }
  }

  @Builder
  panelHeader(title: string, onBack: () => void) {
    Row({ space: 12 }) {
      Button('返回').backgroundColor('#F3F3F3').fontColor(BubuColor.warmBrown).onClick(onBack)
      Text(title).fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Blank()
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  @Builder
  mainPage() {
    Scroll() {
      Column({ space: 16 }) {
        // 顶部说明卡（对照 iOS header）
        Column({ space: 8 }) {
          Text('❤️ 餐食、零食、营养补充都记在这里')
            .fontSize(17).fontWeight(FontWeight.Bold).fontColor(BubuColor.primary).width('100%')
          Text('这是家庭照护记录，不替代医生建议。它帮你看见布布每天吃了什么、睡得怎样、有没有不舒服。')
            .fontSize(13).fontColor(BubuColor.secondaryText).width('100%')
        }
        .width('100%').padding(16).backgroundColor(BubuColor.card).borderRadius(20)

	        // 成长曲线 / 疫苗接种入口（对照 iOS insightLinks）
	        if (this.isNarrow()) {
	          Column({ space: 10 }) {
	            this.insightTile('📈', '成长曲线', '身高·体重·头围', () => { this.showGrowth = true; })
	            this.insightTile('💉', '疫苗接种', '按月龄排期打卡', () => { this.showVaccine = true; })
	          }.width('100%')
	        } else {
	          Row({ space: 10 }) {
	            this.insightTile('📈', '成长曲线', '身高·体重·头围', () => { this.showGrowth = true; })
	            this.insightTile('💉', '疫苗接种', '按月龄排期打卡', () => { this.showVaccine = true; })
	          }.width('100%')
	        }

        // 7 类快速记录入口（对照 iOS quickActions）
        Grid() {
          ForEach(ALL_HEALTH_KINDS, (k: HealthRecordKind) => {
            GridItem() { this.kindCard(k) }
          }, (k: HealthRecordKind) => k)
	        }.columnsTemplate(this.isNarrow() ? '1fr' : '1fr 1fr')
	          .columnsGap(10)
	          .rowsGap(10)
	          .height(this.isNarrow() ? 532 : 280)

        // 今天（对照 iOS todaySection）
        Row({ space: 6 }) {
          Text('☀️ 今天').fontSize(17).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        }.width('100%').margin({ top: 8 })
        if (this.todayRecordList().length === 0) {
          Text('今天还没有健康记录。可以先记一顿餐食或一次喝水。')
            .fontSize(13).fontColor(BubuColor.secondaryText).width('100%')
        } else {
          ForEach(this.todayRecordList().slice(0, 6), (r: HealthRecord) => {
            this.recordRow(r)
          }, (r: HealthRecord) => r.id + '_today')
        }

        // 最近记录（对照 iOS recentSection）
        Row({ space: 6 }) {
          Text('🕐 最近记录').fontSize(17).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        }.width('100%').margin({ top: 8 })
        if (this.recordList().length === 0) {
          Text('点上面的卡片，记录布布的第一条健康吧')
            .fontSize(13).fontColor(BubuColor.secondaryText).width('100%')
        } else {
          ForEach(this.recordList().slice(0, 12), (r: HealthRecord) => {
            this.recordRow(r)
          }, (r: HealthRecord) => r.id + '_recent')
        }

	        // 免责声明（对照 iOS disclaimer）
	        Text('如果出现持续发热、过敏、精神状态异常等情况，请及时咨询医生。这里的记录主要用于家庭观察和复盘。')
	          .fontSize(12).fontColor(BubuColor.secondaryText).width('100%').margin({ top: 4 })
	        Blank().height(this.isNarrow() ? 170 : 140)
	      }
      .padding(16).width('100%')
    }
    .backgroundColor(BubuColor.cream).width('100%').height('100%')
    .onAreaChange((_old: Area, area: Area) => {
      const w = area.width as number;
      if (w > 0) this.viewportW = w;
    })
  }

  @Builder
  insightTile(emoji: string, title: string, subtitle: string, onTap: () => void) {
    Column({ space: 8 }) {
      Text(emoji).fontSize(22)
      Text(title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Text(subtitle).fontSize(12).fontColor(BubuColor.secondaryText)
    }
    .alignItems(HorizontalAlign.Start).layoutWeight(1)
    .padding(14).backgroundColor(BubuColor.card).borderRadius(20)
    .onClick(onTap)
  }

  @Builder
  kindCard(k: HealthRecordKind) {
    Row({ space: 10 }) {
      Text(healthKindMeta(k).emoji).fontSize(26)
      Column({ space: 2 }) {
        Text(healthKindMeta(k).title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
        Text(healthKindMeta(k).placeholder).fontSize(11).fontColor(BubuColor.secondaryText)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }
    .width('100%').padding(12).backgroundColor(BubuColor.card).borderRadius(16)
    .onClick(() => { this.composingKind = k; })
  }

  @Builder
  recordRow(r: HealthRecord) {
    Row({ space: 12 }) {
      Stack() {
        Text(healthKindMeta(r.kind as HealthRecordKind).emoji).fontSize(24)
      }.width(42).height(42).backgroundColor('#1AF28C9E').borderRadius(21)
      Column({ space: 3 }) {
        Text(r.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown).width('100%')
        // 类型 · 时间 · 数值摘要（对照 iOS）
        Text(this.metaLine(r)).fontSize(13).fontColor(BubuColor.secondaryText).width('100%')
        // 标签
        if (r.tags && r.tags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(r.tags.slice(0, 5), (tag: string) => {
              Text(tag).fontSize(11).fontWeight(FontWeight.Medium).fontColor(BubuColor.primary)
                .backgroundColor('#1AF28C9E').borderRadius(20)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 }).margin({ right: 6, bottom: 4 })
            }, (tag: string) => tag)
          }.width('100%')
        }
        if (r.detail && r.detail.length > 0) {
          Text(r.detail).fontSize(13).fontColor(BubuColor.secondaryText).width('100%')
        }
        if (r.reaction && r.reaction.length > 0) {
          Text(`反应：${r.reaction}`).fontSize(13).fontColor(BubuColor.primary).width('100%')
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }
    .width('100%').padding(12).backgroundColor(BubuColor.card).borderRadius(16)
    .alignItems(VerticalAlign.Top)
  }

  // 类型 · 时间 · 数值摘要行。
  private metaLine(r: HealthRecord): string {
    const parts: string[] = [healthKindMeta(r.kind as HealthRecordKind).title, BubuDateFormat.shortTime(new Date(r.recordedAt))];
    const amount = this.amountSummary(r);
    if (amount) parts.push(amount);
    return parts.join(' · ');
  }

  // 数值摘要（对照 iOS amountSummary）。
  private amountSummary(r: HealthRecord): string | null {
    if (r.amountText && r.amountText.length > 0) return r.amountText;
    if (r.kind === HealthRecordKind.sleep && r.startAt !== undefined && r.endAt !== undefined && r.endAt > r.startAt) {
      return HealthDraftUtil.durationText(r.startAt, r.endAt);
    }
    if (r.amountValue !== undefined && r.amountValue !== null && r.amountUnit) {
      return `${HealthDraftUtil.cleanAmount(r.amountValue)}${r.amountUnit}`;
    }
    if (r.temperatureCelsius !== undefined && r.temperatureCelsius !== null) {
      return `${r.temperatureCelsius.toFixed(1)}℃`;
    }
    return null;
  }
}
