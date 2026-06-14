import { Entry, FeedEvent } from '../models/Models';
import { FeedEventKind, feedEventTitle, feedEventEmoji } from '../models/Enums';
import { AppDatabase } from '../data/AppDatabase';
import { BubuColor, BubuRadius } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { EntryDetailView } from './EntryDetailView';

// MARK: - 家庭动态墙（对照 iOS Features/Feed/FamilyFeedView.swift）
// 汇集「谁记录了新瞬间 / 谁补充了评论 / 谁点亮了里程碑」。
// 派生事件：每条未归档 Entry 合成一条 entryCreated，与库里的 FeedEvent 合并按时间倒序。
// iOS 用 navigationDestination(for: Entry.self) → 这里用内部 @State 切换详情面板（对照 TimelineView 模式）。

// 过滤 chip 的可枚举类型（全部 + 各 kind）。
const ALL_FEED_KINDS: FeedEventKind[] = [
  FeedEventKind.entryCreated, FeedEventKind.entryArchived, FeedEventKind.commentAdded,
  FeedEventKind.voiceAdded, FeedEventKind.milestoneLit, FeedEventKind.healthRecorded,
  FeedEventKind.firstTimeConfirmed
];

@Component
export struct FamilyFeedView {
  // 关闭家庭动态墙（对照 iOS sheet dismiss）。
  onClose?: () => void;

  @State private events: FeedEvent[] = [];
  @State private entries: Entry[] = [];
  @State private selectedKind: FeedEventKind | null = null;
  @State private detailEntry: Entry | null = null;

  aboutToAppear(): void { this.reload(); }

  private theme(): string { return BubuColor.primary; }

  private async reload(): Promise<void> {
    this.events = await AppDatabase.shared.fetchFeedEvents(100);
    this.entries = await AppDatabase.shared.fetchEntries(false);
  }

  // 派生事件（对照 iOS derivedEvents）：库内 FeedEvent + 每条 Entry 合成的 entryCreated，按时间倒序。
  private derivedEvents(): FeedEvent[] {
    const entryEvents: FeedEvent[] = this.entries.map((entry: Entry) => {
      const summary = (entry.note && entry.note.length > 0)
        ? `记录了：${entry.note}`
        : '记录了布布的一个新瞬间';
      const ev: FeedEvent = {
        id: 'derived_' + entry.id,
        kind: FeedEventKind.entryCreated,
        actorRole: entry.authorRole,
        summary: summary,
        targetLocalId: entry.id,
        happenedAt: entry.happenedAt,
        syncState: entry.syncState,
        createdAt: entry.happenedAt
      };
      return ev;
    });
    const merged = this.events.concat(entryEvents);
    return merged.sort((a: FeedEvent, b: FeedEvent) => b.happenedAt - a.happenedAt);
  }

  private filteredEvents(): FeedEvent[] {
    const all = this.derivedEvents();
    if (this.selectedKind === null) return all;
    return all.filter((e: FeedEvent) => e.kind === this.selectedKind);
  }

  // 找事件对应的 Entry（仅 entryCreated 可点开，对照 iOS entry(for:)）。
  private entryFor(event: FeedEvent): Entry | null {
    if (event.kind !== FeedEventKind.entryCreated || !event.targetLocalId) return null;
    return this.entries.find((e: Entry) => e.id === event.targetLocalId) ?? null;
  }

  build() {
    if (this.detailEntry) {
      Column() {
        Row({ space: 12 }) {
          Button('返回')
            .backgroundColor('#F3F3F3').fontColor(BubuColor.warmBrown)
            .onClick(() => { this.detailEntry = null; this.reload(); })
          Text('记录详情').fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
          Blank()
        }
        .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })
        EntryDetailView({
          entry: this.detailEntry!,
          onDismiss: () => { this.detailEntry = null; this.reload(); }
        })
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.background)
    } else {
      this.feedPage()
    }
  }

  @Builder
  feedPage() {
    Column() {
      // 顶栏（对照 iOS navigationTitle「家庭动态」）。
      Row({ space: 12 }) {
        if (this.onClose) {
          Button('关闭')
            .backgroundColor('#F3F3F3').fontColor(BubuColor.warmBrown)
            .onClick(() => { if (this.onClose) this.onClose(); })
        }
        Text('家庭动态').fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Blank()
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 14 }) {
          this.headerCard()
          this.filters()
          ForEach(this.filteredEvents(), (event: FeedEvent) => {
            this.eventRow(event)
          }, (event: FeedEvent) => event.id)
          if (this.filteredEvents().length === 0) {
            this.emptyState()
          }
        }
        .padding(16)
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%').backgroundColor(BubuColor.background)
  }

  // MARK: 头部卡片（对照 iOS header）
  @Builder
  headerCard() {
    Column({ space: 6 }) {
      Text('布布的家庭动态墙')
        .fontSize(26).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Text('谁记录了新瞬间、谁补充了评论、谁点亮了里程碑，都会汇到这里。')
        .fontSize(15).fontColor(BubuColor.secondaryText)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.card)
    .shadow({ radius: 14, color: '#33B57870', offsetY: 8 })
  }

  // MARK: 过滤 chip 横滑（对照 iOS filters）
  @Builder
  filters() {
    Scroll() {
      Row({ space: 8 }) {
        this.filterChip('全部', this.selectedKind === null, () => { this.selectedKind = null; })
        ForEach(ALL_FEED_KINDS, (kind: FeedEventKind) => {
          this.filterChip(feedEventTitle(kind), this.selectedKind === kind, () => { this.selectedKind = kind; })
        }, (kind: FeedEventKind) => kind)
      }
      .padding({ top: 2, bottom: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .align(Alignment.Start)
  }

  @Builder
  filterChip(text: string, selected: boolean, action: () => void) {
    Text(text)
      .fontSize(15).fontWeight(FontWeight.Medium)
      .fontColor(selected ? Color.White : this.theme())
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor(selected ? this.theme() : '#1AF28C9E')
      .borderRadius(100)
      .onClick(() => { action(); })
  }

  // MARK: 单条动态（对照 iOS eventRow）
  @Builder
  eventRow(event: FeedEvent) {
    Row({ space: 12 }) {
      Text(feedEventEmoji(event.kind as FeedEventKind))
        .fontSize(22).textAlign(TextAlign.Center)
        .width(44).height(44)
        .backgroundColor(this.theme())
        .borderRadius(22)
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          Text(event.actorRole.length === 0 ? '家人' : event.actorRole)
            .fontSize(18).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
          Text(feedEventTitle(event.kind as FeedEventKind))
            .fontSize(15).fontColor(this.theme())
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor('#1AF28C9E')
            .borderRadius(100)
        }
        Text(event.summary)
          .fontSize(18).fontColor(BubuColor.warmBrown)
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(BubuDateFormat.shortDateTime(new Date(event.happenedAt)))
          .fontSize(15).fontColor(BubuColor.secondaryText)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding(16)
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.card)
    .onClick(() => {
      const e = this.entryFor(event);
      if (e) this.detailEntry = e;
    })
  }

  @Builder
  emptyState() {
    Text('还没有家庭动态。发一条记录后，这里就会热闹起来。')
      .fontSize(18).fontColor(BubuColor.secondaryText)
      .width('100%').textAlign(TextAlign.Center)
      .padding({ top: 60, bottom: 60 })
  }
}
