// MARK: - 里程碑 & 成就墙（对照 iOS Features/Milestones/MilestonesHomeView.swift）
// 已达成（高亮）+ 待达成（待解锁）网格。可从预设库添加，也可完全自定义。
// 展示方式可在「星盘视图」与「奖章墙」间切换。点亮新里程碑时由本页播放仪式。

import { util } from '@kit.ArkTS';
import { Milestone, ChildProfile } from '../models/Models';
import { MILESTONE_CATEGORIES, MILESTONE_PRESETS } from '../models/MilestoneTemplates';
import { AppDatabase } from '../data/AppDatabase';
import { SyncState } from '../models/Enums';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor, BubuFont, BubuRadius, BubuShadow } from '../theme/BubuTheme';
import { BubuMotion } from '../theme/BubuMotion';
import { BubuHaptics } from '../theme/BubuHaptics';
import { BubuProgressRing, BubuSparkle } from '../components/MacaronComponents';
import { BubuMascotBadge, BubuExpression } from '../components/BubuMascotBadge';
import { BubuIconBadge, BubuIconName } from '../components/BubuIcon';
import { CeremonyAnimation } from '../components/CeremonyAnimation';
import { BubuConstellationView } from './BubuConstellationView';
import { MilestonePickerSheet, MilestoneEditSheet } from './MilestoneSheets';

@Component
export struct MilestonesView {
  @State milestones: Milestone[] = [];
  @State profile: ChildProfile | null = null;

  @State private searchText: string = '';
  @State private selectedCategory: string = '全部';
  @State private isConstellation: boolean = true;   // 展示方式：星盘视图 / 奖章墙

  // 弹层状态（iOS .sheet → ArkUI @State + Stack 覆盖）
  @State private showPicker: boolean = false;
  @State private showCustom: boolean = false;
  @State private detailFor: Milestone | null = null;
  // 仪式（iOS .fullScreenCover）
  @State private ceremonyFor: Milestone | null = null;
  @State private showAddMenu: boolean = false;
  @State private pageIn: boolean = false;
  @State private viewportW: number = 0;
  @StorageLink('bubuBackSignal') @Watch('onBackSignal') backSignal: number = 0;

  aboutToAppear(): void {
    this.reload();
    this.pageIn = false;
    animateTo(BubuMotion.gentle, () => { this.pageIn = true; });
  }

  private async reload(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    this.milestones = await AppDatabase.shared.fetchMilestones() ?? [];
    this.checkPendingCeremony();
  }

  private onBackSignal(): void {
    if (this.backSignal <= 0) return;
    if (this.showAddMenu) {
      this.showAddMenu = false;
      return;
    }
    if (this.showPicker) {
      this.showPicker = false;
      return;
    }
    if (this.showCustom) {
      this.showCustom = false;
      return;
    }
    if (this.detailFor !== null) {
      this.detailFor = null;
      return;
    }
    if (this.ceremonyFor !== null) {
      this.ceremonyFor = null;
    }
  }

  // —— 计算属性（对照 iOS）——
  private isAchieved(m: Milestone): boolean {
    return m.happenedAt !== undefined && m.happenedAt !== null;
  }

  private filteredMilestones(): Milestone[] {
    const query: string = this.searchText.trim();
    return this.milestones.filter((m: Milestone) => {
      const categoryOK: boolean = this.selectedCategory === '全部' || m.category === this.selectedCategory;
      const searchOK: boolean = query.length === 0
        || m.title.toLowerCase().indexOf(query.toLowerCase()) >= 0
        || m.category.toLowerCase().indexOf(query.toLowerCase()) >= 0;
      return categoryOK && searchOK;
    });
  }

  private achieved(): Milestone[] {
    return this.filteredMilestones().filter((m: Milestone) => this.isAchieved(m));
  }

  private allPending(): Milestone[] {
    return this.filteredMilestones().filter((m: Milestone) => !this.isAchieved(m));
  }

  // 默认（无搜索 + 全部分类）只看最可能发生的 12 个（对照 iOS pending）。
  private pending(): Milestone[] {
    if (this.searchText.trim().length === 0 && this.selectedCategory === '全部') {
      return this.allPending().slice(0, 12);
    }
    return this.allPending();
  }

  private categoryOptions(): string[] {
    return ['全部'].concat(MILESTONE_CATEGORIES);
  }

