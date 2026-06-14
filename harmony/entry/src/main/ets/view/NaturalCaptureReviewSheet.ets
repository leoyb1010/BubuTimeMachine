import { promptAction } from '@kit.ArkUI';
import { BubuColor, BubuRadius, BubuFont, BubuShadow } from '../theme/BubuTheme';
import { BubuMascotBadge } from '../components/BubuMascotBadge';
import { BubuExpression } from '../theme/BubuExpression';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { NaturalCaptureRouter } from './NaturalCaptureRouter';
import {
  NaturalCaptureParseResult, NaturalCaptureItem, NaturalCaptureDomain,
  domainDisplayName, domainIcon, requiresHardConfirmation,
  fieldString, fieldDouble, fieldStringArray, fieldISODate,
  jvString, jvNumber, JSONValue
} from '../services/NaturalCaptureDTO';

// MARK: - 解析结果确认页 v2（对照 iOS Features/NaturalCapture/NaturalCaptureReviewSheet.swift）
// 一组待保存小卡：可逐条「编辑标题/时间/数量」、删除；
// 敏感（疫苗/症状/营养补充）与低置信项必须点「确认无误」才入库；
// 置信度 < 0.6 的卡片默认折叠并提供手动分类下拉；
// 保存时若仍有未确认项，会先明确提示而不是静默跳过。
@Component
export struct NaturalCaptureReviewSheet {
  @Require @Prop result: NaturalCaptureParseResult;
  @Require @Prop originalText: string;
  authorRole: string = '妈妈';
  onSaved?: () => void;
  onDismiss?: () => void;

  @State private editableItems: NaturalCaptureItem[] = [];
  @State private confirmedIDs: Set<string> = new Set<string>();
  @State private expandedIDs: Set<string> = new Set<string>();
  @State private editingID: string | null = null;
  // 触发重渲染的版本号（编辑 item 内部字段后自增）。
  @State private rev: number = 0;

  aboutToAppear(): void {
    // 初始化可编辑副本 + 低置信默认折叠，其余展开（对照 init）。
    this.editableItems = this.result.items.slice();
    const expanded = new Set<string>();
    for (const it of this.result.items) {
      if (it.confidence >= 0.6) expanded.add(it.id);
    }
    this.expandedIDs = expanded;
  }

  // 可保存：不需要硬确认，或已被用户点「确认」（对照 savableItems）。
  private savableItems(): NaturalCaptureItem[] {
    return this.editableItems.filter((it: NaturalCaptureItem) =>
      !requiresHardConfirmation(it) || this.confirmedIDs.has(it.id));
  }

  private unconfirmedCount(): number {
    return this.editableItems.length - this.savableItems().length;
  }

  private hasSymptom(): boolean {
    return this.editableItems.some((it: NaturalCaptureItem) => it.domain === NaturalCaptureDomain.symptom);
  }

  // 数字裁剪（对照 trimNumber）。
  private trimNumber(value: number): string {
    return value === Math.round(value) ? `${Math.trunc(value)}` : value.toFixed(1);
  }

  // domain SF Symbol → emoji（对照 Image(systemName: domain.icon)）。
  private iconEmoji(d: NaturalCaptureDomain): string {
    switch (domainIcon(d)) {
      case 'syringe': return '💉';
      case 'ruler': return '📏';
      case 'fork.knife': return '🍽️';
      case 'takeoutbag.and.cup.and.straw': return '🥤';
      case 'pills': return '💊';
      case 'drop.fill': return '💧';
      case 'moon.zzz.fill': return '🌙';
      case 'cross.case.fill': return '🩹';
      case 'stethoscope': return '🩺';
      case 'sparkles': return '✨';
      case 'star.fill': return '⭐';
      case 'party.popper': return '🎉';
      default: return '❓';
    }
  }

