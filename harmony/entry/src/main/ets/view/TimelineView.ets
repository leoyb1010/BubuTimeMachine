import { Entry, ChildProfile, Media, FeedEvent } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { MediaStore } from '../services/MediaStore';
import { ServerConfig } from '../services/ServerConfig';
import { AgeCalculator } from '../models/AgeCalculator';
import { Mood, moodEmoji, FeedEventKind, SyncState } from '../models/Enums';
import { BubuColor, BubuRadius } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { EntryDetailView } from './EntryDetailView';
import { FamilyFeedView } from './FamilyFeedView';
import { promptAction } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';

// MARK: - 时光轴（对照 iOS Features/Timeline/TimelineView.swift）
// 按 happenedAt 倒序读取本地 Entry，按「年-月」分段展示；离线优先，只读本地数据库。
// 左侧 hue 圆点 + 竖向虚线，右侧大图卡片；section 头展示月份 + 当时布布年龄。
// 顶部「家庭动态」入口；搜索；删除（软删除 + 写 entryArchived FeedEvent）。

// 一个月份分段（对照 iOS TimelineSection）。
interface TimelineSection {
  key: string;       // "2026年6月"
  entries: Entry[];
}

@Component
export struct TimelineView {
  @State entries: Entry[] = [];
  @State profile: ChildProfile | null = null;
  // entryId → 首张照片沙盒绝对 file:// 路径（卡片大图占位）。
  @State photoMap: Map<string, string> = new Map();
  // entryId → 首张媒体 mood emoji 占位用（无图时）。
  @State sections: TimelineSection[] = [];
  @State searchText: string = '';

  @State showFamilyFeed: boolean = false;
  @State detailEntry: Entry | null = null;

  aboutToAppear(): void { this.reload(); }

  private theme(): string { return BubuColor.primary; }

  private async reload(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    const entries = await AppDatabase.shared.fetchEntries(false);
    this.entries = entries;
    const map = new Map<string, string>();
    for (const e of entries) {
      const media = await AppDatabase.shared.fetchMediaForEntry(e.id);
      const photo = media.find((m: Media) => m.typeRaw === 'photo' && m.localFileName !== undefined && m.localFileName.length > 0);
      if (photo && photo.localFileName) {
        map.set(e.id, 'file://' + MediaStore.shared.fullPath(photo.localFileName));
      }
    }
    this.photoMap = map;
    this.rebuildSections();
  }

  // MARK: 分段（对照 iOS rebuildSections）：按年月分组，section 内按时间倒序。
  private rebuildSections(): void {
    const filtered = this.matchingEntries();
    const groupKeys: string[] = [];
    const groups: Map<string, Entry[]> = new Map();
    for (const e of filtered) {
      const d = new Date(e.happenedAt);
      const key = `${d.getFullYear()}年${d.getMonth() + 1}月`;
      if (!groups.has(key)) { groups.set(key, []); groupKeys.push(key); }
      groups.get(key)!.push(e);
    }
    // entries 已按 happenedAt 倒序，遇见顺序即时间倒序；section 间也按首条时间倒序。
    const out: TimelineSection[] = groupKeys.map((key: string) => {
      const section: TimelineSection = { key: key, entries: groups.get(key)! };
      return section;
    });
    out.sort((a: TimelineSection, b: TimelineSection) => {
      const at = a.entries.length > 0 ? a.entries[0].happenedAt : 0;
      const bt = b.entries.length > 0 ? b.entries[0].happenedAt : 0;
      return bt - at;
    });
    this.sections = out;
  }

  // MARK: 搜索命中（对照 iOS matchingEntries）：正文 / 第一人称 / 标题 / 地点 / 作者 / 心情。
  private matchingEntries(): Entry[] {
    const q = this.searchText.trim().toLowerCase();
    if (q.length === 0) return this.entries;
    return this.entries.filter((e: Entry) => {
      return this.hit(e.note, q) || this.hit(e.firstPersonNote, q) || this.hit(e.title, q)
        || this.hit(e.locationName, q) || this.hit(e.authorRole, q) || this.hit(e.moodRaw, q);
    });
  }

  private hit(s: string | undefined, q: string): boolean {
    return s !== undefined && s.toLowerCase().includes(q);
  }

  build() {
    if (this.detailEntry) {
      this.detailPanel()
    } else if (this.showFamilyFeed) {
      FamilyFeedView({ onClose: () => { this.showFamilyFeed = false; this.reload(); } })
    } else {
      this.mainPage()
    }
  }

