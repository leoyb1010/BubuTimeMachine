import { util } from '@kit.ArkTS';
import { HealthRecord } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { SyncState, HealthRecordKind, healthKindMeta } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';
import { healthKindDesign } from './HealthKindDesign';

// 录入卡片外壳样式（对照 iOS ComposerCard 的卡片底+描边）。
@Extend(Column)
function cardStyle() {
  .width('100%')
  .padding(16)
  .backgroundColor(BubuColor.card)
  .borderRadius(20)
  .border({ width: 1, color: '#1AF28C9E' })
}

// MARK: - 健康记录编辑（对照 iOS Features/Health/HealthRecordSheet.swift）
// 一张表单，按 kind 切换 7 种录入器（餐食/零食/营养/喝水/睡眠/不舒服/体检）。
// iOS 用 HealthRecordDraft 草稿对象 + 多个 Composer 子视图；ArkUI 把草稿摊平成
// @State 字段，按 kind 走不同 @Builder。保存逻辑对照 makeRecord。

// 草稿（对照 iOS struct HealthRecordDraft）。
export interface HealthRecordDraft {
  title: string;
  detail: string;
  recordedAt: number;
  amountValue: number | undefined;
  amountUnit: string | undefined;
  startAt: number | undefined;
  endAt: number | undefined;
  reaction: string;
  severity: string;
  temperatureCelsius: number | undefined;
  tags: string[];
}

// 草稿工具（对照 iOS HealthRecordDraft 静态方法）。
export class HealthDraftUtil {
  // 时长文案（对照 iOS durationText）。
  static durationText(startMs: number, endMs: number): string {
    const minutes = Math.max(0, Math.floor((endMs - startMs) / 60000));
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    if (hours > 0 && rest > 0) return `${hours}小时${rest}分钟`;
    if (hours > 0) return `${hours}小时`;
    return `${rest}分钟`;
  }

  // 数值清洗（对照 iOS cleanAmount）。
  static cleanAmount(value: number): string {
    return Math.round(value) === value ? `${Math.round(value)}` : value.toFixed(1);
  }
}

@Component
export struct HealthRecordSheet {
  @Prop kind: HealthRecordKind = HealthRecordKind.meal;
  // 今日喝水累计（喝水录入器用），由父级传入。
  @Prop todayWaterTotal: number = 0;
  // 保存/取消回调（对照 iOS dismiss + save）。
  onDone: () => void = () => {};
  onCancel: () => void = () => {};

  // —— 草稿字段（对照 iOS HealthRecordDraft）——
  @State draftTitle: string = '';
  @State draftDetail: string = '';
  @State draftRecordedAt: number = Date.now();
  @State amountValue: number | undefined = undefined;
  @State amountUnit: string | undefined = undefined;
  @State startAt: number | undefined = undefined;
  @State endAt: number | undefined = undefined;
  @State reaction: string = '';
  @State severity: string = '';
  @State temperatureCelsius: number | undefined = undefined;
  @State tags: string[] = [];

  private readonly suppUnits: string[] = ['滴', '粒', 'ml', '袋'];
  private readonly checkupUnits: string[] = ['cm', 'kg', '针', '颗'];

  aboutToAppear(): void {
    if (this.kind === HealthRecordKind.supplement && this.amountUnit === undefined) {
      this.amountUnit = '滴';
    }
    if (this.kind === HealthRecordKind.checkup && this.amountUnit === undefined) {
      this.amountUnit = 'cm';
    }
  }

  // —— 标签切换 ——
  private toggleTag(tag: string): void {
    if (this.tags.includes(tag)) {
      this.tags = this.tags.filter((t: string) => t !== tag);
    } else {
      this.tags = this.tags.concat([tag]);
    }
  }