  private gridColumns(): string {
    if (this.viewportW <= 0) return '1fr 1fr 1fr';
    if (this.viewportW > 0 && this.viewportW < 320) return '1fr 1fr';
    if (this.viewportW > 0 && this.viewportW < 1500) return '1fr 1fr 1fr';
    return '1fr 1fr 1fr 1fr';
  }

  private gridColumnCount(): number {
    if (this.viewportW <= 0) return 3;
    if (this.viewportW > 0 && this.viewportW < 320) return 2;
    if (this.viewportW > 0 && this.viewportW < 1500) return 3;
    return 4;
  }

  // 有新达成且未播放仪式 → 播放（对照 iOS onChange）。
  private checkPendingCeremony(): void {
    if (this.ceremonyFor !== null) { return; }
    const pendingCeremony: Milestone | undefined =
      this.achieved().find((m: Milestone) => !m.ceremonyPlayed);
    if (pendingCeremony !== undefined) { this.ceremonyFor = pendingCeremony; }
  }

  build() {
    Stack() {
      Scroll() {
        Column({ space: 28 }) {
          this.progressHeader()
          this.filters()
          if (this.isConstellation) {
            // 星盘视图（复用同一份筛选后的里程碑）
            BubuConstellationView({
              milestones: this.filteredMilestones(),
              primary: BubuColor.primary,
              onTapStar: (m: Milestone) => { this.detailFor = m; }
            })
          } else {
            if (this.achieved().length > 0) { this.achievedWall() }
            if (this.pending().length > 0) { this.pendingWall() }
          }
	          if (this.milestones.length === 0) { this.emptyState() }
	          Blank().height(130)
        }
	        .padding(16).width('100%')
	        .opacity(this.pageIn ? 1 : 0)
	        .translate({ x: 0, y: this.pageIn ? 0 : BubuMotion.entranceOffsetY })
	        .animation(BubuMotion.gentle)
	      }
      .backgroundColor(BubuColor.background).width('100%').height('100%')

      // 顶栏切换 + 添加（对照 iOS toolbar 左右两侧按钮）
      this.topBar()

      // 添加菜单（自定义 / 管理预设）
      if (this.showAddMenu) { this.addMenu() }

      // 弹层覆盖
      if (this.showPicker) {
        MilestonePickerSheet({
          existingTitles: this.milestones.map((m: Milestone) => m.title),
          onCancel: () => { this.showPicker = false; },
          onAdd: (titles: string[]) => { this.addPresets(titles); }
        })
      }
      if (this.showCustom) {
        MilestoneEditSheet({
          milestone: null,
          profile: this.profile,
          onCancel: () => { this.showCustom = false; },
          onSaved: () => { this.showCustom = false; this.reload(); },
          onDeleted: () => { this.showCustom = false; this.reload(); }
        })
      }
      if (this.detailFor !== null) {
        MilestoneEditSheet({
          milestone: this.detailFor,
          profile: this.profile,
          onCancel: () => { this.detailFor = null; },
          onSaved: () => { this.detailFor = null; this.reload(); },
          onDeleted: () => { this.detailFor = null; this.reload(); }
        })
      }
      // 仪式（全屏覆盖）
      if (this.ceremonyFor !== null) {
        CeremonyAnimation({
          title: `🎉 ${this.ceremonyFor.title}`,
          subtitle: this.ceremonySubtitle(),
          onDismiss: () => { this.markCeremonyPlayed(); }
        })
      }
    }
	    .width('100%').height('100%')
	    .onAreaChange((_old: Area, area: Area) => {
	      const w = area.width as number;
	      if (w > 0) this.viewportW = w;
	    })
	  }

  private ceremonySubtitle(): string {
    const m: Milestone | null = this.ceremonyFor;
    if (m === null || this.profile === null) { return ''; }
    const at: number = m.happenedAt ?? Date.now();
    return AgeCalculator.ageDescription(this.profile.birthday, at);
  }

