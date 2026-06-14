import { Entry, Media, Comment } from '../models/Models';
import { Mood, moodEmoji, SyncState, syncStateFriendlyText } from '../models/Enums';
import { BubuColor, BubuRadius } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { MediaThumbnail } from '../components/MediaThumbnail';
import { ReactionRow, ReactionSummary, ReactionUtil } from './Reaction';

// MARK: - 时光轴卡片（对照 iOS Features/Timeline/TimelineEntryCard.swift）
// 一条 Entry 的卡片：媒体缩略图网格 + 日期 + 备注摘要 + 同步状态 + 反应/评论/语音角标。
// iOS 直接读 entry.media / entry.comments / entry.voiceNotes（SwiftData 关系）；
// ArkUI 关系存于独立表，由父级查好后以 @Prop 传入（media / comments / voiceCount）。
@Component
export struct TimelineEntryCard {
  @Require @Prop entry: Entry;
  @Prop media: Media[] = [];
  @Prop comments: Comment[] = [];
  @Prop voiceCount: number = 0;

  build() {
    Column({ space: 12 }) {
      this.header()

      if (this.media.length > 0) {
        this.mediaGrid()
      } else {
        this.noteOnlyMascot()
      }

      if (this.entry.note && this.entry.note.length > 0) {
        Text(this.entry.note)
          .fontSize(18).fontColor(BubuColor.warmBrown)
          .width('100%')
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      this.footer()
    }
    .padding(16)
    .width('100%')
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.card)
    .shadow({ radius: 14, color: '#33B57870', offsetY: 8 })
  }

  // MARK: 头部（心情 + 日期 + 作者 + 地点）
  @Builder
  header() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        if (this.entry.moodRaw) {
          Text(moodEmoji(this.entry.moodRaw as Mood)).fontSize(18)
        }
        Text(BubuDateFormat.shortDateTime(new Date(this.entry.happenedAt)))
          .fontSize(15).fontColor(BubuColor.secondaryText)
          .maxLines(1).layoutWeight(1)
        Text(this.entry.authorRole)
          .fontSize(15).fontColor(BubuColor.primary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor('#1FF28C9E')
          .borderRadius(100)
      }
      .width('100%')

      if (this.entry.locationName) {
        Row({ space: 4 }) {
          Text('📍').fontSize(12)
          Text(this.entry.locationName)
            .fontSize(12).fontColor(BubuColor.secondaryText).maxLines(1)
        }
      }
    }
  }

  // MARK: 媒体网格（对照 iOS mediaGrid：1 张占位大图；2 张两列；其余三列，最多 9）
  @Builder
  mediaGrid() {
    if (this.media.length === 1) {
      MediaThumbnail({ media: this.media[0] })
        .width(156).height(156)
    } else {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.gridMedia(), (m: Media) => {
          MediaThumbnail({ media: m })
            .width(this.cellPercent())
            .aspectRatio(1)
            .padding(3)
        }, (m: Media) => m.id)
      }
      .width('100%')
    }
  }

  // MARK: 仅文字时的吉祥物占位（对照 iOS noteOnlyMascot）
  @Builder
  noteOnlyMascot() {
    Row({ space: 10 }) {
      Text(this.entry.moodRaw ? moodEmoji(this.entry.moodRaw as Mood) : '🐣').fontSize(40)
      Text('这一刻先用文字和声音收好了')
        .fontSize(15).fontColor(BubuColor.secondaryText)
      Blank()
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#B8FFF7F1')
    .borderRadius(BubuRadius.small)
  }

  // MARK: 行尾（同步状态 + 反应 + 语音/评论计数，对照 iOS footer）
  @Builder
  footer() {
    Row({ space: 12 }) {
      Row({ space: 6 }) {
        Text(this.syncSymbol()).fontSize(11)
        Text(syncStateFriendlyText(this.entry.syncState as SyncState)).fontSize(15)
      }
      ReactionRow({ summary: ReactionSummary.from(this.comments, '') })
      Blank()
      if (this.voiceCount > 0) {
        Row({ space: 3 }) {
          Text('〰').fontSize(12)
          Text(`${this.voiceCount}`).fontSize(12)
        }
      }
      if (this.realCommentCount() > 0) {
        Row({ space: 3 }) {
          Text('👪').fontSize(12)
          Text(`${this.realCommentCount()}`).fontSize(12)
        }
      }
    }
    .width('100%')
    .opacity(0.85)
  }

  private gridMedia(): Media[] {
    return this.media.slice(0, 9);
  }

  // 2 张时两列 50%；其余三列约 33%（对照 iOS columns count == 2 ? 2 : 3）。
  private cellPercent(): string {
    return this.media.length === 2 ? '50%' : '33.33%';
  }

  private realCommentCount(): number {
    return this.comments.filter((c: Comment) => !ReactionUtil.isReaction(c)).length;
  }

  // 对照 iOS syncSymbol（SF Symbol → emoji 近似）。
  private syncSymbol(): string {
    switch (this.entry.syncState as SyncState) {
      case SyncState.local: return '📱';
      case SyncState.uploading: return '⬆️';
      case SyncState.synced: return '☁️';
      case SyncState.failed: return '⚠️';
      default: return '📱';
    }
  }
}
