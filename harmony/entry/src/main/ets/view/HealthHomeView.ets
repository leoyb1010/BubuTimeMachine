import { util } from '@kit.ArkTS';
import { HealthRecord } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { SyncState, HealthRecordKind, ALL_HEALTH_KINDS, healthKindMeta } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';
import { GrowthCurveView } from './GrowthCurveView';
import { promptAction } from '@kit.ArkUI';

// MARK: - 布布健康（对照 iOS HealthHomeView）
// 7 类快速记录入口（餐食/零食/营养/喝水/睡眠/不舒服/体检）+ 今日 + 最近列表。
@Component
export struct HealthHomeView {
  @State records: HealthRecord[] = [];
  @State composingKind: HealthRecordKind | null = null;
  @State draftTitle: string = '';
  @State draftDetail: string = '';
  @State showGrowth: boolean = false;

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.records = await AppDatabase.shared.fetchHealth();
  }

  private get todayRecords(): HealthRecord[] {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    return this.records.filter(r => r.recordedAt >= start.getTime());
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Text('布布健康')
            .fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
          Blank()
          Button('📈 成长曲线').backgroundColor('#F3F3F3').fontColor(BubuColor.warmBrown)
            .onClick(() => { this.showGrowth = true; })
        }.width('100%')

        // 7 类入口网格
        Grid() {
          ForEach(ALL_HEALTH_KINDS, (k: HealthRecordKind) => {
            GridItem() {
              this.kindCard(k)
            }
          }, (k: HealthRecordKind) => k)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(12).rowsGap(12)
        .height(360)

        // 今日
        if (this.todayRecords.length > 0) {
          Text('今天').fontSize(16).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown).width('100%')
          ForEach(this.todayRecords, (r: HealthRecord) => {
            this.recordRow(r)
          }, (r: HealthRecord) => r.id)
        }

        // 最近
        if (this.records.length > 0) {
          Text('最近').fontSize(16).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
            .width('100%').margin({ top: 8 })
          ForEach(this.records.slice(0, 20), (r: HealthRecord) => {
            this.recordRow(r)
          }, (r: HealthRecord) => r.id + '_recent')
        } else {
          Text('点上面的卡片，记录布布的第一条健康吧')
            .fontSize(13).fontColor(BubuColor.secondaryText).margin({ top: 20 })
        }
      }
      .padding(16).width('100%')
    }
    .backgroundColor(BubuColor.cream).width('100%').height('100%')
    .bindSheet(this.composingKind !== null, this.recordSheet(), {
      height: 360,
      onDisappear: () => { this.composingKind = null; }
    })
    .bindSheet($$this.showGrowth, this.growthSheet(), { height: '90%' })
  }

  @Builder
  growthSheet() {
    GrowthCurveView()
  }

  @Builder
  kindCard(k: HealthRecordKind) {
    Column({ space: 6 }) {
      Text(healthKindMeta(k).emoji).fontSize(30)
      Text(healthKindMeta(k).title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
      Text(healthKindMeta(k).placeholder).fontSize(10).fontColor(BubuColor.secondaryText)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%').padding(14).justifyContent(FlexAlign.Center)
    .backgroundColor(BubuColor.card).borderRadius(16)
    .onClick(() => {
      this.draftTitle = '';
      this.draftDetail = '';
      this.composingKind = k;
    })
  }

  @Builder
  recordRow(r: HealthRecord) {
    Row({ space: 10 }) {
      Text(healthKindMeta(r.kind as HealthRecordKind).emoji).fontSize(26)
      Column() {
        Text(r.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
        if (r.detail && r.detail.length > 0) {
          Text(r.detail).fontSize(12).fontColor(BubuColor.secondaryText).maxLines(1)
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text(this.timeText(r.recordedAt)).fontSize(11).fontColor(BubuColor.secondaryText)
    }
    .width('100%').padding(12)
    .backgroundColor(BubuColor.card).borderRadius(14)
  }

  @Builder
  recordSheet() {
    Column({ space: 14 }) {
      Text(this.composingKind ? `记录${healthKindMeta(this.composingKind).title}` : '')
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      TextInput({ text: $$this.draftTitle, placeholder: this.composingKind ? healthKindMeta(this.composingKind).placeholder : '' })
        .height(48).backgroundColor('#F3F3F3').borderRadius(10)
      TextArea({ text: $$this.draftDetail, placeholder: '补充说明（选填）' })
        .height(100).backgroundColor('#F3F3F3').borderRadius(10)
      Button('保存').width('100%').backgroundColor(BubuColor.primary)
        .onClick(() => { this.save(); })
    }
    .padding(20).width('100%')
  }

  private async save(): Promise<void> {
    const kind = this.composingKind;
    if (!kind) return;
    const title = this.draftTitle.trim().length === 0 ? healthKindMeta(kind).title : this.draftTitle.trim();
    const now = Date.now();
    const rec: HealthRecord = {
      id: util.generateRandomUUID(true),
      kind: kind,
      title: title,
      detail: this.draftDetail.trim().length === 0 ? undefined : this.draftDetail.trim(),
      recordedAt: now,
      tags: [],
      syncState: SyncState.local,
      createdAt: now
    };
    await AppDatabase.shared.insertHealth(rec);
    this.composingKind = null;
    await this.reload();
    promptAction.showToast({ message: '已经收好啦 🌟' });
  }

  private timeText(ms: number): string {
    const d = new Date(ms);
    return `${d.getMonth() + 1}.${d.getDate()} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  }
}