  build() {
    Stack() {
      Column() {
        // 顶栏（对照 navigationTitle "确认保存" + 取消/保存）。
        Row() {
          Text('取消')
            .fontSize(16)
            .fontColor(BubuColor.primary)
            .onClick(() => { if (this.onDismiss) this.onDismiss(); })
          Blank()
          Text('确认保存')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
          Blank()
          Text(this.saveButtonLabel())
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.savableItems().length === 0 ? BubuColor.secondaryText : BubuColor.primary)
            .opacity(this.savableItems().length === 0 ? 0.5 : 1)
            .onClick(() => { this.onTapSave(); })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        Scroll() {
          Column({ space: 14 }) {
            if (this.editableItems.length === 0) {
              this.emptyState()
            } else {
              Text(`识别到 ${this.editableItems.length} 条记录`)
                .fontSize(BubuFont.headline)
                .fontWeight(FontWeight.Bold)
                .fontColor(BubuColor.warmBrown)
                .width('100%')

              Text(this.originalText)
                .fontSize(BubuFont.caption)
                .fontColor(BubuColor.secondaryText)
                .width('100%')
                .padding(16)
                .backgroundColor(BubuColor.card)
                .borderRadius(16)

              ForEach(this.editableItems, (item: NaturalCaptureItem) => {
                this.itemCard(item)
              }, (item: NaturalCaptureItem) => `${item.id}-${this.rev}`)

              if (this.hasSymptom()) {
                Text('以上仅记录事实，不构成医疗建议；如情况严重请及时联系医生。')
                  .fontSize(11)
                  .fontColor(BubuColor.secondaryText)
                  .width('100%')
              }
              if (this.result.warnings.includes('date_inferred') || this.result.warnings.includes('item_date_dropped')) {
                Text('部分时间由系统推断或缺失，可点「编辑」修正。')
                  .fontSize(11)
                  .fontColor(BubuColor.secondaryText)
                  .width('100%')
              }
            }
          }
          .width('100%')
          .padding(16)
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BubuColor.background)
    }
    .width('100%')
    .height('100%')
  }

  private saveButtonLabel(): string {
    return this.unconfirmedCount() === 0 ? '保存' : `保存 ${this.savableItems().length} 条`;
  }

  // 保存按钮：仍有未确认项时先弹提示（对照 alert）。
  private onTapSave(): void {
    if (this.savableItems().length === 0) return;
    if (this.unconfirmedCount() > 0) {
      promptAction.showDialog({
        title: `还有 ${this.unconfirmedCount()} 条需要确认`,
        message: '疫苗、症状等敏感记录需要逐条点「确认无误」才会保存；未确认的这次不会入库。',
        buttons: [
          { text: '返回确认', color: BubuColor.secondaryText },
          { text: `仍然保存其余 ${this.savableItems().length} 条`, color: BubuColor.primary }
        ]
      }).then((res: promptAction.ShowDialogSuccessResponse) => {
        if (res.index === 1) this.saveAll();
      });
    } else {
      this.saveAll();
    }
  }

  // 对照 emptyState
  @Builder
  emptyState() {
    Column({ space: 14 }) {
      BubuMascotBadge({ badgeSize: 72, expression: BubuExpression.surprised })
      Text('这句话布布没听懂\n可以换个说法，或回首页用「记录此刻」')
        .fontSize(BubuFont.body)
        .fontColor(BubuColor.secondaryText)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 60 })
  }