  // 是否可保存（对照 iOS canSave）。
  private canSave(): boolean {
    const titleTrim = this.draftTitle.trim();
    switch (this.kind) {
      case HealthRecordKind.water:
        return this.amountValue !== undefined;
      case HealthRecordKind.sleep:
        return this.startAt !== undefined || this.endAt !== undefined || titleTrim.length > 0 || this.tags.length > 0;
      case HealthRecordKind.symptom:
        return this.tags.length > 0 || this.temperatureCelsius !== undefined || this.draftDetail.trim().length > 0;
      default:
        return titleTrim.length > 0 || this.tags.length > 0 || this.amountValue !== undefined;
    }
  }

  build() {
    Column() {
      // 顶部工具栏（取消 / 标题 / 保存）
      Row({ space: 12 }) {
        Button('取消').backgroundColor('#F3F3F3').fontColor(BubuColor.warmBrown)
          .onClick(() => { this.onCancel(); })
        Text(`记录${healthKindMeta(this.kind).title}`)
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown).layoutWeight(1)
          .textAlign(TextAlign.Center)
        Button('保存').fontWeight(FontWeight.Bold)
          .backgroundColor(this.canSave() ? BubuColor.primary : '#E5D5CC')
          .fontColor(this.canSave() ? Color.White : BubuColor.secondaryText)
          .enabled(this.canSave())
          .onClick(() => { this.save(); })
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 16 }) {
          this.heroCard()

          if (this.kind === HealthRecordKind.meal) {
            this.mealComposer()
          } else if (this.kind === HealthRecordKind.snack) {
            this.snackComposer()
          } else if (this.kind === HealthRecordKind.supplement) {
            this.supplementComposer()
          } else if (this.kind === HealthRecordKind.water) {
            this.waterComposer()
          } else if (this.kind === HealthRecordKind.sleep) {
            this.sleepComposer()
          } else if (this.kind === HealthRecordKind.symptom) {
            this.symptomComposer()
          } else if (this.kind === HealthRecordKind.checkup) {
            this.checkupComposer()
          }

          this.detailNoteCard()
          this.disclaimerCard()
        }
        .padding(16).width('100%')
      }
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%').backgroundColor(BubuColor.cream)
  }

  // MARK: - 英雄卡（对照 iOS HealthHeroCard）
  @Builder
  heroCard() {
    Row({ space: 14 }) {
      Text(healthKindDesign(this.kind).mascotEmoji).fontSize(44)
      Column({ space: 5 }) {
        Row({ space: 6 }) {
          Text(healthKindDesign(this.kind).iconEmoji).fontSize(18)
          Text(healthKindDesign(this.kind).heroTitle)
            .fontSize(17).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        }
        Text(healthKindDesign(this.kind).heroSubtitle)
          .fontSize(13).fontColor(BubuColor.secondaryText)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }
    .width('100%').padding(16).backgroundColor('#14F28C9E').borderRadius(20)
  }

  // 录入卡片标题行（对照 iOS ComposerCard 的 Label）。
  @Builder
  cardHeader(title: string, iconEmoji: string) {
    Row({ space: 6 }) {
      Text(iconEmoji).fontSize(18)
      Text(title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
    }.width('100%')
  }

  // 可选标签格（对照 iOS TagGrid + FlowLayout）。
  @Builder
  tagGrid(chips: string[], dangerTint: boolean) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(chips, (chip: string) => {
        this.chip(chip, this.tags.includes(chip), dangerTint, () => { this.toggleTag(chip); })
      }, (chip: string) => chip)
    }.width('100%')
  }

  // 单个胶囊 chip（对照 iOS SelectableChip）。
  @Builder
  chip(text: string, selected: boolean, dangerTint: boolean, onTap: () => void) {
    Text(text)
      .fontSize(14).fontWeight(FontWeight.Medium)
      .fontColor(selected ? Color.White : (dangerTint ? BubuColor.danger : BubuColor.primary))
      .backgroundColor(selected ? (dangerTint ? BubuColor.danger : BubuColor.primary) : (dangerTint ? '#1ADB3B47' : '#1AF28C9E'))
      .borderRadius(20)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .margin({ right: 8, bottom: 8 })
      .onClick(onTap)
  }

  // 反应选择（对照 iOS ReactionChips）。
  @Builder
  reactionChips(options: string[]) {
    Column({ space: 8 }) {
      Text('布布的反应').fontSize(13).fontWeight(FontWeight.Medium).fontColor(BubuColor.secondaryText).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(options, (opt: string) => {
          this.chip(opt, this.reaction === opt, false, () => {
            this.reaction = this.reaction === opt ? '' : opt;
          })
        }, (opt: string) => opt)
      }.width('100%')
    }.width('100%')
  }

  // MARK: 各录入器
  @Builder
  mealComposer() {
    Column({ space: 14 }) {
      this.cardHeader('食物卡片', '🍴')
      TextInput({ text: $$this.draftTitle, placeholder: '比如：小米粥、鸡蛋羹、青菜碎' })
        .backgroundColor('#A6F5E8E0').borderRadius(16).padding(12).width('100%')
      this.tagGrid(healthKindDesign(HealthRecordKind.meal).chips, false)
      this.reactionChips(['喜欢', '一般', '不喜欢', '过敏/不适'])
    }.cardStyle()
  }

  @Builder
  snackComposer() {
    Column({ space: 14 }) {
      this.cardHeader('小零食卡片', '🍿')
      Grid() {
        ForEach(healthKindDesign(HealthRecordKind.snack).chips, (chip: string) => {
          GridItem() {
            Column({ space: 6 }) {
              Text(chip).fontSize(16).fontWeight(FontWeight.Bold)
                .fontColor(this.tags.includes(chip) ? Color.White : BubuColor.warmBrown)
              Text(this.tags.includes(chip) ? '已选择' : '点一下').fontSize(11)
                .fontColor(this.tags.includes(chip) ? Color.White : BubuColor.warmBrown)
            }
            .width('100%').height(66).justifyContent(FlexAlign.Center)
            .backgroundColor(this.tags.includes(chip) ? BubuColor.primary : '#B3FFF1E8')
            .borderRadius(16)
            .onClick(() => {
              this.toggleTag(chip);
              if (this.draftTitle.trim().length === 0) this.draftTitle = chip;
            })
          }
        }, (chip: string) => chip)
      }.columnsTemplate('1fr 1fr').columnsGap(10).rowsGap(10).height(208)
      TextInput({ text: $$this.draftTitle, placeholder: '补充具体零食' })
        .backgroundColor('#A6F5E8E0').borderRadius(16).padding(12).width('100%')
      this.reactionChips(['开心', '一般', '不喜欢', '疑似不适'])
      this.tagGrid(['尝新', '常吃', '少量', '多吃了'], false)
    }.cardStyle()
  }

  @Builder
  supplementComposer() {
    Column({ space: 14 }) {
      this.cardHeader('补充类型和剂量', '💊')
      this.tagGrid(healthKindDesign(HealthRecordKind.supplement).chips, false)
      TextInput({ text: $$this.draftTitle, placeholder: '比如：维D、益生菌' })
        .backgroundColor('#A6F5E8E0').borderRadius(16).padding(12).width('100%')
      this.amountStepper('本次剂量', this.amountUnit ?? '滴', 0, 20, 1, false)
      Row({ space: 8 }) {
        ForEach(this.suppUnits, (u: string) => {
          this.chip(u, this.amountUnit === u, false, () => { this.amountUnit = u; })
        }, (u: string) => u)
      }
      this.tagGrid(['早上', '中午', '晚上', '睡前'], false)
    }.cardStyle()
  }

  @Builder
  waterComposer() {
    Column({ space: 14 }) {
      this.cardHeader('小水壶喝了多少', '💧')
      Row({ space: 14 }) {
        Stack() {
          Text('💧').fontSize(38)
        }.width(82).height(82).backgroundColor('#1FF28C9E').borderRadius(24)
        Column({ space: 5 }) {
          Text(this.amountValue !== undefined ? `本次 ${Math.round(this.amountValue)} ml` : '点一下快速记录')
            .fontSize(17).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
          Text(`今日已记录 ${Math.round(this.todayWaterTotal + (this.amountValue ?? 0))} ml`)
            .fontSize(13).fontColor(BubuColor.secondaryText)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%')

      Grid() {
        ForEach(healthKindDesign(HealthRecordKind.water).quickAmounts, (amt: number) => {
          GridItem() {
            Text(`${Math.round(amt)} ml`)
              .fontSize(16).fontWeight(FontWeight.Bold)
              .fontColor(this.amountValue === amt ? BubuColor.primary : BubuColor.warmBrown)
              .width('100%').height(48).textAlign(TextAlign.Center)
              .backgroundColor(this.amountValue === amt ? '#2EF28C9E' : '#B3FFF1E8')
              .borderRadius(16)
              .onClick(() => {
                this.amountValue = amt;
                this.amountUnit = 'ml';
                this.draftTitle = '喝水';
              })
          }
        }, (amt: number) => `${amt}`)
      }.columnsTemplate('1fr 1fr 1fr').columnsGap(10).rowsGap(10).height(106)

      this.amountStepper('微调水量', 'ml', 10, 500, 10, false)
      this.tagGrid(healthKindDesign(HealthRecordKind.water).chips, false)
    }.cardStyle()
  }

  @Builder
  sleepComposer() {
    Column({ space: 14 }) {
      this.cardHeader('睡眠时间', '🌙')
      Row() {
        Text('入睡').fontSize(15).fontColor(BubuColor.warmBrown)
        Blank()
        Text(this.startAt !== undefined ? this.dateTimeText(this.startAt) : '点选时间')
          .fontSize(14).fontColor(BubuColor.primary)
          .onClick(() => { this.pickDateTime(true); })
      }.width('100%').padding(12).backgroundColor('#A6F5E8E0').borderRadius(12)
      Row() {
        Text('醒来').fontSize(15).fontColor(BubuColor.warmBrown)
        Blank()
        Text(this.endAt !== undefined ? this.dateTimeText(this.endAt) : '点选时间')
          .fontSize(14).fontColor(BubuColor.primary)
          .onClick(() => { this.pickDateTime(false); })
      }.width('100%').padding(12).backgroundColor('#A6F5E8E0').borderRadius(12)
      if (this.startAt !== undefined && this.endAt !== undefined && this.endAt > this.startAt) {
        Text(`🕐 睡了 ${HealthDraftUtil.durationText(this.startAt, this.endAt)}`)
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor(BubuColor.primary).width('100%')
      }
      this.tagGrid(healthKindDesign(HealthRecordKind.sleep).chips, false)
    }.cardStyle()
  }

  @Builder
  symptomComposer() {
    Column({ space: 14 }) {
      this.cardHeader('观察症状', '🩹')
      this.tagGrid(healthKindDesign(HealthRecordKind.symptom).chips, true)
      this.temperatureStepper()
      Column({ space: 8 }) {
        Text('严重程度').fontSize(13).fontWeight(FontWeight.Medium).fontColor(BubuColor.secondaryText).width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(['轻微', '观察中', '需要关注', '已就医'], (s: string) => {
            this.chip(s, this.severity === s, true, () => { this.severity = s; })
          }, (s: string) => s)
        }.width('100%')
      }.width('100%')
      TextArea({ text: $$this.draftDetail, placeholder: '药物、护理或变化备注' })
        .backgroundColor('#A6F5E8E0').borderRadius(16).padding(12).width('100%').height(96)
    }.cardStyle()
  }

  @Builder
  checkupComposer() {
    Column({ space: 14 }) {
      this.cardHeader('体检数据', '🩺')
      this.tagGrid(healthKindDesign(HealthRecordKind.checkup).chips, false)
      TextInput({ text: $$this.draftTitle, placeholder: '体检项目或疫苗名称' })
        .backgroundColor('#A6F5E8E0').borderRadius(16).padding(12).width('100%')
      this.amountStepper('主要数值', this.amountUnit ?? 'cm', 0, 130, 0.5, false)
      Row({ space: 8 }) {
        ForEach(this.checkupUnits, (u: string) => {
          this.chip(u, this.amountUnit === u, false, () => { this.amountUnit = u; })
        }, (u: string) => u)
      }
      TextArea({ text: $$this.draftDetail, placeholder: '医生建议、头围、体重、牙齿等补充' })
        .backgroundColor('#A6F5E8E0').borderRadius(16).padding(12).width('100%').height(96)
    }.cardStyle()
  }

  // MARK: 时间与备注（对照 iOS DetailNoteCard）
  @Builder
  detailNoteCard() {
    Column({ space: 14 }) {
      this.cardHeader('时间和备注', '📅')
      Row() {
        Text('记录时间').fontSize(15).fontColor(BubuColor.warmBrown)
        Blank()
        Text(this.dateTimeText(this.draftRecordedAt))
          .fontSize(14).fontColor(BubuColor.primary)
          .onClick(() => { this.pickRecordedAt(); })
      }.width('100%').padding(12).backgroundColor('#A6F5E8E0').borderRadius(12)
      if (this.kind !== HealthRecordKind.symptom && this.kind !== HealthRecordKind.checkup) {
        TextArea({ text: $$this.draftDetail, placeholder: '补充一点观察，比如吃完状态、睡醒精神……' })
          .backgroundColor('#A6F5E8E0').borderRadius(16).padding(12).width('100%').height(72)
      }
    }.cardStyle()
  }

  @Builder
  disclaimerCard() {
    Text(this.kind === HealthRecordKind.symptom
      ? '🩺 家庭观察不替代医生判断；高热、精神差或症状加重请及时就医。'
      : '🩺 健康记录只用于家庭观察，不替代医生建议。')
      .fontSize(13).fontColor(BubuColor.secondaryText).width('100%')
      .padding(16).backgroundColor('#B8FFFFFF').borderRadius(16)
  }

  // 数值步进（对照 iOS AmountStepper）。
  @Builder
  amountStepper(title: string, unit: string, min: number, max: number, step: number, danger: boolean) {
    Row() {
      Column({ space: 3 }) {
        Text(title).fontSize(13).fontWeight(FontWeight.Medium).fontColor(BubuColor.secondaryText)
        Text(this.amountValue !== undefined ? `${HealthDraftUtil.cleanAmount(this.amountValue)}${unit}` : '未填写')
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Row({ space: 10 }) {
        Button('−').width(40).height(40).backgroundColor('#1AF28C9E').fontColor(BubuColor.primary)
          .onClick(() => {
            const cur = this.amountValue ?? min;
            this.amountValue = Math.min(Math.max(cur - step, min), max);
          })
        Button('+').width(40).height(40).backgroundColor(BubuColor.primary).fontColor(Color.White)
          .onClick(() => {
            const cur = this.amountValue ?? min;
            this.amountValue = Math.min(Math.max(cur + step, min), max);
          })
      }
    }
    .width('100%').padding(12).backgroundColor('#A6FFF1E8').borderRadius(16)
  }

  // 体温步进（对照 iOS TemperatureStepper，34–42℃，步长 0.1）。
  @Builder
  temperatureStepper() {
    Row() {
      Column({ space: 3 }) {
        Text('体温').fontSize(13).fontWeight(FontWeight.Medium).fontColor(BubuColor.secondaryText)
        Text(this.temperatureCelsius !== undefined ? `${this.temperatureCelsius.toFixed(1)}℃` : '未记录')
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Row({ space: 10 }) {
        Button('−').width(40).height(40).backgroundColor('#1ADB3B47').fontColor(BubuColor.danger)
          .onClick(() => {
            const cur = this.temperatureCelsius ?? 36.5;
            this.temperatureCelsius = Math.min(Math.max(Math.round((cur - 0.1) * 10) / 10, 34.0), 42.0);
          })
        Button('+').width(40).height(40).backgroundColor(BubuColor.danger).fontColor(Color.White)
          .onClick(() => {
            const cur = this.temperatureCelsius ?? 36.5;
            this.temperatureCelsius = Math.min(Math.max(Math.round((cur + 0.1) * 10) / 10, 34.0), 42.0);
          })
      }
    }
    .width('100%').padding(12).backgroundColor('#14DB3B47').borderRadius(16)
  }

  // NOTE: 鸿蒙 DatePickerDialog 只给日期；时间部分用 TimePickerDialog。为对照 iOS
  // [.date, .hourAndMinute] 的轻量等价，这里先弹日期选择并保留当前时分，足够家庭记录使用。
  private pickDateTime(isStart: boolean): void {
    // 内联用 DatePickerDialog，见 importChecked 处。
    this.showDatePicker((picked: number) => {
      if (isStart) {
        this.startAt = picked;
      } else {
        this.endAt = picked;
      }
      if (this.draftTitle.trim().length === 0) {
        this.draftTitle = this.tags.length > 0 ? this.tags[0] : '睡眠';
      }
    }, isStart ? (this.startAt ?? this.draftRecordedAt) : (this.endAt ?? Date.now()));
  }

  private pickRecordedAt(): void {
    this.showDatePicker((picked: number) => { this.draftRecordedAt = picked; }, this.draftRecordedAt);
  }

  private showDatePicker(onPick: (ms: number) => void, current: number): void {
    DatePickerDialog.show({
      start: new Date(2015, 0, 1),
      end: new Date(),
      selected: new Date(current),
      onDateAccept: (value: Date) => {
        // 保留原时分，仅替换年月日
        const base = new Date(current);
        value.setHours(base.getHours(), base.getMinutes(), 0, 0);
        onPick(value.getTime());
      }
    });
  }

  private dateTimeText(ms: number): string {
    const d = new Date(ms);
    return `${d.getMonth() + 1}.${d.getDate()} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  }

  // MARK: - 保存（对照 iOS save + makeRecord）
  private async save(): Promise<void> {
    if (!this.canSave()) return;
    const titleTrim = this.draftTitle.trim();
    let finalTitle: string;
    if (titleTrim.length > 0) {
      finalTitle = titleTrim;
    } else if (this.tags.length > 0) {
      finalTitle = this.tags[0];
    } else {
      finalTitle = healthKindMeta(this.kind).title;
    }

    const now = Date.now();
    let amountValue = this.amountValue;
    let amountUnit = this.amountUnit;
    let amountText: string | undefined = undefined;

    // 睡眠：用时长换算小时（对照 iOS makeRecord 睡眠分支）
    if (this.kind === HealthRecordKind.sleep && this.startAt !== undefined && this.endAt !== undefined && this.endAt > this.startAt) {
      const hours = (this.endAt - this.startAt) / 3600000;
      amountValue = hours;
      amountUnit = '小时';
      amountText = HealthDraftUtil.durationText(this.startAt, this.endAt);
    } else if (amountValue !== undefined && amountUnit !== undefined) {
      amountText = `${HealthDraftUtil.cleanAmount(amountValue)}${amountUnit}`;
    }

    // 不舒服：体温拼到 amountText（对照 iOS makeRecord 症状分支）
    if (this.kind === HealthRecordKind.symptom && this.temperatureCelsius !== undefined) {
      const tempText = `体温 ${this.temperatureCelsius.toFixed(1)}℃`;
      amountText = amountText !== undefined ? `${amountText} · ${tempText}` : tempText;
    }

    const detailTrim = this.draftDetail.trim();
    const rec: HealthRecord = {
      id: util.generateRandomUUID(true),
      kind: this.kind,
      title: finalTitle,
      detail: detailTrim.length === 0 ? undefined : detailTrim,
      recordedAt: this.draftRecordedAt,
      amountText: amountText,
      reaction: this.reaction.length === 0 ? undefined : this.reaction,
      amountValue: amountValue,
      amountUnit: amountUnit,
      startAt: this.startAt,
      endAt: this.endAt,
      severity: this.severity.length === 0 ? undefined : this.severity,
      temperatureCelsius: this.temperatureCelsius,
      tags: this.tags,
      syncState: SyncState.local,
      createdAt: now
    };
    await AppDatabase.shared.insertHealth(rec);
    promptAction.showToast({ message: '已经收好啦 🌟' });
    this.onDone();
  }
}
