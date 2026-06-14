// MARK: - 布布的成长绘本（首页）（对照 iOS Features/Story/BubuStoryView.swift）
// butter→peach→pink 大横幅 +「共 N 章」+ 倾斜书卡列表。
// 章节由已达成里程碑实时编织（StoryChapterBuilder），点进翻页阅读器。

import { Milestone } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { StoryChapter, StoryChapterBuilder, chapterNoText } from './StoryChapter';
import { BubuStoryReaderView, dreamPhoto } from './BubuStoryReaderView';
import { BubuColor, BubuShadow } from '../theme/BubuTheme';
import { BubuSparkle } from '../components/MacaronComponents';

@Component
export struct BubuStoryView {
  @Prop compact: boolean = false;
  @State private milestones: Milestone[] = [];
  // 阅读器覆盖（iOS NavigationLink → ArkUI 内部 @State 整页覆盖；RootPage 导航另波次接管）。
  @State private readerOpen: boolean = false;
  @State private readerStart: number = 0;

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.milestones = await AppDatabase.shared.fetchMilestones() ?? [];
  }

  private chapters(): StoryChapter[] {
    return StoryChapterBuilder.chapters(this.milestones);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Scroll() {
          Column({ space: 18 }) {
            this.banner()
            if (this.chapters().length === 0) {
              this.emptyState()
            } else {
              Column({ space: 14 }) {
                ForEach(this.chapters(), (ch: StoryChapter, idx: number) => {
                  this.chapterCard(ch, idx)
                }, (ch: StoryChapter) => ch.id)
              }.width('100%')
            }
            Blank().height(30)
          }
          .padding({ left: 18, right: 18, top: 8 }).width('100%')
        }
        .layoutWeight(1)
        .translate({ x: 0, y: this.compact ? -40 : 0 })
        .backgroundColor(BubuColor.background)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BubuColor.background)

      // 阅读器覆盖
      if (this.readerOpen) {
        BubuStoryReaderView({
          chapters: this.chapters(),
          startIndex: this.readerStart,
          onBack: () => { this.readerOpen = false; }
        })
      }
    }
    .width('100%').height('100%')
  }

  // 大横幅（对照 iOS banner）
  @Builder
  private banner() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: 6 }) {
        Text('一本正在生长的书')
          .fontSize(12.5).fontWeight(FontWeight.Bold).fontColor('#F2FFFFFF')
        Text('布布的成长绘本')
          .fontSize(26).fontWeight(FontWeight.Bolder).fontColor('#FFFFFF')
          .shadow({ radius: 4, color: '#1F000000', offsetY: 2 })
        Text(`由你记录的点滴，自动编织成故事 · 共 ${this.chapters().length} 章`)
          .fontSize(12.5).fontWeight(FontWeight.Medium).fontColor('#F2FFFFFF')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%').padding(22)
      BubuSparkle({ starSize: 14, color: '#F2FFFFFF' }).margin(18)
    }
    .width('100%')
    .linearGradient({
      angle: 135,
      colors: [
        [BubuColor.butter, 0.0],
        [BubuColor.peach, 0.5],
        [BubuColor.pink, 1.0]
      ]
    })
    .borderRadius(28)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
  }

  // 倾斜书卡（对照 iOS chapterCard）
  @Builder
  private chapterCard(ch: StoryChapter, index: number) {
    Row({ space: 14 }) {
      // 倾斜小图（对照 iOS rotationEffect ±3°）
      Stack() {
        dreamPhoto(ch.hue, 64, 12, ch.emoji)
      }
      .rotate({ angle: index % 2 === 0 ? -3 : 3 })
      Column({ space: 3 }) {
        Text(`${chapterNoText(ch)}${ch.ageText.length === 0 ? '' : ` · ${ch.ageText}`}`)
          .fontSize(11.5).fontWeight(FontWeight.Bold).fontColor(BubuColor.deepRose)
        Text(ch.title)
          .fontSize(16.5).fontWeight(FontWeight.Bolder).fontColor(BubuColor.warmBrown)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(ch.lines.length > 0 ? ch.lines[0] : '')
          .fontSize(12).fontWeight(FontWeight.Medium).fontColor(BubuColor.secondaryText)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text('›').fontSize(18).fontWeight(FontWeight.Bold).fontColor(BubuColor.peach)
    }
    .width('100%').padding(14)
    .backgroundColor(BubuColor.card).borderRadius(24)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => { this.readerStart = index; this.readerOpen = true; })
  }

  // 空态（对照 iOS emptyState）
  @Builder
  private emptyState() {
    Column({ space: 10 }) {
      Text('✦').fontSize(44).fontColor(BubuColor.peach)
      Text('绘本还是空白的').fontSize(16).fontWeight(FontWeight.Bolder).fontColor(BubuColor.warmBrown)
      Text('去「里程碑」点亮布布的第一次，\n并写下那一天的故事，这里就会长出第一章')
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor(BubuColor.secondaryText)
        .textAlign(TextAlign.Center)
    }
    .width('100%').padding({ top: 50, bottom: 50 })
  }
}
