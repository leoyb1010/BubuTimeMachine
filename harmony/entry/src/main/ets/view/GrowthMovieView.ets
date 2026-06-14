import { Entry, Media, ChildProfile } from '../models/Models';
import { MediaType } from '../models/Enums';
import { AppDatabase } from '../data/AppDatabase';
import { AgeCalculator } from '../models/AgeCalculator';
import { AIService } from '../services/AIService';
import { ServerConfig } from '../services/ServerConfig';
import { BubuColor, BubuFont, BubuRadius, BubuShadow } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { BubuMascotBadge } from '../components/BubuMascotBadge';
import { BubuExpression } from '../theme/BubuExpression';
import { MediaThumbnail } from '../components/MediaThumbnail';
import { GrowthMoviePlayer, MovieDraft } from './GrowthMoviePlayer';

// MARK: - 年度成长电影（对照 iOS Features/AIStudio/GrowthMovieView.swift）
// 端侧生成「电影草稿」：按年龄/地点/时间筛选真实照片，套用模板播放（GrowthMoviePlayer）。

// 模板（对照 iOS MovieTemplate）。
interface MovieTemplateMeta { raw: string; title: string; subtitle: string; emoji: string; }
const MOVIE_TEMPLATES: MovieTemplateMeta[] = [
  { raw: 'documentary', title: '温柔纪录片', subtitle: '按时间慢慢讲', emoji: '🎬' },
  { raw: 'travel', title: '出门旅行', subtitle: '适合公园和外出', emoji: '🧳' },
  { raw: 'birthday', title: '生日回顾', subtitle: '更有仪式感', emoji: '🎂' },
  { raw: 'daily', title: '日常碎片', subtitle: '短节奏、多照片', emoji: '✨' }
];

// 时间范围（对照 iOS MovieTimeRange）。
interface MovieTimeRangeMeta { raw: string; title: string; }
const MOVIE_TIME_RANGES: MovieTimeRangeMeta[] = [
  { raw: 'all', title: '全部时间' },
  { raw: 'recent3Months', title: '最近3个月' },
  { raw: 'recentYear', title: '最近1年' }
];

// 一条记录连同其照片（HarmonyOS 需预取 media）。
interface EntryWithMedia { entry: Entry; photos: Media[]; }

@Component
export struct GrowthMovieView {
  onBack: () => void = () => {};

  @State private items: EntryWithMedia[] = [];
  @State private profile: ChildProfile | null = null;

  @State private selectedTemplate: string = 'documentary';
  // -1 表示「全部年龄」（对照 iOS selectedYear: Int?）。
  @State private selectedYear: number = -1;
  @State private selectedLocation: string = '';   // 空 = 全部地点
  @State private selectedRange: string = 'all';
  @State private stageIndex: number = -1;
  @State private draft: MovieDraft | null = null;
  @State private showPlayer: boolean = false;

