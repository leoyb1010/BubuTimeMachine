import { Entry, ChildProfile } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { AgeCalculator } from '../models/AgeCalculator';
import { moodEmoji, Mood, syncStateFriendlyText, SyncState } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';

// MARK: - 时光轴（对照 iOS TimelineView）
// 所有未归档瞬间按时间倒序；每条显示心情/原文/当时年龄/同步状态。
@Component
export struct TimelineView {
  @State entries: Entry[] = [];
  @State profile: ChildProfile | null = null;

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    this.entries = await AppDatabase.shared.fetchEntries(false);
  }

  build() {
    Column() {
      Text('时光轴')
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        .width('100%').padding({ left: 16, top: 16, bottom: 8 })

      if (this.entries.length === 0) {
        Column({ space: 10 }) {
          Text('🐣').fontSize(56)
          Text('还没有记录呢').fontSize(16).fontColor(BubuColor.warmBrown)
          Text('回首页点「记录此刻」，留住布布的第一个瞬间').fontSize(12).fontColor(BubuColor.secondaryText)
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 12 }) {
          ForEach(this.entries, (e: Entry) => {
            ListItem() {
              this.entryCard(e)
            }
          }, (e: Entry) => e.id)
        }
        .layoutWeight(1).padding({ left: 16, right: 16 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%').height('100%').backgroundColor(BubuColor.cream)
  }

  @Builder
  entryCard(e: Entry) {
    Column({ space: 6 }) {
      Row() {
        Text(moodEmoji(e.moodRaw as Mood | undefined)).fontSize(22)
        Column() {
          if (this.profile) {
            Text(AgeCalculator.compactAge(this.profile!.birthday, e.happenedAt))
              .fontSize(12).fontWeight(FontWeight.Medium).fontColor(BubuColor.primary)
          }
          Text(this.dateText(e.happenedAt)).fontSize(11).fontColor(BubuColor.secondaryText)
        }.alignItems(HorizontalAlign.Start).margin({ left: 8 })
        Blank()
        Text(e.authorRole).fontSize(11).fontColor(BubuColor.secondaryText)
      }.width('100%')

      if (e.note && e.note.length > 0) {
        Text(e.note).fontSize(15).fontColor(BubuColor.warmBrown)
          .width('100%').maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Text(syncStateFriendlyText(e.syncState as SyncState))
        .fontSize(10).fontColor(BubuColor.secondaryText).alignSelf(ItemAlign.End)
    }
    .padding(14).width('100%')
    .backgroundColor(BubuColor.card).borderRadius(16)
    .shadow({ radius: 8, color: '#14000000', offsetY: 2 })
  }

  private dateText(ms: number): string {
    const d = new Date(ms);
    return `${d.getFullYear()}.${d.getMonth() + 1}.${d.getDate()}`;
  }
}
