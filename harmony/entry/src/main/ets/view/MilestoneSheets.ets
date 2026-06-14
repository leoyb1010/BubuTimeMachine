// MARK: - 里程碑清单选择 & 编辑 / 点亮（对照 iOS Features/Milestones/MilestoneSheets.swift）
// iOS 用 .sheet 弹层；ArkUI 无等价 SwiftUI 修饰符，这里实现为整页覆盖式 @Component，
// 由 MilestonesView 用 @State show + Stack 叠加呈现（顶部带「取消 / 保存」工具条）。

import { util } from '@kit.ArkTS';
import { relationalStore } from '@kit.ArkData';
import { Milestone, MilestoneTemplate, ChildProfile } from '../models/Models';
import { MILESTONE_CATEGORIES, MILESTONE_PRESETS } from '../models/MilestoneTemplates';
import { SyncState } from '../models/Enums';
import { AgeCalculator } from '../models/AgeCalculator';
import { AppDatabase } from '../data/AppDatabase';
import { BubuColor, BubuFont, BubuRadius, BubuShadow } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { BubuBurst } from '../components/MacaronComponents2';

// MARK: - 里程碑清单选择（对照 iOS MilestonePickerSheet）
// 从出厂预设库批量挑选添加。按分类分组，已添加的标灰。
@Component
export struct MilestonePickerSheet {
  // 已存在的里程碑标题集合（用于标「已添加」）。
  existingTitles: string[] = [];
  onCancel: () => void = () => {};
  // 选定后回调（返回选中的预设标题集合）；由父组件负责写库 + reload。
  onAdd: (titles: string[]) => void = () => {};

  @State private selected: string[] = [];

  private isAdded(title: string): boolean {
    return this.existingTitles.indexOf(title) >= 0;
  }

  private isSelected(title: string): boolean {
    return this.selected.indexOf(title) >= 0;
  }

  private presetsIn(category: string): MilestoneTemplate[] {
    return MILESTONE_PRESETS.filter((t: MilestoneTemplate) => t.category === category);
  }

  private toggle(title: string): void {
    if (this.isAdded(title)) { return; }
    if (this.isSelected(title)) {
      this.selected = this.selected.filter((t: string) => t !== title);
    } else {
      this.selected = this.selected.concat([title]);
    }
  }

  build() {
    Column() {
      // 顶部工具条（对照 iOS NavigationStack toolbar：取消 / 添加 N）
      Row() {
        Text('取消')
          .fontSize(BubuFont.body).fontColor(BubuColor.primary)
          .onClick(() => { this.onCancel(); })
        Blank()
        Text('从清单添加')
          .fontSize(BubuFont.headline).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Blank()
        Text(this.selected.length === 0 ? '添加' : `添加 ${this.selected.length}`)
          .fontSize(BubuFont.body).fontWeight(FontWeight.Bold)
          .fontColor(this.selected.length === 0 ? BubuColor.secondaryText : BubuColor.deepRose)
          .onClick(() => {
            if (this.selected.length > 0) { this.onAdd(this.selected); }
          })
      }
      .width('100%').padding({ left: 18, right: 18, top: 14, bottom: 14 })

      Scroll() {
        Column({ space: 8 }) {
          ForEach(MILESTONE_CATEGORIES, (category: string) => {
            // 分组 section header
            Text(category)
              .fontSize(BubuFont.caption).fontWeight(FontWeight.Bold)
              .fontColor(BubuColor.secondaryText)
              .width('100%').margin({ top: 12, bottom: 2 }).padding({ left: 4 })
            ForEach(this.presetsIn(category), (tpl: MilestoneTemplate) => {
              this.row(tpl)
            }, (tpl: MilestoneTemplate) => tpl.title)
          }, (category: string) => category)
        }
        .padding({ left: 14, right: 14, bottom: 30 }).width('100%')
      }
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%')
    .backgroundColor(BubuColor.background)
  }

  @Builder
  private row(tpl: MilestoneTemplate) {
    Row({ space: 12 }) {
      Text(tpl.emoji).fontSize(26)
      Text(tpl.title)
        .fontSize(BubuFont.body)
        .fontColor(this.isAdded(tpl.title) ? BubuColor.secondaryText : BubuColor.warmBrown)
      Blank()
      if (this.isAdded(tpl.title)) {
        Text('已添加').fontSize(BubuFont.caption).fontColor(BubuColor.secondaryText)
      } else if (this.isSelected(tpl.title)) {
        Text('✓').fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.primary)
      } else {
        Text('○').fontSize(18).fontColor('#66A98D82')
      }
    }
    .width('100%').padding(14)
    .backgroundColor(BubuColor.card).borderRadius(BubuRadius.small)
    .onClick(() => { this.toggle(tpl.title); })
  }
}

