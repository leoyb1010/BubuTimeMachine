import { util } from '@kit.ArkTS';
import { VaccineRecord, ChildProfile } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { SyncState } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';
import { VaccineDose, VACCINE_SCHEDULE, vaccineDueDate } from './VaccineSchedule';
import { VaccineQuickLogSheet } from './VaccineQuickLogSheet';

// MARK: - 疫苗接种表（对照 iOS Features/Health/VaccineView.swift）
// 数据源：结构化 VaccineRecord（可同步、可被 AI 归档）。
// 交互：点剂次 → 补录/修改详情；长按未完成剂次 → 一键快速完成；取消打卡走删除。

// 按周岁段分组的结果（对照 iOS groupedByYear）。
interface YearGroup {
  label: string;
  doses: VaccineDose[];
}

@Component
export struct VaccineView {
  @State records: VaccineRecord[] = [];
  @State profile: ChildProfile | null = null;
  // 补录/编辑面板路由（对照 iOS VaccineLogTarget）。
  @State logDose: VaccineDose | null = null;
  @State logRecord: VaccineRecord | null = null;
  @State showLog: boolean = false;

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.records = await AppDatabase.shared.fetchVaccines() ?? [];
    this.profile = await AppDatabase.shared.fetchChildProfile();
  }

  // doseId → 记录（对照 iOS recordByDose）。
  private recordForDose(doseId: string): VaccineRecord | null {
    for (const r of this.records) {
      if (r.doseId === doseId) return r;
    }
    return null;
  }

  private completedCount(): number {
    let n = 0;
    for (const dose of VACCINE_SCHEDULE) {
      if (this.recordForDose(dose.id)) n += 1;
    }
    return n;
  }

  // 不在排期内的记录（自费苗、AI 归档）（对照 iOS extraRecords）。
  private extraRecords(): VaccineRecord[] {
    return this.records.filter((r: VaccineRecord) => r.doseId === undefined || r.doseId === null);
  }

  // 下一针（未完成中 monthDue 最小）（对照 iOS nextDue）。
  private nextDue(): VaccineDose | null {
    let best: VaccineDose | null = null;
    for (const dose of VACCINE_SCHEDULE) {
      if (this.recordForDose(dose.id)) continue;
      if (best === null || dose.monthDue < best.monthDue) best = dose;
    }
    return best;
  }

  // 到期/接种文案（对照 iOS dueText）。
  private dueText(dose: VaccineDose): string {
    const record = this.recordForDose(dose.id);
    if (record) return this.dateText(record.injectedAt);
    const profile = this.profile;
    if (!profile) return `${dose.monthDue} 月龄`;
    const date = vaccineDueDate(dose, profile.birthday);
    if (date < Date.now()) return '建议尽快补种';
    return this.dateText(date);
  }

  // 按周岁段分组（对照 iOS groupedByYear）。
  private groupedByYear(): YearGroup[] {
    const sorted = VACCINE_SCHEDULE.slice().sort((a, b) => a.monthDue - b.monthDue);
    const byYear: Map<number, VaccineDose[]> = new Map();
    for (const dose of sorted) {
      const year = Math.floor(dose.monthDue / 12);
      const arr = byYear.get(year) ?? [];
      arr.push(dose);
      byYear.set(year, arr);
    }
    const years: number[] = Array.from(byYear.keys()).sort((a, b) => a - b);
    return years.map((year: number): YearGroup => ({
      label: year === 0 ? '1 岁内' : `${year}–${year + 1} 岁`,
      doses: byYear.get(year) as VaccineDose[]
    }));
  }

  // 旧版迁移、日期待确认（对照 iOS needsDateConfirm）。
  private needsDateConfirm(record: VaccineRecord): boolean {
    return record.source === 'migration' && (record.note?.includes('待确认') ?? false);
  }

  build() {
    if (this.showLog) {
      VaccineQuickLogSheet({
        dose: this.logDose,
        existingRecord: this.logRecord,
        birthdayMs: this.profile?.birthday ?? 0,
        onDone: () => { this.showLog = false; this.reload(); },
        onCancel: () => { this.showLog = false; }
      })
    } else {
      this.mainPage()
    }
  }

  @Builder
  mainPage() {
    Scroll() {
      Column({ space: 14 }) {
        // 汇总卡（对照 iOS summaryCard）
        Row({ space: 14 }) {
          Text('🎉').fontSize(40)
          Column({ space: 4 }) {
            Text(`已完成 ${this.completedCount()} / ${VACCINE_SCHEDULE.length} 剂`)
              .fontSize(17).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
            Text(this.summarySubtitle()).fontSize(13).fontColor(BubuColor.primary)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }
        .width('100%').padding(16).backgroundColor(BubuColor.card).borderRadius(20)

        Text('点剂次补录日期/医院/反应 · 长按未完成的快速打卡')
          .fontSize(11).fontColor(BubuColor.secondaryText).width('100%')

        // 按周岁分组的排期
        ForEach(this.groupedByYear(), (group: YearGroup) => {
          Text(group.label).fontSize(13).fontWeight(FontWeight.Medium)
            .fontColor(BubuColor.secondaryText).width('100%').margin({ top: 8 })
          ForEach(group.doses, (dose: VaccineDose) => {
            this.doseRow(dose)
          }, (dose: VaccineDose) => dose.id)
        }, (group: YearGroup) => group.label)

        // 其他疫苗记录
        if (this.extraRecords().length > 0) {
          Text('其他疫苗记录').fontSize(13).fontWeight(FontWeight.Medium)
            .fontColor(BubuColor.secondaryText).width('100%').margin({ top: 8 })
          ForEach(this.extraRecords(), (record: VaccineRecord) => {
            this.extraRow(record)
          }, (record: VaccineRecord) => record.id)
        }

        Text('依据国家免疫规划（一类苗）排期，地区与个体差异以当地接种点通知为准。打卡仅作家庭提醒。')
          .fontSize(12).fontColor(BubuColor.secondaryText).width('100%').margin({ top: 4 })
      }
      .padding(16).width('100%')
    }
    .backgroundColor(BubuColor.cream).width('100%').height('100%')
  }

  private summarySubtitle(): string {
    const next = this.nextDue();
    if (next) return `下一针：${next.shortName} ${next.doseLabel} · ${this.dueText(next)}`;
    return '规划内的疫苗都打齐啦 🎉';
  }

  @Builder
  doseRow(dose: VaccineDose) {
    Row({ space: 12 }) {
      Text(this.recordForDose(dose.id) ? '✅' : '⭕')
        .fontSize(22)
        .fontColor(this.recordForDose(dose.id) ? BubuColor.success : BubuColor.secondaryText)
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(`${dose.shortName} · ${dose.doseLabel}`)
            .fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor(BubuColor.warmBrown)
            .decoration({ type: this.recordForDose(dose.id) ? TextDecorationType.LineThrough : TextDecorationType.None })
          if (this.needsDateConfirmFor(dose.id)) {
            Text('日期待确认').fontSize(9).fontWeight(FontWeight.Bold).fontColor(BubuColor.primary)
              .backgroundColor('#1FF28C9E').borderRadius(8).padding({ left: 6, right: 6, top: 3, bottom: 3 })
          }
        }
        Text(`${dose.vaccine} · 预防${dose.prevents}`)
          .fontSize(13).fontColor(BubuColor.secondaryText)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text(this.dueText(dose)).fontSize(11)
        .fontColor(this.recordForDose(dose.id) ? BubuColor.secondaryText : BubuColor.primary)
    }
    .width('100%').padding(12).backgroundColor(BubuColor.card).borderRadius(16)
    .onClick(() => {
      this.logDose = dose;
      this.logRecord = this.recordForDose(dose.id);
      this.showLog = true;
    })
    .gesture(
      LongPressGesture().onAction(() => {
        if (this.recordForDose(dose.id)) return;
        this.instantComplete(dose);
      })
    )
  }

  private needsDateConfirmFor(doseId: string): boolean {
    const r = this.recordForDose(doseId);
    return r ? this.needsDateConfirm(r) : false;
  }

  @Builder
  extraRow(record: VaccineRecord) {
    Row({ space: 12 }) {
      Text('💉').fontSize(20)
      Column({ space: 2 }) {
        Text(record.vaccineName).fontSize(15).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
        if (record.hospital || record.note) {
          Text(record.hospital ?? record.note ?? '')
            .fontSize(13).fontColor(BubuColor.secondaryText)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text(this.dateText(record.injectedAt)).fontSize(11).fontColor(BubuColor.secondaryText)
    }
    .width('100%').padding(12).backgroundColor(BubuColor.card).borderRadius(16)
    .onClick(() => {
      this.logDose = null;
      this.logRecord = record;
      this.showLog = true;
    })
    .gesture(
      LongPressGesture().onAction(() => { this.confirmDeleteExtra(record); })
    )
  }

  private confirmDeleteExtra(record: VaccineRecord): void {
    AlertDialog.show({
      title: '删除这条记录？',
      message: '删除后家人设备也会同步移除这条记录。',
      primaryButton: { value: '删除', fontColor: BubuColor.danger, action: () => { this.deleteRecord(record); } },
      secondaryButton: { value: '再想想', action: () => {} }
    });
  }

  // 长按一键完成（对照 iOS instantComplete）。接种日取「排期日与今天的较早者」。
  private async instantComplete(dose: VaccineDose): Promise<void> {
    const profile = this.profile;
    const due = profile ? vaccineDueDate(dose, profile.birthday) : Date.now();
    const injectedAt = Math.min(due, Date.now());
    const now = Date.now();
    const record: VaccineRecord = {
      id: util.generateRandomUUID(true),
      doseId: dose.id,
      vaccineName: dose.vaccine,
      doseLabel: dose.doseLabel,
      injectedAt: injectedAt,
      source: 'manual',
      syncState: SyncState.local,
      createdAt: now,
      updatedAt: now
    };
    await AppDatabase.shared.insertVaccine(record);
    await this.reload();
    promptAction.showToast({ message: '打卡完成 ✅' });
  }

  private async deleteRecord(record: VaccineRecord): Promise<void> {
    await AppDatabase.shared.deleteVaccine(record.id);
    await this.reload();
  }

  private dateText(ms: number): string {
    const d = new Date(ms);
    return `${d.getFullYear()}.${d.getMonth() + 1}.${d.getDate()}`;
  }
}
