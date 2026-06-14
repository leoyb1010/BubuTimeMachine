import { Entry, Media, Milestone, HealthRecord } from '../models/Models';
import { MediaType, HealthRecordKind, healthKindMeta } from '../models/Enums';
import { AppDatabase } from '../data/AppDatabase';
import { BubuColor, BubuFont, BubuRadius, BubuShadow } from '../theme/BubuTheme';
import { BubuMascotBadge } from '../components/BubuMascotBadge';
import { BubuExpression } from '../theme/BubuExpression';

// MARK: - 成长报告（对照 iOS Features/AIStudio/GrowthReportView.swift）
// 不做伪发育评估，只呈现这个家庭档案真实收到了什么、缺什么。
// iOS Swift Charts 柱状图 → ArkUI 自绘等高柱（无第三方图表依赖）。

interface MetricItem { title: string; value: string; icon: string; tint: string; }
interface MonthCount { label: string; count: number; sort: number; }
interface KindCount { label: string; count: number; }
interface PairRow { left: string; right: string; }

@Component
export struct GrowthReportView {
  onBack: () => void = () => {};

  @State private entries: Entry[] = [];
  @State private milestones: Milestone[] = [];
  @State private healthRecords: HealthRecord[] = [];
  // 预聚合统计（iOS 用 @Query + computed；HarmonyOS 在 reload 内一次算好）。
  @State private photoCount: number = 0;
  @State private visualMediaCount: number = 0;
  @State private voiceCount: number = 0;
  @State private textCount: number = 0;
  @State private locations: string[] = [];
  @State private topTags: string[] = [];

  private theme: string = BubuColor.primary;

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.entries = await AppDatabase.shared.fetchEntries(false) ?? [];
    this.milestones = await AppDatabase.shared.fetchMilestones() ?? [];
    this.healthRecords = await AppDatabase.shared.fetchHealth() ?? [];

