// MARK: - 成长绘本 · 翻页阅读器（对照 iOS Features/Story/BubuStoryReaderView.swift）
// 全屏 hue 渐变 + 大图 + 章号/标题 + 正文逐行浮现 + 进度点 + 上/下一章。
// iOS 用手动 rotation3DEffect 翻页；ArkUI 用 Swiper 承载分章，保留进度点 + 顶/底栏。

import { StoryChapter, chapterNoText } from './StoryChapter';
import { BubuColor } from '../theme/BubuTheme';

@Component
export struct BubuStoryReaderView {
  chapters: StoryChapter[] = [];
  startIndex: number = 0;
  onBack: () => void = () => {};

  @State private index: number = 0;
  private swiperCtrl: SwiperController = new SwiperController();

  aboutToAppear(): void {
    this.index = Math.max(0, Math.min(this.startIndex, this.chapters.length - 1));
  }

  private current(): StoryChapter | null {
    if (this.chapters.length === 0) { return null; }
    const i: number = Math.max(0, Math.min(this.index, this.chapters.length - 1));
    return this.chapters[i];
  }

  build() {
    Stack() {
      // 全屏 hue 渐变底（随当前章变化，对照 iOS LinearGradient）
      Column()
        .width('100%').height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            [BubuColor.hue(this.current()?.hue ?? 0, 0.92), 0.0],
            [BubuColor.hue(((this.current()?.hue ?? 0) + 30) % 360, 0.88), 1.0]
          ]
        })

      Column() {
        // 顶部：返回 + 进度点（对照 iOS topBar）
        this.topBar()

        // 分章 Swiper（每页一章正文）
        Swiper(this.swiperCtrl) {
          ForEach(this.chapters, (ch: StoryChapter) => {
            this.page(ch)
          }, (ch: StoryChapter) => ch.id)
        }
        .index(this.index)
        .loop(false)
        .indicator(false)
        .layoutWeight(1)
        .onChange((i: number) => { this.index = i; })

        // 底部：上/下一章（对照 iOS bottomBar）
        this.bottomBar()
      }
      .width('100%').height('100%')
    }
    .width('100%').height('100%')
  }

  // 顶部：返回 + 进度点
  @Builder
  private topBar() {
    Row() {
      Text('‹')
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        .width(40).height(40).textAlign(TextAlign.Center)
        .backgroundColor('#B3FFFFFF').borderRadius(20)
        .onClick(() => { this.onBack(); })
      Blank()
      Row({ space: 5 }) {
        ForEach(this.chapters, (ch: StoryChapter, i: number) => {
          // 当前章为长条，其余为圆点（对照 iOS Capsule）
          Stack()
            .width(i === this.index ? 18 : 7).height(7)
            .backgroundColor(i === this.index ? '#FFFFFF' : '#8CFFFFFF')
            .borderRadius(4)
        }, (ch: StoryChapter) => ch.id)
      }
      Blank()
      Stack().width(40).height(40)
    }
    .width('100%').padding({ left: 18, right: 18, top: 8 })
  }

  // 正文页（对照 iOS page）
  @Builder
  private page(ch: StoryChapter) {
    Scroll() {
      Column() {
        // 大图（梦幻照片占位，对照 iOS BubuDreamPhoto 150pt）
        Stack() {
          dreamPhoto(ch.hue, 150, 30, ch.emoji)
        }
        .margin({ top: 14, bottom: 22 })

        Text(`${chapterNoText(ch)}${ch.ageText.length === 0 ? '' : ` · ${ch.ageText}`}`)
          .fontSize(13).fontWeight(FontWeight.Bolder).fontColor('#E6FFFFFF')
        Text(ch.title)
          .fontSize(24).fontWeight(FontWeight.Bolder).fontColor('#FFFFFF')
          .shadow({ radius: 6, color: '#24000000', offsetY: 2 })
          .textAlign(TextAlign.Center).margin({ top: 4 })

        // 正文逐行（对照 iOS StoryLine 逐行浮现；ArkUI 简化为静态多行）
        Column({ space: 12 }) {
          ForEach(ch.lines, (line: string, i: number) => {
            Text(line)
              .fontSize(16.5).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
              .textAlign(TextAlign.Center).lineHeight(24)
              .shadow({ radius: 4, color: '#1F000000', offsetY: 1 })
          }, (line: string, i: number) => `${i}-${line}`)
        }
        .margin({ top: 20 }).padding({ left: 26, right: 26 }).width('100%')
      }
      .width('100%').padding({ bottom: 20 })
    }
    .width('100%').height('100%').scrollBar(BarState.Off)
  }

  // 底部：上/下一章（对照 iOS bottomBar）
  @Builder
  private bottomBar() {
    Row() {
      this.navButton('‹ 上一章', this.index > 0, () => {
        if (this.index > 0) { this.index = this.index - 1; this.swiperCtrl.showPrevious(); }
      })
      Blank()
      this.navButton('下一章 ›', this.index < this.chapters.length - 1, () => {
        if (this.index < this.chapters.length - 1) { this.index = this.index + 1; this.swiperCtrl.showNext(); }
      })
    }
    .width('100%').padding({ left: 24, right: 24, top: 8, bottom: 36 })
  }

  @Builder
  private navButton(title: string, enabled: boolean, action: () => void) {
    Text(title)
      .fontSize(13.5).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      .padding({ left: 18, right: 18 }).height(44)
      .backgroundColor(enabled ? '#D9FFFFFF' : '#59FFFFFF').borderRadius(22)
      .opacity(enabled ? 1 : 0.6)
      .onClick(() => { if (enabled) { action(); } })
  }
}

// MARK: - 梦幻照片占位（对照 iOS BubuDreamPhoto）
// iOS 是一张柔色梦幻底图 + 中央 motif；本切片无资源，用 hue 渐变方块 + 大 emoji 近似。
@Builder
export function dreamPhoto(hue: number, size: number, radius: number, motif: string) {
  Stack() {
    Column()
      .width(size).height(size)
      .linearGradient({
        angle: 135,
        colors: [
          [BubuColor.hue(hue, 0.88), 0.0],
          [BubuColor.hue((hue + 40) % 360, 0.82), 1.0]
        ]
      })
      .borderRadius(radius)
      .border({ width: 6, color: '#99FFFFFF' })
      .shadow({ radius: 16, color: '#2E000000', offsetY: 8 })
    Text(motif).fontSize(size * 0.42)
  }
  .width(size).height(size)
}
