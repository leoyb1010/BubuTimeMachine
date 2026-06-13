import { util } from '@kit.ArkTS';
import { Milestone, ChildProfile } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { SyncState } from '../models/Enums';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';

// 预置里程碑（对照 iOS 适龄推荐）
interface PresetMilestone {
  title: string;
  category: string;
  emoji: string;
}

const PRESETS: PresetMilestone[] = [
  { title: '第一次抬头', category: '大运动', emoji: '🍼' },
  { title: '第一次翻身', category: '大运动', emoji: '🔄' },
  { title: '第一次独坐', category: '大运动', emoji: '🪑' },
  { title: '第一次爬行', category: '大运动', emoji: '🧎' },
  { title: '第一次站立', category: '大运动', emoji: '🧍' },
  { title: '第一次走路', category: '大运动', emoji: '👣' },
  { title: '第一次叫爸爸妈妈', category: '语言', emoji: '🗣️' },
  { title: '第一颗牙', category: '身体', emoji: '🦷' },
  { title: '第一次自己吃饭', category: '生活', emoji: '🥄' },
  { title: '第一次笑出声', category: '社交', emoji: '😄' }
];

// MARK: - 里程碑墙（对照 iOS MilestonesHomeView）
// 已点亮（达成）+ 适龄推荐（待点亮）。点待点亮项即标记达成。
@Component
export struct MilestonesView {
  @State milestones: Milestone[] = [];
  @State profile: ChildProfile | null = null;

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    let list = await AppDatabase.shared.fetchMilestones();
    // 首次进入：把预置里程碑种入（仅当库里为空）
    if (list.length === 0) {
      const now = Date.now();
      for (const p of PRESETS) {
        const m: Milestone = {
          id: util.generateRandomUUID(true),
          title: p.title, category: p.category, emoji: p.emoji,
          isCustom: false, ceremonyPlayed: false,
          syncState: SyncState.local, createdAt: now
        };
        await AppDatabase.shared.upsertMilestone(m);
      }
      list = await AppDatabase.shared.fetchMilestones();
    }
    this.milestones = list;
  }

  private get achieved(): Milestone[] {
    return this.milestones.filter(m => m.happenedAt !== undefined && m.happenedAt !== null);
  }
  private get pending(): Milestone[] {
    return this.milestones.filter(m => m.happenedAt === undefined || m.happenedAt === null);
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('里程碑')
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown).width('100%')

        if (this.achieved.length > 0) {
          Text(`⭐ 已点亮 ${this.achieved.length}`).fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.primary).width('100%')
          Grid() {
            ForEach(this.achieved, (m: Milestone) => {
              GridItem() { this.medallion(m, true) }
            }, (m: Milestone) => m.id)
          }
          .columnsTemplate('1fr 1fr 1fr').columnsGap(12).rowsGap(12)
          .height(Math.ceil(this.achieved.length / 3) * 110)
        }

        Text('适龄推荐 · 待点亮').fontSize(16).fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.secondaryText).width('100%').margin({ top: 8 })
        Grid() {
          ForEach(this.pending, (m: Milestone) => {
            GridItem() { this.medallion(m, false) }
          }, (m: Milestone) => m.id)
        }
        .columnsTemplate('1fr 1fr 1fr').columnsGap(12).rowsGap(12)
        .height(Math.ceil(this.pending.length / 3) * 110)
      }
      .padding(16).width('100%')
    }
    .backgroundColor(BubuColor.cream).width('100%').height('100%')
  }

  @Builder
  medallion(m: Milestone, lit: boolean) {
    Column({ space: 4 }) {
      Text(m.emoji).fontSize(34).opacity(lit ? 1 : 0.35)
      Text(m.title).fontSize(11).fontColor(lit ? BubuColor.warmBrown : BubuColor.secondaryText)
        .maxLines(2).textAlign(TextAlign.Center)
      if (lit && this.profile && m.happenedAt) {
        Text(AgeCalculator.compactAge(this.profile!.birthday, m.happenedAt!))
          .fontSize(9).fontColor(BubuColor.primary)
      }
    }
    .width('100%').height(98).justifyContent(FlexAlign.Center)
    .backgroundColor(lit ? '#FFF3F0' : BubuColor.card).borderRadius(14)
    .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.92 })
    .onClick(() => {
      if (!lit) { this.lightUp(m); }
    })
  }

  private async lightUp(m: Milestone): Promise<void> {
    m.happenedAt = Date.now();
    if (this.profile) {
      m.ageDescription = AgeCalculator.ageDescription(this.profile.birthday, m.happenedAt);
    }
    m.syncState = SyncState.local;
    await AppDatabase.shared.upsertMilestone(m);
    await this.reload();
    promptAction.showToast({ message: `点亮了「${m.title}」🌟` });
  }
}
