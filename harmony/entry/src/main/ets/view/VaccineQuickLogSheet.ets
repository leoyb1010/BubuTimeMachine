import { util } from '@kit.ArkTS';
import { VaccineRecord } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { SyncState } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';
import { VaccineDose, vaccineDueDate } from './VaccineSchedule';

// MARK: - 疫苗快速补录 / 编辑（对照 iOS Features/Health/VaccineQuickLogSheet.swift）
// 点剂次弹出：接种日期、医院、反应、备注；编辑模式可取消打卡（删除记录）。
// 迁移来的记录在此确认真实接种日期后，自动摘掉「日期待确认」标记。

@Component
export struct VaccineQuickLogSheet {
  // 排期剂次；自费苗（AI 归档）为 null。
  @Prop dose: VaccineDose | null = null;
  // 编辑已有记录；null = 新打卡。
  @Prop existingRecord: VaccineRecord | null = null;
  // 布布生日（epoch ms），用于推算默认接种日。
  @Prop birthdayMs: number = 0;
  onDone: () => void = () => {};
  onCancel: () => void = () => {};

  @State injectedAt: number = Date.now();
  @State hospital: string = '';
  @State reaction: string = '';
  @State note: string = '';
  @State showDeleteConfirm: boolean = false;

  aboutToAppear(): void {
    const r = this.existingRecord;
    if (r) {
      this.injectedAt = r.injectedAt;
      this.hospital = r.hospital ?? '';
      this.reaction = r.reaction ?? '';
      const initialNote = r.note ?? '';
      // 迁移占位说明不进编辑框，由下方提示语承担。
      this.note = initialNote.includes('待确认') ? '' : initialNote;
    } else if (this.dose && this.birthdayMs > 0) {
      const due = vaccineDueDate(this.dose, this.birthdayMs);
      this.injectedAt = Math.min(due, Date.now());
    } else {
      this.injectedAt = Date.now();
    }
  }

  private isEditing(): boolean {
    return this.existingRecord !== null;
  }

  // 旧版打卡迁移且日期尚未被家长确认。
  private isMigrationPending(): boolean {
    const r = this.existingRecord;
    if (!r) return false;
    return r.source === 'migration' && (r.note?.includes('待确认') ?? false);
  }

  private titleText(): string {
    if (this.dose) return `${this.dose.shortName} · ${this.dose.doseLabel}`;
    return this.existingRecord?.vaccineName ?? '疫苗记录';
  }

  private footerText(): string {
    if (this.isMigrationPending()) return '此记录由旧版打卡迁移，请确认真实接种日期后保存。';
    if (this.dose) return `${this.dose.vaccine} · 预防${this.dose.prevents}`;
    return '';
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button('取消').backgroundColor('#F3F3F3').fontColor(BubuColor.warmBrown)
          .onClick(() => { this.onCancel(); })
        Text(this.isEditing() ? '修改接种记录' : '补录接种')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown).layoutWeight(1)
          .textAlign(TextAlign.Center)
        Button('保存').fontWeight(FontWeight.Bold).backgroundColor(BubuColor.primary).fontColor(Color.White)
          .onClick(() => { this.save(); })
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 14 }) {
          // 剂次标题
          Text(this.titleText()).fontSize(15).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown).width('100%')

          // 接种日期
          Row() {
            Text('接种日期').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            Text(this.dateText(this.injectedAt)).fontSize(14).fontColor(BubuColor.primary)
              .onClick(() => { this.pickDate(); })
          }.width('100%').padding(12).backgroundColor(BubuColor.card).borderRadius(12)

          Row() {
            Text('接种医院').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            TextInput({ text: $$this.hospital, placeholder: '门诊（可选）' }).width(180).textAlign(TextAlign.End)
          }.width('100%').padding({ left: 12, right: 4 }).backgroundColor(BubuColor.card).borderRadius(12)

          Row() {
            Text('接种后反应').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            TextInput({ text: $$this.reaction, placeholder: '可选' }).width(160).textAlign(TextAlign.End)
          }.width('100%').padding({ left: 12, right: 4 }).backgroundColor(BubuColor.card).borderRadius(12)

          Row() {
            Text('备注').fontSize(15).fontColor(BubuColor.warmBrown)
            Blank()
            TextInput({ text: $$this.note, placeholder: '可选' }).width(180).textAlign(TextAlign.End)
          }.width('100%').padding({ left: 12, right: 4 }).backgroundColor(BubuColor.card).borderRadius(12)

          if (this.footerText().length > 0) {
            Text(this.footerText()).fontSize(12).fontColor(BubuColor.secondaryText).width('100%')
          }

          // 编辑模式：取消打卡 / 删除
          if (this.isEditing()) {
            Button('取消打卡 / 删除记录')
              .width('100%').backgroundColor('#1ADB3B47').fontColor(BubuColor.danger)
              .onClick(() => { this.confirmDelete(); })
          }
        }
        .padding(16).width('100%')
      }
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%').backgroundColor(BubuColor.cream)
  }

  private pickDate(): void {
    DatePickerDialog.show({
      start: new Date(2015, 0, 1),
      end: new Date(),
      selected: new Date(this.injectedAt),
      onDateAccept: (value: Date) => { this.injectedAt = value.getTime(); }
    });
  }

  private confirmDelete(): void {
    AlertDialog.show({
      title: '取消这针的打卡？',
      message: '删除后家人设备也会同步移除这条记录。',
      primaryButton: { value: '取消打卡', fontColor: BubuColor.danger, action: () => { this.deleteRecord(); } },
      secondaryButton: { value: '再想想', action: () => {} }
    });
  }

  // 对照 iOS save()。
  private async save(): Promise<void> {
    const hospital = this.hospital.trim();
    const reaction = this.reaction.trim();
    const note = this.note.trim();
    const now = Date.now();
    const r = this.existingRecord;
    if (r) {
      r.injectedAt = this.injectedAt;
      r.hospital = hospital.length === 0 ? undefined : hospital;
      r.reaction = reaction.length === 0 ? undefined : reaction;
      r.note = note.length === 0 ? undefined : note;   // 迁移「待确认」标记随之摘除
      r.updatedAt = now;
      r.syncState = SyncState.local;
      await AppDatabase.shared.insertVaccine(r);
    } else {
      const vaccineName = this.dose?.vaccine ?? '疫苗接种';
      const newRecord: VaccineRecord = {
        id: util.generateRandomUUID(true),
        doseId: this.dose?.id,
        vaccineName: vaccineName,
        doseLabel: this.dose?.doseLabel,
        injectedAt: this.injectedAt,
        hospital: hospital.length === 0 ? undefined : hospital,
        reaction: reaction.length === 0 ? undefined : reaction,
        note: note.length === 0 ? undefined : note,
        source: 'manual',
        syncState: SyncState.local,
        createdAt: now,
        updatedAt: now
      };
      await AppDatabase.shared.insertVaccine(newRecord);
    }
    promptAction.showToast({ message: '已记录 💉' });
    this.onDone();
  }

  private async deleteRecord(): Promise<void> {
    const r = this.existingRecord;
    if (!r) return;
    await AppDatabase.shared.deleteVaccine(r.id);
    this.onDone();
  }

  private dateText(ms: number): string {
    const d = new Date(ms);
    return `${d.getFullYear()}.${d.getMonth() + 1}.${d.getDate()}`;
  }
}
