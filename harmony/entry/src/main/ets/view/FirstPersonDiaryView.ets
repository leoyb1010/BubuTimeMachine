import { Entry, Media } from '../models/Models';
import { MediaType, SyncState } from '../models/Enums';
import { AppDatabase } from '../data/AppDatabase';
import { AIService } from '../services/AIService';
import { ServerConfig } from '../services/ServerConfig';
import { BubuColor, BubuFont, BubuRadius, BubuShadow } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { BubuMascotBadge } from '../components/BubuMascotBadge';
import { BubuExpression } from '../theme/BubuExpression';
import { MediaThumbnail } from '../components/MediaThumbnail';
import { promptAction } from '@kit.ArkUI';

// MARK: - 第一人称日记（对照 iOS Features/AIStudio/FirstPersonDiaryView.swift）
// 选一条记录 → AI 把父母视角改写成布布第一人称（打字机动效）→ 可保存回 Entry。

@Component
export struct FirstPersonDiaryView {
  // 返回魔法屋首页（对照 iOS 导航返回）。
  onBack: () => void = () => {};

  @State private entries: Entry[] = [];
  // entryId → 该条第一张照片（用于头像）。
  @State private photoByEntry: Map<string, Media> = new Map();
  @State private selectedId: string = '';
  @State private generating: boolean = false;
  @State private output: string = '';
  @State private displayed: string = '';
  @State private errorText: string = '';

  private theme: string = BubuColor.primary;

  aboutToAppear(): void { this.reload(); }

  // 只取有文字的记录作候选（对照 iOS candidates）。
  private candidates(): Entry[] {
    return this.entries.filter((e: Entry): boolean => e.note !== undefined && e.note.length > 0);
  }

  private async reload(): Promise<void> {
    const all = await AppDatabase.shared.fetchEntries(false);
    this.entries = all ?? [];
    // 预取每条记录首张照片做头像（对照 iOS entry.media.first(photo)）。
    const map = new Map<string, Media>();
    for (const e of this.entries) {
      if (e.note === undefined || e.note.length === 0) continue;
      const media = await AppDatabase.shared.fetchMediaForEntry(e.id);
      const photo = media.find((m: Media): boolean => m.typeRaw === MediaType.photo);
      if (photo !== undefined) map.set(e.id, photo);
    }
    this.photoByEntry = map;
  }

  private selectedEntry(): Entry | undefined {
    return this.entries.find((e: Entry): boolean => e.id === this.selectedId);
  }