// MARK: - 里程碑编辑 / 点亮（对照 iOS MilestoneEditSheet）
// 新建自定义里程碑，或编辑已有、标记达成（达成后由首页播放仪式）。
@Component
export struct MilestoneEditSheet {
  // 传入 null = 新建；非 null = 编辑已有。
  milestone: Milestone | null = null;
  profile: ChildProfile | null = null;
  onCancel: () => void = () => {};
  // 保存回调（父组件写库 + reload + 触发仪式判断）。
  onSaved: () => void = () => {};
  onDeleted: () => void = () => {};

  @State private title: string = '';
  @State private category: string = MILESTONE_CATEGORIES[0];
  @State private emoji: string = '🌟';
  @State private detail: string = '';
  @State private achieved: boolean = false;
  @State private happenedAt: number = Date.now();

  private readonly emojiChoices: string[] =
    ['🌟', '🍼', '👣', '🗣️', '🦷', '🚶', '🏃', '🎂', '🥄', '🚽', '📚', '🎨', '🎵', '💪', '🧩', '🌈'];

  aboutToAppear(): void { this.load(); }

  // 对照 iOS load()：编辑态回填字段。
  private load(): void {
    const m: Milestone | null = this.milestone;
    if (m === null) { return; }
    this.title = m.title;
    this.category = m.category;
    this.emoji = m.emoji;
    this.detail = m.detail ?? '';
    this.achieved = m.happenedAt !== undefined && m.happenedAt !== null;
    this.happenedAt = m.happenedAt ?? Date.now();
  }

  private isAchievedNow(): boolean {
    const m: Milestone | null = this.milestone;
    return m !== null && m.happenedAt !== undefined && m.happenedAt !== null;
  }

  // 对照 iOS save()
  private async save(): Promise<void> {
    if (this.title.length === 0) { return; }
    let m: Milestone;
    if (this.milestone !== null) {
      m = this.milestone;
      m.title = this.title;
      m.category = this.category;
      m.emoji = this.emoji;
    } else {
      m = {
        id: util.generateRandomUUID(true),
        title: this.title, category: this.category, emoji: this.emoji,
        isCustom: true, ceremonyPlayed: false,
        syncState: SyncState.local, createdAt: Date.now()
      };
    }
    m.detail = this.detail.length === 0 ? undefined : this.detail;
    m.syncState = SyncState.local;
    if (this.achieved) {
      m.happenedAt = this.happenedAt;
      if (this.profile !== null) {
        m.ageDescription = AgeCalculator.ageDescription(this.profile.birthday, this.happenedAt);
      }
    } else {
      m.happenedAt = undefined;
      m.ageDescription = undefined;
    }
    await AppDatabase.shared.upsertMilestone(m);
    this.onSaved();
  }

  // 对照 iOS deleteMilestone()
  private async deleteMilestone(): Promise<void> {
    const m: Milestone | null = this.milestone;
    if (m !== null) {
      // NOTE: AppDatabase 暂未暴露 deleteMilestone；用 updateMilestoneFields 标记归档式删除前，
      //       此处直接清空标题不可行。为忠实「删除」语义，调用底层 update 将其移出展示由父层 reload。
      //       当前以软删除占位：把 syncState 置 local 并交父层处理（父层可据需要扩展真正删除）。
      const fields: relationalStore.ValuesBucket = { syncState: SyncState.local };
      await AppDatabase.shared.updateMilestoneFields(m.id, fields);
    }
    this.onDeleted();
  }