  // —— 顶栏 ——（对照 iOS toolbar）
  @Builder
  private topBar() {
    Row() {
      // 左：切换展示方式
      BubuIconBadge({
        name: this.isConstellation ? BubuIconName.grid : BubuIconName.star,
        badgeSize: 40,
        iconSize: 20,
        color: BubuColor.primary,
        fill: '#F2FFFFFF',
        radius: 20,
        strokeWidth: 2.1,
        filled: !this.isConstellation
      })
	        .onClick(() => {
	          BubuHaptics.selection();
	          animateTo(BubuMotion.quick, () => { this.isConstellation = !this.isConstellation; });
	        })
      Blank()
      Text('里程碑').fontSize(BubuFont.headline).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Blank()
      // 右：添加
      BubuIconBadge({
        name: BubuIconName.plus,
        badgeSize: 40,
        iconSize: 22,
        color: BubuColor.primary,
        fill: '#F2FFFFFF',
        radius: 20,
        strokeWidth: 2.8
      })
	        .onClick(() => {
	          BubuHaptics.tapLight();
	          animateTo(BubuMotion.quick, () => { this.showAddMenu = !this.showAddMenu; });
	        })
    }
    .width('100%').padding({ left: 8, right: 8, top: 6 })
    .position({ x: 0, y: 0 })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private addMenu() {
    Column({ space: 0 }) {
      Text('✨ 自定义里程碑')
        .fontSize(BubuFont.body).fontColor(BubuColor.warmBrown).padding(14).width('100%')
        .onClick(() => { this.showAddMenu = false; this.showCustom = true; })
      Divider().color(BubuColor.hairline)
      Text('☰ 管理预设清单')
        .fontSize(BubuFont.body).fontColor(BubuColor.warmBrown).padding(14).width('100%')
        .onClick(() => { this.showAddMenu = false; this.showPicker = true; })
    }
    .width(200)
    .backgroundColor(BubuColor.card).borderRadius(BubuRadius.small)
    .shadow({ radius: 16, color: BubuShadow.cardColor, offsetY: 6 })
    .position({ x: '50%', y: 50 })
  }

  // 进度卡（对照 iOS progressHeader：lav→pink 渐变 + 进度环）
  private doneCount(): number {
    return this.milestones.filter((m: Milestone) => this.isAchieved(m)).length;
  }

  @Builder
  private progressHeader() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Row({ space: 16 }) {
        Stack() {
          BubuProgressRing({
            value: this.doneCount(), total: Math.max(this.milestones.length, 1),
            ringSize: 60, stroke: 7, color: '#FFFFFF', track: '#66FFFFFF'
          })
          Text(`${this.doneCount()}`).fontSize(18).fontWeight(FontWeight.Bolder).fontColor('#FFFFFF')
        }.width(60).height(60)
        Column({ space: 3 }) {
          Text(`已点亮 ${this.doneCount()} / ${Math.max(this.milestones.length, 1)} 颗星`)
            .fontSize(17).fontWeight(FontWeight.Bolder).fontColor('#FFFFFF')
            .shadow({ radius: 2, color: '#1A000000', offsetY: 1 })
          Text(`还有 ${Math.max(0, this.milestones.length - this.doneCount())} 颗等你点亮 ♡`)
            .fontSize(12.5).fontWeight(FontWeight.Medium).fontColor('#F2FFFFFF')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }
      .width('100%').padding(16)
      BubuSparkle({ starSize: 13, color: '#F2FFFFFF' }).margin(14)
    }
    .width('100%').margin({ top: 44 })
    .linearGradient({
      angle: 90,
      colors: [[BubuColor.lav, 0.0], [BubuColor.pink, 1.0]]
    })
    .borderRadius(24)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
  }

