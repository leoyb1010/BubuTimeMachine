import { Entry, ChildProfile, Media } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { MediaStore } from '../services/MediaStore';
import { AgeCalculator } from '../models/AgeCalculator';
import { moodEmoji, Mood, syncStateFriendlyText, SyncState } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';
import { EntryDetailView } from './EntryDetailView';

// MARK: - 时光轴（对照 iOS TimelineView）
// 所有未归档瞬间按时间倒序；每条显示心情/原文/当时年龄/同步状态。
@Component
export struct TimelineView {
  @State entries: Entry[] = [];
  @State profile: ChildProfile | null = null;
  // entryId → 首张照片沙盒绝对路径
  @State photoMap: Map<string, string> = new Map();
  @State detailEntry: Entry | null = null;
  @State showDetail: boolean = false;

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    const entries = await AppDatabase.shared.fetchEntries(false) ?? [];
    this.entries = entries;
    const map = new Map<string, string>();
    for (const e of entries) {
      const media = await AppDatabase.shared.fetchMediaForEntry(e.id) ?? [];
      const photo = media.find(m => m.typeRaw === 'photo' && m.localFileName);
      if (photo && photo.localFileName) {
        map.set(e.id, 'file://' + MediaStore.shared.fullPath(photo.localFileName));
      }
    }
    this.photoMap = map;
  }

  private entryList(): Entry[] {
    return this.entries ?? [];
  }

  build() {
    if (this.showDetail && this.detailEntry) {
      Column() {
        Row({ space: 12 }) {
          Button('返回')
            .backgroundColor('#F3F3F3')
            .fontColor(BubuColor.warmBrown)
            .onClick(() => {
              this.showDetail = false;
              this.detailEntry = null;
              this.reload();
            })
          Text('记录详情')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })
        EntryDetailView({
          entry: this.detailEntry!,
          onDismiss: () => {
            this.showDetail = false;
            this.detailEntry = null;
            this.reload();
          }
        })
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else {
      this.mainPage()
    }
  }

  @Builder
  mainPage() {
    Column() {
      Text('时光轴')
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        .width('100%').padding({ left: 16, top: 16, bottom: 8 })

      if (this.entryList().length === 0) {
        Column({ space: 10 }) {
          Text('🐣').fontSize(56)
          Text('还没有记录呢').fontSize(16).fontColor(BubuColor.warmBrown)
          Text('回首页点「记录此刻」，留住布布的第一个瞬间').fontSize(12).fontColor(BubuColor.secondaryText)
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 12 }) {
          ForEach(this.entryList(), (e: Entry) => {
            ListItem() {
              this.entryCard(e)
            }
            .onClick(() => {
              this.detailEntry = e;
              this.showDetail = true;
            })
            // 入场动画：列表项渐显 + 轻微上移
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 })))
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

      if (this.photoMap.has(e.id)) {
        Image(this.photoMap.get(e.id))
          .width('100%').height(180).borderRadius(12).objectFit(ImageFit.Cover)
      }

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