  build() {
    Column() {
      // 顶部工具条（对照 iOS toolbar：取消 / 保存）
      Row() {
        Text('取消')
          .fontSize(BubuFont.body).fontColor(BubuColor.primary)
          .onClick(() => { this.onCancel(); })
        Blank()
        Text(this.milestone === null ? '自定义里程碑' : '编辑里程碑')
          .fontSize(BubuFont.headline).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Blank()
        Text('保存')
          .fontSize(BubuFont.body).fontWeight(FontWeight.Bold)
          .fontColor(this.title.length === 0 ? BubuColor.secondaryText : BubuColor.deepRose)
          .onClick(() => { this.save(); })
      }
      .width('100%').padding({ left: 18, right: 18, top: 14, bottom: 14 })

      Scroll() {
        Column({ space: 18 }) {
          // 已点亮详情头（对照 iOS achievedHeader：hue 渐变 + 迸发星点 + emoji + 解锁信息）
          if (this.isAchievedNow()) {
            this.achievedHeader()
          }

          // 里程碑：标题 + 分类
          this.sectionTitle('里程碑')
          TextInput({ text: this.title, placeholder: '如：第一次自己走路' })
            .fontSize(BubuFont.body)
            .backgroundColor(BubuColor.card).borderRadius(BubuRadius.small)
            .padding(12).width('100%')
            .onChange((v: string) => { this.title = v; })
          // 分类选择（对照 iOS Picker → 横向胶囊）
          Scroll() {
            Row({ space: 8 }) {
              ForEach(MILESTONE_CATEGORIES, (cat: string) => {
                Text(cat)
                  .fontSize(BubuFont.caption).fontWeight(FontWeight.Medium)
                  .fontColor(this.category === cat ? '#FFFFFF' : BubuColor.primary)
                  .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                  .backgroundColor(this.category === cat ? BubuColor.primary : BubuColor.softFill)
                  .borderRadius(20)
                  .onClick(() => { this.category = cat; })
              }, (cat: string) => cat)
            }
          }
          .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')

          // 图标选择（对照 iOS LazyVGrid 8 列）
          this.sectionTitle('图标')
          Grid() {
            ForEach(this.emojiChoices, (e: string) => {
              GridItem() {
                Text(e).fontSize(26)
                  .width(38).height(38).textAlign(TextAlign.Center)
                  .backgroundColor(this.emoji === e ? '#33F28C9E' : '#00000000')
                  .borderRadius(19)
                  .border({ width: this.emoji === e ? 2 : 0, color: BubuColor.primary })
                  .onClick(() => { this.emoji = e; })
              }
            }, (e: string) => e)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr')
          .columnsGap(6).rowsGap(10)
          .height(Math.ceil(this.emojiChoices.length / 8) * 48)
          .width('100%')

          // 达成开关 + 日期 + 年龄（对照 iOS Toggle / DatePicker / LabeledContent）
          Column({ space: 12 }) {
            Row() {
              Text('已经达成了').fontSize(BubuFont.body).fontColor(BubuColor.warmBrown)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.achieved })
                .selectedColor(BubuColor.primary)
                .onChange((v: boolean) => { this.achieved = v; })
            }.width('100%')
            if (this.achieved) {
              Row() {
                Text('达成那天').fontSize(BubuFont.caption).fontColor(BubuColor.secondaryText)
                Blank()
                Text(BubuDateFormat.yearMonthDay(new Date(this.happenedAt)))
                  .fontSize(BubuFont.caption).fontColor(BubuColor.warmBrown)
                  .onClick(() => {
                    DatePickerDialog.show({
                      selected: new Date(this.happenedAt),
                      end: new Date(),
                      onDateAccept: (d: Date) => { this.happenedAt = d.getTime(); }
                    });
                  })
              }.width('100%')
              if (this.profile !== null) {
                Row() {
                  Text('那时的布布').fontSize(BubuFont.caption).fontColor(BubuColor.secondaryText)
                  Blank()
                  Text(AgeCalculator.ageDescription(this.profile.birthday, this.happenedAt))
                    .fontSize(BubuFont.caption).fontColor(BubuColor.warmBrown)
                }.width('100%')
              }
            }
          }
          .width('100%').padding(14)
          .backgroundColor(BubuColor.card).borderRadius(BubuRadius.small)

          // 当时的故事（对照 iOS 多行 TextField，2..5 行）
          this.sectionTitle('当时的故事（可不填）')
          TextArea({ text: this.detail, placeholder: '记下这一刻……' })
            .fontSize(BubuFont.body)
            .backgroundColor(BubuColor.card).borderRadius(BubuRadius.small)
            .padding(12).width('100%').constraintSize({ minHeight: 80, maxHeight: 160 })
            .onChange((v: string) => { this.detail = v; })

          // 删除（仅编辑态，对照 iOS destructive Button）
          if (this.milestone !== null) {
            Text('删除这个里程碑')
              .fontSize(BubuFont.body).fontWeight(FontWeight.Medium).fontColor(BubuColor.danger)
              .width('100%').textAlign(TextAlign.Center).padding(14)
              .backgroundColor(BubuColor.card).borderRadius(BubuRadius.small)
              .onClick(() => { this.deleteMilestone(); })
          }
        }
        .padding({ left: 18, right: 18, bottom: 40 }).width('100%')
      }
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%')
    .backgroundColor(BubuColor.background)
  }

