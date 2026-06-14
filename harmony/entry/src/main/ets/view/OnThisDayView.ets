import { Entry, ChildProfile } from '../models/Models';
import { Mood, moodEmoji } from '../models/Enums';
import { AppDatabase } from '../data/AppDatabase';
import { MediaStore } from '../services/MediaStore';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor, BubuFont, BubuRadius, BubuShadow } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { BubuMascotBadge, BubuExpression } from '../components/BubuMascotBadge';

// MARK: - 那年今日 · 落地页（对照 iOS Features/Capture/OnThisDayView.swift）
// 按年份纵向排「2025 的今天 / 2024 的今天」，每年一张大卡（照片 + 当时年龄 + 当时记录原文）。
// 空年份显示「这一年的今天没有记录」，把怀旧转化为新记录。

interface YearRow {
  year: number;
  entries: Entry[];   // 该年同月同日的记录（可能为空）
}

@Component
export struct OnThisDayView {
  @State entries: Entry[] = [];
  @State profile: ChildProfile | null = null;
  // entryId → 首张照片沙盒绝对路径
  @State photoMap: Map<string, string> = new Map();
  // 选中某条记录回调（由父级 HomeView 路由到详情页）。
  onSelect?: (entry: Entry) => void;

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
      const photo = media.find(m => m.typeRaw === 'photo' && (m.localFileName !== undefined && m.localFileName.length > 0));
      if (photo && photo.localFileName) {
        map.set(e.id, 'file://' + MediaStore.shared.fullPath(photo.localFileName));
      }
    }
    this.photoMap = map;
  }

  // 同月同日（不含今天）。
  private isSameDay(a: number, b: number): boolean {
    const da = new Date(a);
    const db = new Date(b);
    return da.getFullYear() === db.getFullYear() && da.getMonth() === db.getMonth() && da.getDate() === db.getDate();
  }

  // 从布布出生那年的「今天」到今年，每年一行（含空年）。
  private yearRows(): YearRow[] {
    const now = new Date();
    const thisYear = now.getFullYear();
    let startYear = thisYear;
    if (this.profile) {
      startYear = new Date(this.profile!.birthday).getFullYear();
    } else if (this.entries.length > 0) {
      let earliest = this.entries[0].happenedAt;
      for (const e of this.entries) {
        if (e.happenedAt < earliest) {
          earliest = e.happenedAt;
        }
      }
      startYear = new Date(earliest).getFullYear();
    }

    // 同月同日且往年的记录，按年分组。
    const matched = this.entries.filter(e => {
      const d = new Date(e.happenedAt);
      return d.getMonth() === now.getMonth() && d.getDate() === now.getDate() && !this.isSameDay(e.happenedAt, Date.now());
    });
    const byYear = new Map<number, Entry[]>();
    for (const e of matched) {
      const y = new Date(e.happenedAt).getFullYear();
      const arr = byYear.get(y) ?? [];
      arr.push(e);
      byYear.set(y, arr);
    }

    const rows: YearRow[] = [];
    for (let year = thisYear - 1; year >= startYear; year--) {
      rows.push({ year, entries: byYear.get(year) ?? [] });
    }
    return rows;
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        this.header()
        ForEach(this.yearRows(), (row: YearRow) => {
          this.yearCard(row)
        }, (row: YearRow) => `${row.year}`)
      }
      .padding(16)
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BubuColor.cream)
  }

  @Builder
  header() {
    Column({ space: 6 }) {
      Text(BubuDateFormat.monthDay(new Date()) + ' 的回忆')
        .fontSize(BubuFont.title)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      Text('每一年的今天，布布都在长大')
        .fontSize(BubuFont.caption)
        .fontColor(BubuColor.secondaryText)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  yearCard(row: YearRow) {
    Column({ space: 10 }) {
      Row() {
        Text(`${row.year} 年的今天`)
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Blank()
        if (this.profile && row.entries.length > 0) {
          Text(AgeCalculator.compactAge(this.profile!.birthday, row.entries[0].happenedAt))
            .fontSize(BubuFont.caption)
            .fontColor(BubuColor.primary)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .backgroundColor('#1AF28C9E')
            .borderRadius(12)
        }
      }
      .width('100%')

      if (row.entries.length === 0) {
        this.emptyYear()
      } else {
        ForEach(row.entries, (entry: Entry) => {
          this.memoryRow(entry)
        }, (entry: Entry) => entry.id)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.card)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  memoryRow(entry: Entry) {
    Row({ space: 12 }) {
      if (this.photoMap.has(entry.id)) {
        Image(this.photoMap.get(entry.id))
          .width(96).height(96)
          .borderRadius(BubuRadius.small)
          .objectFit(ImageFit.Cover)
      } else {
        Text(moodEmoji(entry.moodRaw as Mood | undefined))
          .fontSize(36)
          .width(96).height(96)
          .textAlign(TextAlign.Center)
          .backgroundColor('#1FF28C9E')
          .borderRadius(BubuRadius.small)
      }
      Column({ space: 4 }) {
        if (entry.note !== undefined && entry.note.length > 0) {
          Text(entry.note)
            .fontSize(BubuFont.body)
            .fontColor(BubuColor.warmBrown)
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          Text('那天的布布')
            .fontSize(BubuFont.body)
            .fontColor(BubuColor.secondaryText)
        }
        Text(BubuDateFormat.shortDate(new Date(entry.happenedAt)))
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.secondaryText)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .onClick(() => { this.onSelect?.(entry); })
  }

  @Builder
  emptyYear() {
    Row({ space: 12 }) {
      BubuMascotBadge({ badgeSize: 44, expression: BubuExpression.bye })
      Text('这一年的今天没有记录')
        .fontSize(BubuFont.caption)
        .fontColor(BubuColor.secondaryText)
      Blank()
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }
}
