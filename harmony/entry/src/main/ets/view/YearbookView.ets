// MARK: - PDF 年册导出（对照 iOS Features/Settings/YearbookView.swift）
// 选一个年龄段（如「1 岁这一年」），生成 A4 竖版年册并分享。
// iOS 用 ImageRenderer→PDF；HarmonyOS 用 YearbookExporter 逐页绘 PNG 到 cacheDir 目录（见该服务 NOTE）。

import { AppDatabase } from '../data/AppDatabase';
import { Entry, Media, Milestone, ChildProfile, Comment } from '../models/Models';
import { MediaType, Mood, moodEmoji } from '../models/Enums';
import { AgeCalculator } from '../models/AgeCalculator';
import { YearbookExporter, YearbookInput, YearbookPage } from '../services/media/YearbookExporter';
import { ThemeManager } from '../theme/ThemeManager';
import { BubuColor, BubuFont, BubuRadius, BubuSpacing } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';

@Component
export struct YearbookView {
  onClose?: () => void;

  @State private profile: ChildProfile | null = null;
  @State private entries: Entry[] = [];           // 未归档，按 happenedAt 升序
  @State private milestones: Milestone[] = [];
  @State private mediaByEntry: Map<string, Media[]> = new Map();
  @State private commentsByEntry: Map<string, Comment[]> = new Map();