  // MARK: 单条卡片（对照 itemCard）
  @Builder
  itemCard(item: NaturalCaptureItem) {
    Column({ space: 10 }) {
      // 头部：图标 + 领域 / 低置信下拉 + 需要确认 + 删除
      Row({ space: 8 }) {
        Text(this.iconEmoji(item.domain))
          .fontSize(13)
          .width(26).height(26)
          .textAlign(TextAlign.Center)
          .backgroundColor('#1AF28C9E')
          .borderRadius(13)

        if (item.confidence < 0.6) {
          // 手动分类下拉（对照 domainPicker）。
          Row({ space: 3 }) {
            Text(domainDisplayName(item.domain))
              .fontSize(BubuFont.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor(BubuColor.primary)
            Text('▾').fontSize(10).fontColor(BubuColor.primary)
          }
          .bindMenu(this.domainMenu(item))

          Text('置信度低')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.secondaryText)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor('#1AA98D82')
            .borderRadius(100)
        } else {
          Text(domainDisplayName(item.domain))
            .fontSize(BubuFont.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(BubuColor.primary)
        }

        Blank()

        if (requiresHardConfirmation(item)) {
          Text(this.confirmedIDs.has(item.id) ? '已确认' : '需要确认')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.confirmedIDs.has(item.id) ? Color.White : BubuColor.primary)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.confirmedIDs.has(item.id) ? BubuColor.success : '#1FF28C9E')
            .borderRadius(100)
        }
        Text('✕')
          .fontSize(16)
          .fontColor(BubuColor.secondaryText)
          .opacity(0.5)
          .onClick(() => { this.removeItem(item.id); })
      }
      .width('100%')

      // 标题 / 编辑标题
      if (this.editingID === item.id) {
        this.editFields(item)
      } else {
        Text(item.title)
          .fontSize(BubuFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(BubuColor.warmBrown)
          .width('100%')
      }

      // 展开区
      if (this.isExpanded(item)) {
        if (this.editingID !== item.id && this.fieldSummary(item) !== undefined) {
          Text(this.fieldSummary(item)!)
            .fontSize(BubuFont.caption)
            .fontColor(BubuColor.secondaryText)
            .width('100%')
        }
        Row({ space: 10 }) {
          if (this.editingID !== item.id && item.date !== undefined) {
            Text(`📅 ${BubuDateFormat.shortDateTime(item.date)}`)
              .fontSize(11)
              .fontColor(BubuColor.secondaryText)
          }
          Blank()
          Text(this.editingID === item.id ? '完成' : '编辑')
            .fontSize(BubuFont.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(BubuColor.primary)
            .onClick(() => { this.editingID = this.editingID === item.id ? null : item.id; })

          if (requiresHardConfirmation(item)) {
            Text(this.confirmedIDs.has(item.id) ? '取消确认' : '确认无误')
              .fontSize(BubuFont.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.confirmedIDs.has(item.id) ? BubuColor.secondaryText : Color.White)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(this.confirmedIDs.has(item.id) ? BubuColor.card : BubuColor.primary)
              .borderRadius(100)
              .onClick(() => { this.toggleConfirm(item.id); })
          }
        }
        .width('100%')
      } else {
        Row() {
          Text('▾ 展开核对')
            .fontSize(BubuFont.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(BubuColor.primary)
            .onClick(() => {
              const next = new Set<string>(this.expandedIDs);
              next.add(item.id);
              this.expandedIDs = next;
            })
          Blank()
        }
        .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .backgroundColor(BubuColor.card)
    .borderRadius(18)
    .border({
      width: (requiresHardConfirmation(item) && !this.confirmedIDs.has(item.id)) ? 1 : 0,
      color: '#59F28C9E'
    })
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
  }

  // 低置信卡片可见性（对照 expanded = expandedIDs.contains || !lowConfidence）。
  private isExpanded(item: NaturalCaptureItem): boolean {
    return this.expandedIDs.has(item.id) || item.confidence >= 0.6;
  }

  // 手动分类菜单项（对照 domainPicker 的 Menu）。
  private domainMenu(item: NaturalCaptureItem): MenuElement[] {
    const all: NaturalCaptureDomain[] = [
      NaturalCaptureDomain.vaccine, NaturalCaptureDomain.growth, NaturalCaptureDomain.meal,
      NaturalCaptureDomain.snack, NaturalCaptureDomain.supplement, NaturalCaptureDomain.water,
      NaturalCaptureDomain.sleep, NaturalCaptureDomain.symptom, NaturalCaptureDomain.checkup,
      NaturalCaptureDomain.timeline, NaturalCaptureDomain.milestone, NaturalCaptureDomain.firstTime
    ];
    return all.map((d: NaturalCaptureDomain) => {
      const el: MenuElement = {
        value: domainDisplayName(d),
        action: () => {
          item.domain = d;
          this.rev += 1;
        }
      };
      return el;
    });
  }

  private removeItem(id: string): void {
    this.editableItems = this.editableItems.filter((it: NaturalCaptureItem) => it.id !== id);
    const next = new Set<string>(this.confirmedIDs);
    next.delete(id);
    this.confirmedIDs = next;
    if (this.editingID === id) this.editingID = null;
  }

  private toggleConfirm(id: string): void {
    const next = new Set<string>(this.confirmedIDs);
    if (next.has(id)) next.delete(id); else next.add(id);
    this.confirmedIDs = next;
  }

  // MARK: 编辑字段（标题 / 时间 / 数量类）（对照 editFields）
  @Builder
  editFields(item: NaturalCaptureItem) {
    Column({ space: 8 }) {
      TextInput({ text: item.title, placeholder: '标题' })
        .fontSize(BubuFont.body)
        .fontColor(BubuColor.warmBrown)
        .backgroundColor('#99FCEDE4')
        .borderRadius(10)
        .onChange((v: string) => { item.title = v; })

      // 时间（对照 DatePicker）：弹日期选择，保留时分。
      Row() {
        Text('时间').fontSize(BubuFont.caption).fontColor(BubuColor.secondaryText)
        Blank()
        Text(item.date !== undefined ? BubuDateFormat.shortDateTime(item.date) : '未填写')
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.primary)
          .onClick(() => { this.pickDate(item); })
      }
      .width('100%')

      // 数量类字段（对照 switch domain）。
      if (item.domain === NaturalCaptureDomain.water) {
        this.amountField(item, 'amount_ml', '喝水量', 'ml')
      } else if (item.domain === NaturalCaptureDomain.growth || item.domain === NaturalCaptureDomain.checkup) {
        this.amountField(item, 'height_cm', '身高', 'cm')
        this.amountField(item, 'weight_kg', '体重', 'kg')
        this.amountField(item, 'head_circumference_cm', '头围', 'cm')
      } else if (item.domain === NaturalCaptureDomain.symptom) {
        this.amountField(item, 'temperature_celsius', '体温', '℃')
      }
    }
    .width('100%')
  }

  // 数量输入（对照 amountField + numericFieldBinding）。
  @Builder
  amountField(item: NaturalCaptureItem, key: string, label: string, unit: string) {
    Row() {
      Text(label).fontSize(BubuFont.caption).fontColor(BubuColor.secondaryText)
      TextInput({ text: this.numericText(item, key), placeholder: '未填写' })
        .type(InputType.Number)
        .textAlign(TextAlign.End)
        .fontSize(BubuFont.body)
        .layoutWeight(1)
        .backgroundColor(Color.Transparent)
        .onChange((v: string) => { this.setNumericField(item, key, v); })
      Text(unit).fontSize(BubuFont.caption).fontColor(BubuColor.secondaryText)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .backgroundColor('#73FCEDE4')
    .borderRadius(10)
  }

  // 数量字段当前文本（对照 numericFieldBinding.get）。
  private numericText(item: NaturalCaptureItem, key: string): string {
    const d = fieldDouble(item.fields, key);
    if (d !== undefined) return this.trimNumber(d);
    const s = fieldString(item.fields, key);
    return s ?? '';
  }

  // 数量字段写入（对照 numericFieldBinding.set：空→移除，数字→number，否则→string）。
  private setNumericField(item: NaturalCaptureItem, key: string, raw: string): void {
    const trimmed = raw.trim();
    const fields: Record<string, JSONValue> = item.fields;
    if (trimmed.length === 0) {
      delete fields[key];
    } else {
      const num = Number(trimmed);
      fields[key] = Number.isNaN(num) ? jvString(trimmed) : jvNumber(num);
    }
  }

  // 选日期（对照 DatePicker；保留时分）。
  private pickDate(item: NaturalCaptureItem): void {
    const current = item.date !== undefined ? item.date : new Date();
    DatePickerDialog.show({
      start: new Date(2015, 0, 1),
      end: new Date(),
      selected: current,
      onDateAccept: (value: Date) => {
        value.setHours(current.getHours(), current.getMinutes(), 0, 0);
        item.date = value;
        this.rev += 1;
      }
    });
  }

  // 关键字段摘要：让家长一眼核对（对照 fieldSummary）。
  private fieldSummary(item: NaturalCaptureItem): string | undefined {
    const parts: string[] = [];
    switch (item.domain) {
      case NaturalCaptureDomain.vaccine: {
        const v = fieldString(item.fields, 'vaccine_name'); if (v !== undefined) parts.push(v);
        const dl = fieldString(item.fields, 'dose_label'); if (dl !== undefined) parts.push(dl);
        const h = fieldString(item.fields, 'hospital'); if (h !== undefined) parts.push(h);
        break;
      }
      case NaturalCaptureDomain.growth: {
        const h = fieldDouble(item.fields, 'height_cm'); if (h !== undefined) parts.push(`身高 ${this.trimNumber(h)}cm`);
        const w = fieldDouble(item.fields, 'weight_kg'); if (w !== undefined) parts.push(`体重 ${this.trimNumber(w)}kg`);
        const hc = fieldDouble(item.fields, 'head_circumference_cm'); if (hc !== undefined) parts.push(`头围 ${this.trimNumber(hc)}cm`);
        break;
      }
      case NaturalCaptureDomain.meal:
      case NaturalCaptureDomain.snack: {
        const foods = fieldStringArray(item.fields, 'food_items');
        if (foods.length > 0) parts.push(foods.join('、'));
        const a = fieldString(item.fields, 'amount_text'); if (a !== undefined) parts.push(a);
        break;
      }
      case NaturalCaptureDomain.water: {
        const ml = fieldDouble(item.fields, 'amount_ml'); if (ml !== undefined) parts.push(`${Math.trunc(ml)}ml`);
        break;
      }
      case NaturalCaptureDomain.sleep: {
        const s = fieldISODate(item.fields, 'start_at'); if (s !== undefined) parts.push(`入睡 ${BubuDateFormat.shortTime(s)}`);
        const e = fieldISODate(item.fields, 'end_at'); if (e !== undefined) parts.push(`醒来 ${BubuDateFormat.shortTime(e)}`);
        if (parts.length === 0) {
          const m = fieldDouble(item.fields, 'duration_minutes');
          if (m !== undefined) parts.push(`约 ${this.trimNumber(m / 60)} 小时`);
        }
        break;
      }
      case NaturalCaptureDomain.symptom: {
        const symptoms = fieldStringArray(item.fields, 'symptoms');
        if (symptoms.length > 0) parts.push(symptoms.join('、'));
        const t = fieldDouble(item.fields, 'temperature_celsius'); if (t !== undefined) parts.push(`体温 ${t.toFixed(1)}℃`);
        break;
      }
      case NaturalCaptureDomain.supplement: {
        const n = fieldString(item.fields, 'supplement_name'); if (n !== undefined) parts.push(n);
        const a = fieldString(item.fields, 'amount_text'); if (a !== undefined) parts.push(a);
        break;
      }
      default:
        break;
    }
    if (parts.length === 0 && item.note !== undefined && item.note !== item.title) return item.note;
    return parts.length === 0 ? undefined : parts.join(' · ');
  }

  // 保存全部可保存项（对照 saveAll）。
  private async saveAll(): Promise<void> {
    const router = new NaturalCaptureRouter(this.authorRole);
    for (const item of this.savableItems()) {
      await router.save(item);
    }
    promptAction.showToast({ message: '已经收好啦 🌟' });
    if (this.onSaved) this.onSaved();
    if (this.onDismiss) this.onDismiss();
  }
}