  // 详情面板（对照 iOS navigationDestination → EntryDetailView）。保留与 HomeView 一致的 prop 契约。
  @Builder
  detailPanel() {
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
  }

  @Builder
  mainPage() {
    Column() {
      // 顶栏：标题 + 家庭动态入口（对照 iOS navigationTitle + toolbar）。
      Row() {
        Text('时光轴')
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Blank()
        Row({ space: 4 }) {
          Text('👨‍👩‍👧').fontSize(16)
          Text('家庭动态').fontSize(15).fontColor(this.theme())
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor('#1AF28C9E')
        .borderRadius(100)
        .onClick(() => { this.showFamilyFeed = true; })
      }
      .width('100%').padding({ left: 16, right: 16, top: 16, bottom: 8 })

      // 搜索框（对照 iOS .searchable）。
      Search({ value: this.searchText, placeholder: '找找布布的记录' })
        .width('100%')
        .margin({ left: 16, right: 16, bottom: 8 })
        .onChange((v: string) => { this.searchText = v; this.rebuildSections(); })

      if (this.entries.length === 0) {
        this.emptyState()
      } else if (this.sections.length === 0) {
        this.searchEmptyState()
      } else {
        this.timeline()
      }
    }
    .width('100%').height('100%').backgroundColor(BubuColor.background)
  }

  // MARK: 时光轴主体（List + ListItemGroup 分段，section 头吸顶）
  @Builder
  timeline() {
    List({ space: 16 }) {
      ForEach(this.sections, (section: TimelineSection) => {
        ListItemGroup({ header: this.sectionHeader(section) }) {
          ForEach(section.entries, (entry: Entry) => {
            ListItem() {
              this.timelineRow(entry)
            }
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 })))
          }, (entry: Entry) => entry.id)
        }
      }, (section: TimelineSection) => section.key)
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ left: 16, right: 16 })
    .sticky(StickyStyle.Header)
    .scrollBar(BarState.Off)
  }

  // MARK: 单条：左 hue 圆点 + 右大图卡片（对照 iOS timelineRow）
  @Builder
  timelineRow(entry: Entry) {
    Row({ space: 14 }) {
      // hue 圆点（对照 iOS Circle().fill(hue(...)) + 白描边 + 阴影）。
      Stack() {
        Circle()
          .width(14).height(14)
          .fill(BubuColor.hue(this.entryHue(entry), 0.78))
      }
      .width(20).height(20)
      .borderRadius(10)
      .border({ width: 3, color: Color.White })
      .backgroundColor(BubuColor.hue(this.entryHue(entry), 0.78))
      .shadow({ radius: 3, color: '#2E000000', offsetY: 1 })
      .margin({ top: 16 })

      Column() {
        this.bigPhotoCard(entry)
      }
      .layoutWeight(1)
      .onClick(() => { this.detailEntry = entry; })
      .gesture(
        LongPressGesture().onAction(() => { this.confirmDelete(entry); })
      )
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  // MARK: 大图卡片（对照 iOS bigPhotoCard）：顶部图/占位 + 日期标 + 标题 + 备注 + tag 行
  @Builder
  bigPhotoCard(entry: Entry) {
    Column() {
      // 顶部图（132 高）+ 左下日期标。
      Stack() {
        if (this.photoMap.has(entry.id)) {
          Image(this.photoMap.get(entry.id))
            .width('100%').height(132).objectFit(ImageFit.Cover)
        } else {
          // 无图占位：hue 渐变 + 心情/默认 motif（对照 iOS BubuDreamPhoto）。
          Stack() {
            Text(entry.moodRaw ? moodEmoji(entry.moodRaw as Mood) : '◡')
              .fontSize(40)
          }
          .alignContent(Alignment.Center)
          .width('100%').height(132)
          .linearGradient({
            angle: 135,
            colors: [
              [BubuColor.hue(this.entryHue(entry), 0.90), 0.0],
              [BubuColor.hue((this.entryHue(entry) + 40) % 360, 0.86), 1.0]
            ]
          })
        }

        Text(`${BubuDateFormat.monthDay(new Date(entry.happenedAt))} · ${BubuDateFormat.shortTime(new Date(entry.happenedAt))}`)
          .fontSize(12).fontWeight(FontWeight.Medium).fontColor(Color.White)
          .shadow({ radius: 3, color: '#4D000000', offsetY: 1 })
          .padding({ left: 14, right: 14, bottom: 10 })
      }
      .alignContent(Alignment.BottomStart)
      .width('100%').height(132).clip(true)

      // 标题 + 备注 + tag 行。
      Column({ space: 4 }) {
        Text(this.cardTitle(entry))
          .fontSize(15.5).fontWeight(FontWeight.Bolder).fontColor(BubuColor.warmBrown)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (entry.note && entry.note.length > 0) {
          Text(entry.note)
            .fontSize(12.5).fontColor(BubuColor.secondaryText)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        Row({ space: 6 }) {
          if (entry.moodRaw) {
            this.bubuTag(`${moodEmoji(entry.moodRaw as Mood)} ${entry.moodRaw}`, '#1AF28C9E', this.theme())
          }
          Blank()
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .width('100%')
    }
    .width('100%')
    .backgroundColor(BubuColor.card)
    .borderRadius(24)
    .clip(true)
    .shadow({ radius: 14, color: '#33B57870', offsetY: 8 })
  }

  // 月份 + 当时年龄锚点（对照 iOS sectionHeader）。
  @Builder
  sectionHeader(section: TimelineSection) {
    Row({ space: 8 }) {
      Text(section.key)
        .fontSize(21).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      if (this.profile && section.entries.length > 0) {
        Text(`布布 ${AgeCalculator.compactAge(this.profile!.birthday, section.entries[0].happenedAt)}`)
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.theme())
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .backgroundColor('#1AF28C9E')
          .borderRadius(100)
      }
      Blank()
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .backgroundColor(BubuColor.background)
  }

  @Builder
  bubuTag(text: string, bg: string, fg: string) {
    Text(text)
      .fontSize(12).fontColor(fg)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(bg)
      .borderRadius(100)
  }

  @Builder
  emptyState() {
    Column({ space: 18 }) {
      Text('🐣').fontSize(78)
      Text('还没有记录呢\n点上面的「记录此刻」，留住布布的第一个瞬间吧')
        .fontSize(18).fontColor(BubuColor.secondaryText)
        .textAlign(TextAlign.Center)
    }
    .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding(40)
  }

  @Builder
  searchEmptyState() {
    Column({ space: 16 }) {
      Text('😮').fontSize(72)
      Text(`没找到「${this.searchText}」相关的记录`)
        .fontSize(18).fontColor(BubuColor.secondaryText)
        .textAlign(TextAlign.Center)
    }
    .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding(40)
  }

  private cardTitle(entry: Entry): string {
    if (entry.title && entry.title.length > 0) return entry.title;
    if (entry.note && entry.note.length > 0) return entry.note;
    return '记录此刻';
  }

  // 由 entry.id 派生稳定 hue（对照 iOS abs(id.hashValue) % 360）。
  private entryHue(entry: Entry): number {
    let hash = 0;
    for (let i = 0; i < entry.id.length; i++) {
      hash = (hash * 31 + entry.id.charCodeAt(i)) | 0;
    }
    return Math.abs(hash) % 360;
  }

  // 删除确认（对照 iOS alert「删除这条记录？」+ deletePendingEntry）。
  private confirmDelete(entry: Entry): void {
    promptAction.showDialog({
      title: '删除这条记录？',
      message: '删除后会从时光轴隐藏，本地记录会标记为待同步删除。',
      buttons: [
        { text: '取消', color: BubuColor.secondaryText },
        { text: '删除', color: '#DB3B47' }
      ]
    }).then(async (res) => {
      if (res.index === 1) {
        await this.deleteEntry(entry);
      }
    });
  }

  // 软删除 + 写 entryArchived FeedEvent（对照 iOS deletePendingEntry）。
  private async deleteEntry(entry: Entry): Promise<void> {
    await AppDatabase.shared.archiveEntry(entry.id);
    const now = Date.now();
    const event: FeedEvent = {
      id: util.generateRandomUUID(true),
      kind: FeedEventKind.entryArchived,
      actorRole: ServerConfig.shared.currentRole,
      summary: '删除了一条时光轴记录',
      targetLocalId: entry.id,
      happenedAt: now,
      syncState: SyncState.synced,
      createdAt: now
    };
    await AppDatabase.shared.insertFeedEvent(event);
    promptAction.showToast({ message: '已删除' });
    this.reload();
  }
}