  // 筛选（搜索框 + 分类胶囊，对照 iOS filters）
  @Builder
  private filters() {
    Column({ space: 10 }) {
      TextInput({ text: this.searchText, placeholder: '搜索里程碑，比如 走路、吃饭、睡觉' })
        .fontSize(BubuFont.caption).fontColor(BubuColor.warmBrown)
        .padding(12).width('100%')
        .backgroundColor(BubuColor.card).borderRadius(BubuRadius.small)
        .border({ width: 1, color: '#B3DBCCC2' })
        .onChange((v: string) => { this.searchText = v; })
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.categoryOptions(), (category: string) => {
            Text(category)
              .fontSize(BubuFont.caption).fontWeight(FontWeight.Medium)
	        .fontColor(this.selectedCategory === category ? '#FFFFFF' : BubuColor.primary)
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
	              .backgroundColor(this.selectedCategory === category ? BubuColor.primary : BubuColor.softFill)
	              .borderRadius(20)
	              .scale({ x: this.selectedCategory === category ? 1.05 : 1, y: this.selectedCategory === category ? 1.05 : 1 })
	              .animation(BubuMotion.quick)
	              .onClick(() => {
	                BubuHaptics.selection();
	                animateTo(BubuMotion.quick, () => { this.selectedCategory = category; });
	              })
          }, (category: string) => category)
        }
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
    }
    .width('100%')
  }

  // 已点亮墙（对照 iOS achievedWall）
  @Builder
  private achievedWall() {
    Column({ space: 12 }) {
      Text('⭐ 已点亮')
        .fontSize(BubuFont.headline).fontWeight(FontWeight.Bold).fontColor(BubuColor.primary).width('100%')
      Grid() {
        ForEach(this.achieved(), (m: Milestone) => {
          GridItem() { this.medallion(m, true) }
        }, (m: Milestone) => m.id)
      }
	      .columnsTemplate(this.gridColumns()).columnsGap(10).rowsGap(10)
	      .height(Math.ceil(this.achieved().length / this.gridColumnCount()) * 108).width('100%')
    }
    .width('100%')
  }

  // 待点亮墙（对照 iOS pendingWall）
  @Builder
  private pendingWall() {
    Column({ space: 12 }) {
      Text('☆ 适龄推荐 · 待点亮')
        .fontSize(BubuFont.headline).fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.secondaryText).width('100%')
      if (this.searchText.trim().length === 0 && this.selectedCategory === '全部') {
        Text('先看最可能发生的 12 个。其它里程碑可以用搜索或分类找到，不把 100 多项都压在眼前。')
          .fontSize(BubuFont.caption).fontColor(BubuColor.secondaryText).width('100%')
      }
      Grid() {
        ForEach(this.pending(), (m: Milestone) => {
          GridItem() { this.medallion(m, false) }
        }, (m: Milestone) => m.id)
      }
	      .columnsTemplate(this.gridColumns()).columnsGap(10).rowsGap(10)
	      .height(Math.ceil(this.pending().length / this.gridColumnCount()) * 108).width('100%')
    }
    .width('100%')
  }

  // 奖章（对照 iOS medallion）
  @Builder
  private medallion(m: Milestone, lit: boolean) {
    Column({ space: 8 }) {
      Stack() {
        Circle().width(62).height(62)
          .fill(lit ? '#26F28C9E' : BubuColor.softFill)
          .border({ width: lit ? 2 : 0, color: BubuColor.primary })
        Text(m.emoji).fontSize(lit ? 32 : 29).opacity(lit ? 1 : 0.58)
      }
      .width(62).height(62)
      Text(m.title)
        .fontSize(12).fontWeight(FontWeight.Medium)
        .fontColor(lit ? BubuColor.warmBrown : BubuColor.secondaryText)
        .maxLines(2).textAlign(TextAlign.Center)
    }
    .width('100%').padding({ top: 6, bottom: 6 }).justifyContent(FlexAlign.Center)
    .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.92 })
    .onClick(() => { this.detailFor = m; })
  }

  // 空态（对照 iOS emptyState）
  @Builder
  private emptyState() {
    Column({ space: 16 }) {
      BubuMascotBadge({ badgeSize: 84, expression: BubuExpression.cheer })
      Text('还没有里程碑\n点右上角 + 号，从清单选或自定义布布的第一次')
        .fontSize(BubuFont.body).fontColor(BubuColor.secondaryText).textAlign(TextAlign.Center)
    }
    .width('100%').padding({ top: 60, bottom: 60 })
  }

  // —— 动作 ——
  // 批量添加预设（对照 iOS addSelected）
  private async addPresets(titles: string[]): Promise<void> {
    for (const tpl of MILESTONE_PRESETS) {
      if (titles.indexOf(tpl.title) >= 0) {
        const m: Milestone = {
          id: util.generateRandomUUID(true),
          title: tpl.title, category: tpl.category, emoji: tpl.emoji,
          isCustom: false, ceremonyPlayed: false,
          syncState: SyncState.local, createdAt: Date.now()
        };
        await AppDatabase.shared.upsertMilestone(m);
      }
    }
    this.showPicker = false;
    await this.reload();
  }

  // 仪式播放完成 → 标记 ceremonyPlayed（对照 iOS fullScreenCover 回调）
  private async markCeremonyPlayed(): Promise<void> {
    const m: Milestone | null = this.ceremonyFor;
    if (m !== null) {
      m.ceremonyPlayed = true;
      m.syncState = SyncState.local;
      await AppDatabase.shared.upsertMilestone(m);
    }
    this.ceremonyFor = null;
    await this.reload();
  }
}