  private theme: string = BubuColor.primary;
  private readonly stages: string[] = ['筛选照片素材…', '整理时间和地点…', '套用电影模板…', '生成片头和字幕…'];

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    const entries = await AppDatabase.shared.fetchEntries(false) ?? [];
    const out: EntryWithMedia[] = [];
    for (const e of entries) {
      const media = await AppDatabase.shared.fetchMediaForEntry(e.id);
      const photos = media.filter((m: Media): boolean =>
        m.typeRaw === MediaType.photo && m.localFileName !== undefined && m.localFileName.length > 0);
      out.push({ entry: e, photos: photos });
    }
    this.items = out;
  }

  build() {
    if (this.showPlayer && this.draft !== null) {
      GrowthMoviePlayer({
        draft: this.draft,
        tint: this.theme,
        onClose: (): void => { this.showPlayer = false; }
      })
    } else {
      this.editorPage()
    }
  }

  @Builder
  editorPage() {
    Column() {
      this.navBar()
      Scroll() {
        Column({ space: 18 }) {
          this.introCard()
          this.templatePicker()
          this.filterCard()
          this.materialPreview()
          if (this.stageIndex >= 0) { this.progressArea() }
          this.actionButtons()
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

  @Builder
  navBar() {
    Row({ space: 12 }) {
      Text('‹ 返回')
        .fontSize(BubuFont.body)
        .fontColor(this.theme)
        .onClick(() => { this.onBack(); })
      Text('年度成长电影')
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      Blank()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  @Builder
  introCard() {
    Row({ space: 14 }) {
      BubuMascotBadge({ badgeSize: 62, expression: BubuExpression.tv })
      Column({ space: 5 }) {
        Text(this.draft === null ? '做一支布布的小电影' : '电影草稿已准备好')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text(this.draft === null
          ? '先选模板，再按年龄、地点和时间挑照片。生成后可以预览播放，不会被旧记录背景干扰。'
          : '可以先播放看看，不满意就换模板或筛选条件重新生成。')
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.secondaryText)
          .maxLines(3)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.card)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
  }

  @Builder
  templatePicker() {
    Column({ space: 10 }) {
      Text('选择模板')
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
        .width('100%')
      Row({ space: 10 }) {
        this.templateTile(MOVIE_TEMPLATES[0])
        this.templateTile(MOVIE_TEMPLATES[1])
      }.width('100%')
      Row({ space: 10 }) {
        this.templateTile(MOVIE_TEMPLATES[2])
        this.templateTile(MOVIE_TEMPLATES[3])
      }.width('100%')
    }
    .width('100%')
  }

  @Builder
  templateTile(t: MovieTemplateMeta) {
    Column({ space: 6 }) {
      Text(t.emoji).fontSize(28)
      Text(t.title)
        .fontSize(BubuFont.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(BubuColor.warmBrown)
      Text(t.subtitle)
        .fontSize(12)
        .fontColor(BubuColor.secondaryText)
        .maxLines(2)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(12)
    .backgroundColor(this.selectedTemplate === t.raw ? '#24F28C9E' : BubuColor.card)
    .borderRadius(BubuRadius.small)
    .border({ width: 1.5, color: this.selectedTemplate === t.raw ? this.theme : '#73DBCCC2' })
    .onClick(() => { this.selectedTemplate = t.raw; this.draft = null; })
  }

  @Builder
  filterCard() {
    Column({ space: 14 }) {
      this.sectionTitle('筛选素材', '🎚️')
      // 年龄
      this.chipRowLabel('年龄')
      Scroll() {
        Row({ space: 8 }) {
          this.chip('全部年龄', this.selectedYear === -1, (): void => { this.selectedYear = -1; this.draft = null; })
          ForEach(this.availableYears(), (year: number) => {
            this.chip(year === 0 ? '0岁' : `${year}岁`, this.selectedYear === year,
              (): void => { this.selectedYear = year; this.draft = null; })
          }, (year: number) => `y${year}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
      // 地点
      this.chipRowLabel('地点')
      Scroll() {
        Row({ space: 8 }) {
          this.chip('全部地点', this.selectedLocation === '', (): void => { this.selectedLocation = ''; this.draft = null; })
          ForEach(this.availableLocations(), (loc: string) => {
            this.chip(loc, this.selectedLocation === loc,
              (): void => { this.selectedLocation = loc; this.draft = null; })
          }, (loc: string) => `l${loc}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
      // 时间
      this.chipRowLabel('时间')
      Scroll() {
        Row({ space: 8 }) {
          ForEach(MOVIE_TIME_RANGES, (r: MovieTimeRangeMeta) => {
            this.chip(r.title, this.selectedRange === r.raw,
              (): void => { this.selectedRange = r.raw; this.draft = null; })
          }, (r: MovieTimeRangeMeta) => r.raw)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.card)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
  }

  @Builder
  chipRowLabel(title: string) {
    Text(title)
      .fontSize(BubuFont.caption)
      .fontWeight(FontWeight.Medium)
      .fontColor(BubuColor.secondaryText)
      .width('100%')
  }

  // 单个筛选 chip（对照 iOS FilterChip）。
  @Builder
  chip(title: string, selected: boolean, onTap: () => void) {
    Text(title)
      .fontSize(BubuFont.caption)
      .fontWeight(FontWeight.Medium)
      .fontColor(selected ? '#FFFFFF' : BubuColor.warmBrown)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor(selected ? this.theme : BubuColor.softFill)
      .borderRadius(18)
      .onClick(() => { onTap(); })
  }

  @Builder
  materialPreview() {
    Column({ space: 12 }) {
      Row() {
        this.sectionTitle('将用于电影的素材', '🖼️')
        Blank()
        Text(`${this.selectedPhotoFiles().length} 张`)
          .fontSize(BubuFont.caption)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme)
      }
      .width('100%')

      if (this.selectedPreviewMedia().length === 0) {
        Row({ space: 12 }) {
          BubuMascotBadge({ badgeSize: 52, expression: BubuExpression.bye })
          Text('当前筛选下没有照片。可以换成全部年龄/全部地点，或先去时光轴补几张照片。')
            .fontSize(BubuFont.caption)
            .fontColor(BubuColor.secondaryText)
            .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Top)
        .width('100%')
      } else {
        // 3 列预览前 6 张（对照 iOS LazyVGrid prefix(6)）。
        Grid() {
          ForEach(this.selectedPreviewMedia().slice(0, 6), (m: Media) => {
            GridItem() {
              Stack() {
                MediaThumbnail({ media: m })
              }
              .width('100%')
              .height(86)
              .clip(true)
              .borderRadius(8)
            }
          }, (m: Media) => m.id)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .width('100%')
        .height(this.selectedPreviewMedia().length > 3 ? 180 : 86)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.card)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
  }

  @Builder
  progressArea() {
    Column({ space: 10 }) {
      ForEach(this.stages, (stage: string, idx: number) => {
        Row({ space: 10 }) {
          if (idx < this.stageIndex || this.draft !== null) {
            Text('✓').fontSize(16).fontColor(this.theme)
          } else if (idx === this.stageIndex) {
            LoadingProgress().width(16).height(16).color(this.theme)
          } else {
            Text('○').fontSize(16).fontColor('#73A98D82')
          }
          Text(stage)
            .fontSize(BubuFont.caption)
            .fontColor(BubuColor.warmBrown)
          Blank()
        }
        .width('100%')
      }, (stage: string) => stage)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.card)
  }

  @Builder
  actionButtons() {
    Column({ space: 10 }) {
      // 生成草稿主按钮（对照 iOS：禁用条件 = 无照片或生成中）。
      Text(this.stageIndex >= 0 && this.draft === null
        ? '生成中…'
        : (this.draft === null ? '生成电影草稿' : '重新生成草稿'))
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(54)
        .backgroundColor(this.canGenerate() ? this.theme : '#59A98D82')
        .borderRadius(27)
        .onClick(() => { if (this.canGenerate()) { this.generateDraft(); } })

      if (this.draft !== null) {
        Text('▶ 播放电影')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme)
          .textAlign(TextAlign.Center)
          .width('100%')
          .height(50)
          .backgroundColor('#1AF28C9E')
          .borderRadius(25)
          .onClick(() => { this.showPlayer = true; })
      }
    }
    .width('100%')
  }

  @Builder
  sectionTitle(title: string, icon: string) {
    Row({ space: 6 }) {
      Text(icon).fontSize(16)
      Text(title)
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
    }
  }

  // —— 派生数据（对照 iOS computed vars）——

  private canGenerate(): boolean {
    return this.selectedPhotoFiles().length > 0 && !(this.stageIndex >= 0 && this.draft === null);
  }

  // 出现过的年龄集合（对照 iOS availableYears）。
  private availableYears(): number[] {
    if (this.profile === null) return [];
    const birthday = this.profile.birthday;
    const set = new Set<number>();
    for (const it of this.items) {
      set.add(AgeCalculator.ageYears(birthday, it.entry.happenedAt));
    }
    return Array.from(set).sort((a: number, b: number): number => a - b);
  }

  // 出现过的地点（对照 iOS availableLocations prefix(8)）。
  private availableLocations(): string[] {
    const set = new Set<string>();
    for (const it of this.items) {
      const loc = it.entry.locationName;
      if (loc !== undefined && loc.length > 0) set.add(loc);
    }
    return Array.from(set).sort().slice(0, 8);
  }

  // 时间范围起点（对照 iOS MovieTimeRange.startDate）。
  private rangeStart(): number | null {
    if (this.selectedRange === 'recent3Months') return Date.now() - 90 * 86400000;
    if (this.selectedRange === 'recentYear') return Date.now() - 365 * 86400000;
    return null;
  }

  // 过滤后的记录（按年龄/地点/时间），时间升序（对照 iOS filteredEntries）。
  private filteredItems(): EntryWithMedia[] {
    const start = this.rangeStart();
    const birthday = this.profile !== null ? this.profile.birthday : 0;
    return this.items
      .filter((it: EntryWithMedia): boolean => {
        const yearOK = this.selectedYear === -1 || this.profile === null
          || AgeCalculator.ageYears(birthday, it.entry.happenedAt) === this.selectedYear;
        const locationOK = this.selectedLocation === '' || it.entry.locationName === this.selectedLocation;
        const rangeOK = start === null || it.entry.happenedAt >= start;
        return yearOK && locationOK && rangeOK;
      })
      .sort((a: EntryWithMedia, b: EntryWithMedia): number => a.entry.happenedAt - b.entry.happenedAt);
  }

  private selectedPreviewMedia(): Media[] {
    const out: Media[] = [];
    for (const it of this.filteredItems()) {
      for (const p of it.photos) out.push(p);
    }
    return out;
  }

  private selectedPhotoFiles(): string[] {
    const out: string[] = [];
    for (const m of this.selectedPreviewMedia()) {
      if (m.localFileName !== undefined && m.localFileName.length > 0) out.push(m.localFileName);
    }
    return out;
  }

  private templateMeta(): MovieTemplateMeta {
    return MOVIE_TEMPLATES.find((t: MovieTemplateMeta): boolean => t.raw === this.selectedTemplate) ?? MOVIE_TEMPLATES[0];
  }

  // 生成草稿（对照 iOS generateDraft：分阶段进度 → 拼字幕 → 可选 AI 旁白）。
  private async generateDraft(): Promise<void> {
    if (this.selectedPhotoFiles().length === 0) return;
    this.draft = null;
    for (let i = 0; i < this.stages.length; i++) {
      this.stageIndex = i;
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 420));
    }
    const title = this.draftTitle();
    let captions = this.buildCaptions();
    let narration: string | undefined = undefined;
    if (ServerConfig.shared.isAIConfigured) {
      // 高光去重取前 8 条（对照 iOS highlights）。
      const set = new Set<string>();
      for (const c of captions) { if (c.length > 0) set.add(c); }
      const highlights = Array.from(set).slice(0, 8);
      try {
        const year = this.selectedYear !== -1 ? this.selectedYear : new Date().getFullYear();
        const text = await AIService.shared.movieNarration(year, ServerConfig.shared.childName, highlights);
        if (text.length > 0) {
          narration = text;
          captions = this.distributeNarration(text, this.selectedPhotoFiles().length);
        }
      } catch (e) {
        // AI 失败时降级为本地字幕（对照 iOS try? 静默）。
      }
    }
    const meta = this.templateMeta();
    this.draft = {
      id: `${Date.now()}`,
      title: title,
      templateRaw: meta.raw,
      templateTitle: meta.title,
      templateEmoji: meta.emoji,
      mediaFiles: this.selectedPhotoFiles(),
      captions: captions,
      narration: narration
    };
    this.stageIndex = -1;
  }

  // 草稿标题（对照 iOS draftTitle）。
  private draftTitle(): string {
    const base = this.selectedYear !== -1 ? `第 ${this.selectedYear} 岁` : this.timeRangeTitle();
    const place = this.selectedLocation !== '' ? ` · ${this.selectedLocation}` : '';
    return `《${ServerConfig.shared.childName}的${base}${place}》`;
  }

  private timeRangeTitle(): string {
    const r = MOVIE_TIME_RANGES.find((x: MovieTimeRangeMeta): boolean => x.raw === this.selectedRange);
    return r !== undefined ? r.title : '全部时间';
  }

  // 用记录文字（或日期）逐张配字幕（对照 iOS buildCaptions）。
  private buildCaptions(): string[] {
    const caps: string[] = [];
    for (const it of this.filteredItems()) {
      const count = it.photos.length;
      if (count === 0) continue;
      const text = it.entry.note !== undefined && it.entry.note.length > 0
        ? it.entry.note
        : BubuDateFormat.shortDate(new Date(it.entry.happenedAt));
      for (let i = 0; i < count; i++) caps.push(text);
    }
    return caps;
  }

  // 把旁白按句子分配到每张照片（对照 iOS distributeNarration）。
  private distributeNarration(narration: string, count: number): string[] {
    if (count <= 0) return [];
    const sentences = narration
      .split(/[。！？!?\n]/)
      .map((s: string): string => s.trim())
      .filter((s: string): boolean => s.length > 0);
    if (sentences.length === 0) {
      const out: string[] = [];
      for (let i = 0; i < count; i++) out.push(narration);
      return out;
    }
    const out: string[] = [];
    for (let i = 0; i < count; i++) out.push(sentences[i % sentences.length]);
    return out;
  }
}