  build() {
    Column() {
      this.navBar()
      Scroll() {
        Column({ space: 20 }) {
          this.intro()
          this.entryPicker()
          if (this.selectedId.length > 0) { this.generateArea() }
        }
        .padding(16)
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
    .backgroundColor(BubuColor.background)
    .width('100%')
    .height('100%')
  }

  // 顶部返回栏（对照 iOS navigationTitle「第一人称日记」）。
  @Builder
  navBar() {
    Row({ space: 12 }) {
      Text('‹ 返回')
        .fontSize(BubuFont.body)
        .fontColor(this.theme)
        .onClick(() => { this.onBack(); })
      Text('第一人称日记')
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      Blank()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  @Builder
  intro() {
    Row({ space: 12 }) {
      BubuMascotBadge({ badgeSize: 54, expression: BubuExpression.love })
      Column({ space: 5 }) {
        Text('让布布亲口讲这一刻')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text('选一条你写的记录，布布会像聊天一样，把它变成自己的小日记。')
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.secondaryText)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#D6FFFFFF')
    .borderRadius(BubuRadius.card)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
  }

  @Builder
  entryPicker() {
    if (this.candidates().length === 0) {
      // 对照 iOS ContentUnavailableView。
      Column({ space: 12 }) {
        Text('📕').fontSize(56)
        Text('还没有可改写的记录')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text('先在「记录此刻」写下一句父母视角的话吧。')
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.secondaryText)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height(240)
      .justifyContent(FlexAlign.Center)
    } else {
      Column({ space: 10 }) {
        Text('选择一条记录')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
          .width('100%')
        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.candidates().slice(0, 12), (entry: Entry) => {
              this.entryChip(entry)
            }, (entry: Entry) => entry.id)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  entryChip(entry: Entry) {
    Row({ space: 10 }) {
      this.entryAvatar(entry, 42)
      Column({ space: 6 }) {
        Text(BubuDateFormat.shortDate(new Date(entry.happenedAt)))
          .fontSize(11)
          .fontColor(BubuColor.secondaryText)
        Text(entry.note ?? '')
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.warmBrown)
          .maxLines(3)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width(190)
    .height(96)
    .padding(10)
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.small)
    .border({ width: 2, color: this.selectedId === entry.id ? this.theme : 'transparent' })
    .onClick(() => {
      this.selectedId = entry.id;
      this.output = '';
      this.displayed = '';
      this.errorText = '';
    })
  }

  // 记录头像：有照片用缩略图（圆形），否则用布布表情徽（对照 iOS entryAvatar）。
  @Builder
  entryAvatar(entry: Entry, size: number) {
    if (this.photoByEntry.has(entry.id)) {
      Stack() {
        MediaThumbnail({ media: this.photoByEntry.get(entry.id), cornerRadius: size / 2 })
      }
      .width(size)
      .height(size)
      .borderRadius(size / 2)
      .clip(true)
      .border({ width: 2, color: '#FFFFFF' })
    } else {
      BubuMascotBadge({ badgeSize: size })
    }
  }

  @Builder
  generateArea() {
    Column({ space: 16 }) {
      // 生成按钮（对照 iOS「让布布说出来」/「布布正在想……」）。
      Row({ space: 8 }) {
        if (this.generating) {
          LoadingProgress().width(22).height(22).color('#FFFFFF')
        } else {
          Text('🪄').fontSize(18)
        }
        Text(this.generating ? '布布正在想……' : '让布布说出来')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height(54)
      .backgroundColor(this.theme)
      .borderRadius(27)
      .opacity(this.generating ? 0.7 : 1.0)
      .onClick(() => { if (!this.generating) { this.generate(); } })

      if (this.generating && this.displayed.length === 0) {
        this.thinkingBubble()
      }

      if (this.errorText.length > 0) {
        Row({ space: 10 }) {
          BubuMascotBadge({ badgeSize: 44, expression: BubuExpression.shy })
          Text(this.errorText)
            .fontSize(BubuFont.caption)
            .fontColor(BubuColor.secondaryText)
            .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Top)
        .width('100%')
        .padding(16)
        .backgroundColor(BubuColor.card)
        .borderRadius(BubuRadius.small)
      }

      if (this.displayed.length > 0 && this.selectedEntry() !== undefined) {
        this.bubuMessage(this.selectedEntry()!)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  thinkingBubble() {
    Row({ space: 10 }) {
      BubuMascotBadge({ badgeSize: 52, expression: BubuExpression.thinking })
      Text('我在想，怎么把这一天讲给未来的自己听……')
        .fontSize(BubuFont.body)
        .fontColor(BubuColor.secondaryText)
        .padding(16)
        .backgroundColor(BubuColor.card)
        .borderRadius(22)
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
  }

  // 布布说出来的消息气泡（对照 iOS bubuMessage）。
  @Builder
  bubuMessage(entry: Entry) {
    Row({ space: 10 }) {
      this.entryAvatar(entry, 54)
      Column({ space: 8 }) {
        Text('布布说')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme)
        Text(this.displayed)
          .fontSize(18)
          .fontColor(BubuColor.warmBrown)
          .lineHeight(24)

        if (this.displayed === this.output && this.output.length > 0) {
          Text('⤓ 保存到这条记录')
            .fontSize(BubuFont.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.theme)
            .margin({ top: 4 })
            .onClick(() => { this.saveBack(); })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding(16)
      .backgroundColor('#1AF28C9E')
      .borderRadius(24)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
  }

  // 调 AI 改写并打字机展示（对照 iOS generate + typewriter）。
  private async generate(): Promise<void> {
    const entry = this.selectedEntry();
    if (entry === undefined) return;
    this.generating = true;
    this.displayed = '';
    this.errorText = '';
    const note = entry.note ?? '';
    try {
      const text = await AIService.shared.rewriteFirstPerson(note, ServerConfig.shared.childName);
      this.output = text;
      await this.typewriter(text);
    } catch (e) {
      this.output = '';
      this.errorText = 'AI 暂时没想好，稍后再试一次。';
    } finally {
      this.generating = false;
    }
  }

  // 打字机动效逐字显示（对照 iOS typewriter，18ms/字）。
  private async typewriter(text: string): Promise<void> {
    this.displayed = '';
    const chars = Array.from(text);
    for (const ch of chars) {
      this.displayed += ch;
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 18));
    }
  }

  // 保存第一人称改写回 Entry（对照 iOS saveBack）。
  private async saveBack(): Promise<void> {
    const entry = this.selectedEntry();
    if (entry === undefined) return;
    await AppDatabase.shared.updateEntryFields(entry.id, {
      firstPersonNote: this.output,
      editedAt: Date.now(),
      syncState: SyncState.local
    });
    promptAction.showToast({ message: '已保存到这条记录' });
  }
}