  @State private selectedYear: number = 0;
  @State private generating: boolean = false;
  @State private resultPath: string = '';
  @State private errorText: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    const db = AppDatabase.shared;
    this.profile = await db.fetchChildProfile();
    const all = (await db.fetchEntries(false)) ?? [];
    // 升序（对照 iOS sort: \Entry.happenedAt）。
    this.entries = all.slice().sort((a: Entry, b: Entry): number => a.happenedAt - b.happenedAt);
    this.milestones = (await db.fetchMilestones()) ?? [];
    for (const e of this.entries) {
      this.mediaByEntry.set(e.id, (await db.fetchMediaForEntry(e.id)) ?? []);
      this.commentsByEntry.set(e.id, (await db.fetchCommentsForEntry(e.id)) ?? []);
    }
  }

  // 可选年龄段：0 岁到当前年龄。
  private availableYears(): number[] {
    const p = this.profile;
    if (!p) return [0];
    const age = AgeCalculator.ageYears(p.birthday);
    const out: number[] = [];
    for (let y = 0; y <= Math.max(age, 0); y++) out.push(y);
    return out;
  }

  private yearLabel(year: number): string {
    return year === 0 ? '0–1 岁' : `${year} 岁这一年`;
  }

  // 该年龄段的年初/年末（按生日推 N 岁、N+1 岁）。
  private rangeStart(): number {
    const p = this.profile;
    if (!p) return 0;
    const d = new Date(p.birthday);
    return new Date(d.getFullYear() + this.selectedYear, d.getMonth(), d.getDate()).getTime();
  }

  private rangeEnd(): number {
    const p = this.profile;
    if (!p) return Date.now();
    const d = new Date(p.birthday);
    return new Date(d.getFullYear() + this.selectedYear + 1, d.getMonth(), d.getDate()).getTime();
  }

  private entriesInRange(): Entry[] {
    const start = this.rangeStart();
    const end = this.rangeEnd();
    return this.entries.filter((e: Entry) => e.happenedAt >= start && e.happenedAt < end);
  }

  private photosInRange(): number {
    let n = 0;
    for (const e of this.entriesInRange()) {
      n += (this.mediaByEntry.get(e.id) ?? []).filter((m: Media) => m.typeRaw === MediaType.photo).length;
    }
    return n;
  }

  build() {
    Column() {
      if (this.onClose) {
        Row({ space: 12 }) {
          Button('返回')
            .backgroundColor('#F3F3F3').fontColor(BubuColor.warmBrown)
            .onClick(() => { this.onClose!(); })
          Text('PDF 年册').fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
          Blank()
        }
        .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })
      }

      Scroll() {
        Column({ space: BubuSpacing.section }) {
          // hero
          Column({ space: 12 }) {
            Text('📖').fontSize(52)
            Text('把布布的一年，做成一本书')
              .fontSize(BubuFont.title).fontWeight(FontWeight.Bold)
              .fontColor(BubuColor.warmBrown).textAlign(TextAlign.Center)
            Text('封面 + 每条记录的照片与文字 + 里程碑 + 家人寄语，A4 竖版。打印出来，就是 30 年后还能摸到的实体礼物。')
              .fontSize(BubuFont.caption).fontColor(BubuColor.secondaryText).textAlign(TextAlign.Center)
          }
          .width('100%')

          // 年龄段选择
          Column({ space: 10 }) {
            Text('选择年龄段').fontSize(BubuFont.headline).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown).width('100%')
            Scroll() {
              Row({ space: 10 }) {
                ForEach(this.availableYears(), (year: number) => {
                  Text(this.yearLabel(year))
                    .fontSize(BubuFont.body).fontWeight(FontWeight.Medium)
                    .fontColor(this.selectedYear === year ? Color.White : BubuColor.warmBrown)
                    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                    .backgroundColor(this.selectedYear === year ? BubuColor.primary : BubuColor.softFill)
                    .borderRadius(100)
                    .onClick(() => { this.selectedYear = year; })
                }, (year: number) => year.toString())
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .width('100%')
          }
          .width('100%')

          // 该年统计
          Row({ space: 12 }) {
            Text('📚').fontSize(44)
            Text(`这一年有 ${this.entriesInRange().length} 条记录、${this.photosInRange()} 张照片`)
              .fontSize(BubuFont.body).fontColor(BubuColor.warmBrown).layoutWeight(1)
          }
          .width('100%').padding(16)
          .backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
          .shadow({ radius: 14, color: '#33B57870', offsetY: 8 })

          // 生成按钮
          Button() {
            Row({ space: 8 }) {
              if (this.generating) { LoadingProgress().width(20).height(20).color(Color.White) }
              Text(this.generating ? '正在排版…' : '生成年册')
                .fontSize(BubuFont.headline).fontWeight(FontWeight.Bold).fontColor(Color.White)
            }
          }
          .width('100%').height(54).backgroundColor(BubuColor.primary).borderRadius(27)
          .enabled(!this.generating && this.profile !== null && this.entriesInRange().length > 0)
          .onClick(() => { this.generate(); })

          if (this.errorText.length > 0) {
            Text(this.errorText).fontSize(BubuFont.caption).fontColor(BubuColor.danger).width('100%')
          }
          if (this.resultPath.length > 0) {
            Text(`已生成到：\n${this.resultPath}`)
              .fontSize(BubuFont.caption).fontColor(BubuColor.success).width('100%').textAlign(TextAlign.Center)
          }
        }
        .padding(16).width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(BubuColor.background)
  }

  private async generate(): Promise<void> {
    const profile = this.profile;
    if (!profile) return;
    this.generating = true;
    this.errorText = '';
    this.resultPath = '';
    try {
      const inRange = this.entriesInRange();
      const pages: YearbookPage[] = inRange.map((e: Entry): YearbookPage => {
        const photos = (this.mediaByEntry.get(e.id) ?? [])
          .filter((m: Media) => m.typeRaw === MediaType.photo)
          .map((m: Media) => m.localFileName)
          .filter((n: string | undefined): boolean => n !== undefined && n !== null) as string[];
        const mood: string | undefined = e.moodRaw !== undefined && e.moodRaw !== null
          ? moodEmoji(e.moodRaw as Mood) : undefined;
        return {
          date: e.happenedAt,
          note: e.firstPersonNote ?? e.note,
          ageText: AgeCalculator.compactAge(profile.birthday, e.happenedAt),
          authorRole: e.authorRole,
          imageFileNames: photos,
          mood: mood
        };
      });

      const start = this.rangeStart();
      const end = this.rangeEnd();
      // 已点亮里程碑（happenedAt 非空且落在该年龄段内）。
      const yearMilestones: string[] = this.milestones
        .filter((m: Milestone) => m.happenedAt !== undefined && m.happenedAt !== null
          && (m.happenedAt as number) >= start && (m.happenedAt as number) < end)
        .map((m: Milestone) => m.title);

      // 家人寄语：取该年记录的文字评论。
      // NOTE: iOS 用 Reaction.isReaction 排除「反应」评论；ArkUI 暂无该工具，纳入全部文字评论。
      const messages: string[] = [];
      for (const e of inRange) {
        const comments = this.commentsByEntry.get(e.id) ?? [];
        for (const c of comments) {
          if (c.text !== undefined && c.text !== null && c.text.length > 0) {
            messages.push(`${c.authorRole}：${c.text}`);
          }
        }
      }

      // 封面图：档案首页背景 或 该年第一张照片。
      let cover: string | undefined = profile.heroBackgroundFileName;
      if (!cover) {
        for (const p of pages) {
          if (p.imageFileNames.length > 0) { cover = p.imageFileNames[0]; break; }
        }
      }

      const theme = ThemeManager.shared.theme;
      const input: YearbookInput = {
        childName: profile.name,
        rangeTitle: this.yearLabel(this.selectedYear),
        coverImageFileName: cover,
        entries: pages,
        milestones: yearMilestones,
        messages: messages.slice(0, 14),
        primaryColorHex: theme.primary,
        secondaryColorHex: theme.secondary
      };

      const dir = await YearbookExporter.shared.makePDF(input);
      if (dir) {
        this.resultPath = dir;
        promptAction.showToast({ message: '年册已生成 💛' });
      } else {
        this.errorText = '年册生成失败了，稍后再试试。';
      }
    } catch (e) {
      this.errorText = `年册生成失败：${e instanceof Error ? e.message : '稍后再试'}`;
    }
    this.generating = false;
  }
}