    let photo = 0;
    let visual = 0;
    let voice = 0;
    let text = 0;
    const locSet = new Set<string>();
    const tagCount = new Map<string, number>();
    for (const e of this.entries) {
      if (e.note !== undefined && e.note.length > 0) text += 1;
      if (e.locationName !== undefined && e.locationName.length > 0) locSet.add(e.locationName);
      const media = await AppDatabase.shared.fetchMediaForEntry(e.id);
      for (const m of media) {
        if (m.typeRaw === MediaType.photo) photo += 1;
        if (m.typeRaw === MediaType.photo || m.typeRaw === MediaType.video) visual += 1;
        for (const t of m.aiTags) tagCount.set(t, (tagCount.get(t) ?? 0) + 1);
      }
      const voiceNotes = await AppDatabase.shared.fetchVoiceForEntry(e.id);
      voice += voiceNotes.length;
    }
    this.photoCount = photo;
    this.visualMediaCount = visual;
    this.voiceCount = voice;
    this.textCount = text;
    this.locations = Array.from(locSet).sort();
    this.topTags = Array.from(tagCount.entries())
      .sort((a: [string, number], b: [string, number]): number => b[1] - a[1])
      .slice(0, 8)
      .map((p: [string, number]): string => p[0]);
  }

  build() {
    Column() {
      this.navBar()
      Scroll() {
        Column({ space: 18 }) {
          this.archiveSummary()
          this.metricGrid()
          this.recordingRhythm()
          this.careTraceCard()
          this.milestoneCard()
          this.placeAndSceneCard()
          this.familyParticipationCard()
          this.nextSuggestionCard()
        }
        .padding(16)
        .width('100%')
        .alignItems(HorizontalAlign.Start)
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
      Text('成长报告')
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      Blank()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  @Builder
  archiveSummary() {
    Row({ space: 14 }) {
      BubuMascotBadge({ badgeSize: 62, expression: BubuExpression.reading })
      Column({ space: 8 }) {
        Text('这份档案收到了什么')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text(this.summaryText())
          .fontSize(BubuFont.body)
          .fontColor(BubuColor.warmBrown)
          .lineHeight(23)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding(16)
    .backgroundColor('#14F28C9E')
    .borderRadius(BubuRadius.card)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
  }

  private summaryText(): string {
    if (this.entries.length === 0 && this.healthRecords.length === 0 && this.achievedMilestones().length === 0) {
      return '现在还只是一本空相册。先存几张照片、几句话或一段声音，未来的布布就会慢慢收到一本真实的成长书。';
    }
    return `这里不替布布下发育结论，只整理家人真实留下的材料：${this.textCount} 句文字、${this.photoCount} 张照片、${this.voiceCount} 段声音、${this.healthRecords.length} 条照护记录。`;
  }

  @Builder
  metricGrid() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        this.metric({ title: '照片/视频', value: `${this.visualMediaCount}`, icon: '🖼️', tint: BubuColor.warning })
        this.metric({ title: '家人的话', value: `${this.textCount}`, icon: '💬', tint: this.theme })
      }.width('100%')
      Row({ space: 10 }) {
        this.metric({ title: '声音', value: `${this.voiceCount}`, icon: '🎵', tint: BubuColor.lav })
        this.metric({ title: '已点亮第一次', value: `${this.achievedMilestones().length}`, icon: '⭐', tint: BubuColor.success })
      }.width('100%')
    }
    .width('100%')
  }

  @Builder
  metric(item: MetricItem) {
    Row({ space: 12 }) {
      Stack() {
        Text(item.icon).fontSize(20)
      }
      .width(40)
      .height(40)
      .backgroundColor('#1FF28C9E')
      .borderRadius(13)
      Column({ space: 2 }) {
        Text(item.value)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text(item.title)
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.secondaryText)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .layoutWeight(1)
    .padding(14)
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.small)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
  }

  @Builder
  recordingRhythm() {
    this.reportCardHeader('最近记录节奏', this.rhythmText(), BubuExpression.music)
    if (this.monthlyCounts().length > 0) {
      this.barChart(this.monthlyCounts())
    }
    this.reportCardClose()
  }

  // 自绘等高柱状图（对照 iOS Swift Charts BarMark）。
  @Builder
  barChart(items: MonthCount[]) {
    Row({ space: 8 }) {
      ForEach(items, (item: MonthCount) => {
        Column({ space: 6 }) {
          Blank()
          Column()
            .width('70%')
            .height(`${this.barHeightPercent(item, items)}%`)
            .linearGradient({ angle: 180, colors: [[this.theme, 0.0], ['#99F28C9E', 1.0]] })
            .borderRadius(6)
          Text(item.label)
            .fontSize(11)
            .fontColor(BubuColor.secondaryText)
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.End)
      }, (item: MonthCount) => item.label)
    }
    .width('100%')
    .height(150)
    .alignItems(VerticalAlign.Bottom)
  }

  private barHeightPercent(item: MonthCount, items: MonthCount[]): number {
    let max = 1;
    for (const it of items) { if (it.count > max) max = it.count; }
    return Math.max(8, Math.round((item.count / max) * 84));
  }

  @Builder
  careTraceCard() {
    this.reportCardHeader('生活照护', '只整理餐食、睡眠、不舒服等照护痕迹，不做医学判断。', BubuExpression.eating)
    if (this.healthKindCounts().length === 0) {
      this.quietText('还没有健康照护记录。可以从一顿饭、一次午睡或一次不舒服开始记。')
    } else {
      ForEach(this.healthKindCounts(), (item: KindCount) => {
        this.row({ left: item.label, right: `${item.count} 次` })
      }, (item: KindCount) => item.label)
    }
    this.reportCardClose()
  }

  @Builder
  milestoneCard() {
    this.reportCardHeader('已点亮的第一次',
      this.achievedMilestones().length === 0 ? '还没有点亮里程碑。' : '这些是被家人确认过的成长瞬间。',
      BubuExpression.cheer)
    ForEach(this.achievedMilestones().slice(0, 5), (m: Milestone) => {
      this.row({ left: `${m.emoji} ${m.title}`, right: m.category })
    }, (m: Milestone) => m.id)
    this.reportCardClose()
  }

  @Builder
  placeAndSceneCard() {
    this.reportCardHeader('地点和画面',
      this.locations.length === 0 ? '没有记录地点，隐私保护中。' : '只展示你选择保存过的地点。',
      BubuExpression.thinking)
    if (this.locations.length > 0) {
      this.flowTags(this.locations.slice(0, 8))
    }
    if (this.topTags.length > 0) {
      Text('照片关键词')
        .fontSize(BubuFont.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(BubuColor.secondaryText)
        .margin({ top: 4 })
      this.flowTags(this.topTags)
    }
    this.reportCardClose()
  }

  @Builder
  familyParticipationCard() {
    this.reportCardHeader('谁在陪布布写这本书', '不是排名，只是看见每个人留下的陪伴。', BubuExpression.love)
    ForEach(this.authorCounts(), (item: KindCount) => {
      this.row({ left: item.label, right: `${item.count} 条` })
    }, (item: KindCount) => item.label)
    this.reportCardClose()
  }

  @Builder
  nextSuggestionCard() {
    Row({ space: 12 }) {
      BubuMascotBadge({ badgeSize: 48, expression: BubuExpression.bye })
      Column({ space: 6 }) {
        Text('下次可以补一点')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text(this.suggestionText())
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.secondaryText)
          .lineHeight(20)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding(16)
    .backgroundColor('#12F28C9E')
    .borderRadius(BubuRadius.card)
  }

  // reportCard 卡片在 iOS 是闭包包裹；ArkTS @Builder 不便嵌套 trailing closure，
  // 此处拆成「头部」+ 内容 + 「收尾」三段，靠 Column 自然分组（对照 iOS reportCard）。
  @Builder
  reportCardHeader(title: string, subtitle: string, expression: BubuExpression) {
    Row({ space: 10 }) {
      BubuMascotBadge({ badgeSize: 38, expression: expression })
      Column({ space: 2 }) {
        Text(title)
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text(subtitle)
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.secondaryText)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 8 })
    .backgroundColor(BubuColor.card)
    .borderRadius({ topLeft: BubuRadius.card, topRight: BubuRadius.card })
  }

  @Builder
  reportCardClose() {
    Column()
      .width('100%')
      .height(12)
      .backgroundColor(BubuColor.card)
      .borderRadius({ bottomLeft: BubuRadius.card, bottomRight: BubuRadius.card })
      .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
  }

  @Builder
  row(pair: PairRow) {
    Row() {
      Text(pair.left)
        .fontSize(BubuFont.caption)
        .fontColor(BubuColor.warmBrown)
        .maxLines(1)
        .layoutWeight(1)
      Text(pair.right)
        .fontSize(BubuFont.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(BubuColor.secondaryText)
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 8 })
    .backgroundColor(BubuColor.card)
  }

  @Builder
  quietText(text: string) {
    Text(text)
      .fontSize(BubuFont.caption)
      .fontColor(BubuColor.secondaryText)
      .lineHeight(20)
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
      .backgroundColor(BubuColor.card)
  }

  // 标签流（对照 iOS FlowTags），简化为可换行 Flex。
  @Builder
  flowTags(tags: string[]) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(tags, (t: string) => {
        Text(t)
          .fontSize(12)
          .fontColor(this.theme)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor('#1AF28C9E')
          .borderRadius(12)
          .margin({ right: 6, bottom: 6 })
      }, (t: string) => t)
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 8 })
    .backgroundColor(BubuColor.card)
  }

  // —— 计算属性（对照 iOS computed vars）——

  private achievedMilestones(): Milestone[] {
    return this.milestones
      .filter((m: Milestone): boolean => m.happenedAt !== undefined && m.happenedAt !== null)
      .sort((a: Milestone, b: Milestone): number => (b.happenedAt ?? 0) - (a.happenedAt ?? 0));
  }

  private monthlyCounts(): MonthCount[] {
    const groups = new Map<string, MonthCount>();
    for (const e of this.entries) {
      const d = new Date(e.happenedAt);
      const key = `${d.getFullYear()}-${d.getMonth()}`;
      const sort = new Date(d.getFullYear(), d.getMonth(), 1).getTime();
      const existing = groups.get(key);
      if (existing !== undefined) {
        existing.count += 1;
      } else {
        groups.set(key, { label: `${d.getMonth() + 1}月`, count: 1, sort: sort });
      }
    }
    return Array.from(groups.values())
      .sort((a: MonthCount, b: MonthCount): number => a.sort - b.sort)
      .slice(-6);
  }

  private healthKindCounts(): KindCount[] {
    const counts = new Map<string, number>();
    for (const h of this.healthRecords) {
      counts.set(h.kind, (counts.get(h.kind) ?? 0) + 1);
    }
    const out: KindCount[] = [];
    counts.forEach((count: number, kind: string) => {
      const meta = healthKindMeta(kind as HealthRecordKind);
      out.push({ label: `${meta.emoji} ${meta.title}`, count: count });
    });
    return out.sort((a: KindCount, b: KindCount): number => b.count - a.count);
  }

  private authorCounts(): KindCount[] {
    const counts = new Map<string, number>();
    for (const e of this.entries) {
      counts.set(e.authorRole, (counts.get(e.authorRole) ?? 0) + 1);
    }
    const out: KindCount[] = [];
    counts.forEach((count: number, role: string) => {
      out.push({ label: role, count: count });
    });
    return out.sort((a: KindCount, b: KindCount): number => b.count - a.count);
  }

  private rhythmText(): string {
    const cutoff = Date.now() - 30 * 86400000;
    const recent = this.entries.filter((e: Entry): boolean => e.happenedAt >= cutoff).length;
    return recent === 0 ? '最近 30 天还没有新记录。' : `最近 30 天记录了 ${recent} 个瞬间。`;
  }

  private suggestionText(): string {
    if (this.voiceCount === 0) return '可以录一段今天的声音。未来的布布会想听见家人当时的语气。';
    if (this.healthRecords.length === 0) return '可以补几条餐食、睡眠或不舒服记录，照护线索会更完整。';
    if (this.locations.length === 0) return '如果愿意，可以在记录时打开“记录地点”，以后能按公园、家、旅行来回看。';
    if (this.achievedMilestones().length === 0) return '可以去里程碑里点亮一个第一次，比如第一次挥手或第一次叫妈妈。';
    return '继续保持：照片、声音、文字、照护和第一次都在变丰富。';
  }
}