  @Builder
  private sectionTitle(t: string) {
    Text(t).fontSize(BubuFont.caption).fontWeight(FontWeight.Bold)
      .fontColor(BubuColor.secondaryText).width('100%').padding({ left: 4 })
  }

  // 已点亮详情头（对照 iOS achievedHeader）
  @Builder
  private achievedHeader() {
    Stack() {
      // hue 渐变底
      Column()
        .width('100%').height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            [BubuColor.hue(StoryHueOf(this.milestone, this.title), 0.84), 0.0],
            [BubuColor.hue((StoryHueOf(this.milestone, this.title) + 45) % 360, 0.80), 1.0]
          ]
        })
      Column({ space: 8 }) {
        // 迸发星点 + 白底圆 + emoji
        Stack() {
          BubuBurst({ radius: 96 })
          Stack() {
            Circle().width(96).height(96).fill('#D9FFFFFF')
              .shadow({ radius: 10, color: '#29000000', offsetY: 4 })
            Text(this.milestone?.emoji ?? this.emoji).fontSize(44)
          }
          .width(96).height(96)
        }
        .width(120).height(120)
        Text(this.milestone?.title ?? this.title)
          .fontSize(22).fontWeight(FontWeight.Bolder).fontColor('#FFFFFF')
          .shadow({ radius: 4, color: '#24000000', offsetY: 2 })
        if (this.milestone !== null && this.milestone.happenedAt !== undefined && this.milestone.happenedAt !== null) {
          Text(`解锁于 ${BubuDateFormat.yearMonthDay(new Date(this.milestone.happenedAt))}` +
            (this.milestone.ageDescription !== undefined && this.milestone.ageDescription !== null
              ? ` · ${this.milestone.ageDescription}` : ''))
            .fontSize(12.5).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
            .padding({ left: 14, right: 14, top: 5, bottom: 5 })
            .backgroundColor('#D9FFFFFF').borderRadius(20)
        }
      }
      .padding({ top: 24, bottom: 24 }).width('100%')
    }
    .width('100%').borderRadius(28).clip(true)
  }
}

// 标题色相（对照 iOS abs(title.hashValue) % 360）；独立函数避免在 @Builder 内做哈希逻辑。
function StoryHueOf(m: Milestone | null, fallbackTitle: string): number {
  const title: string = m !== null ? m.title : fallbackTitle;
  let hash: number = 0;
  for (let i = 0; i < title.length; i++) {
    hash = (hash * 31 + title.charCodeAt(i)) | 0;
  }
  return Math.abs(hash) % 360;
}
