import { ChildProfile, Entry, GrowthMeasurement } from '../models/Models';
import { Mood, SyncState, moodEmoji, FamilyRole } from '../models/Enums';
import { AppDatabase } from '../data/AppDatabase';
import { ServerConfig } from '../services/ServerConfig';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor, BubuFont, BubuRadius, BubuShadow } from '../theme/BubuTheme';
import { BubuMotion } from '../theme/BubuMotion';
import { BubuHaptics } from '../theme/BubuHaptics';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { BubuIdentityCard } from '../components/BubuIdentityCard';
import { BubuIcon, BubuIconBadge, BubuIconName } from '../components/BubuIcon';
import { ChildProfileView } from './ChildProfileView';
import { HealthHomeView } from './HealthHomeView';
import { GrowthCurveView } from './GrowthCurveView';
import { SettingsView } from './SettingsView';
import { AlbumView } from './AlbumView';
import { TimelineView } from './TimelineView';
import { EntryDetailView } from './EntryDetailView';
import { MediaStore } from '../services/MediaStore';
import { BubuMascotBadge, BubuExpression } from '../components/BubuMascotBadge';
import { CaptureModel } from './CaptureModel';
import { QuickCaptureSheet } from './QuickCaptureSheet';
import { OnThisDayView } from './OnThisDayView';
import { DailyQuestion } from './DailyQuestion';
import { NaturalCaptureBar } from './NaturalCaptureBar';
import { HomeRoute, BirthdayCountdownView } from './HomeDestinations';

// MARK: - 首页 · 成长仪表盘（对照 iOS Features/Capture/CaptureHomeView.swift）
// 专属布布的主屏：问候 → 身份卡 → 主操作（记录/相册/健康）→ 紧凑四宫格（里程碑/成长/故事/今日一问）
// → 最近时光 → 那年今日 → 同步健康度。记录走 CaptureModel + EntryWriter（与意图/小组件同一写入层）。
// 沿用 RootPage 既有的零参 HomeView() 契约与内部 @State 索引式导航（HomeRoute）。
@Component
export struct HomeView {
  @State profile: ChildProfile | null = null;
  @State entries: Entry[] = [];
  // 内部路由（对照 iOS NavigationStack / navigationDestination）。
  @State route: HomeRoute = HomeRoute.home;
  @State selectedEntry: Entry | null = null;
  // entryId → 首张照片沙盒绝对路径（最近时光/那年今日卡片缩略图）。
  @State photoMap: Map<string, string> = new Map();
  // 统计
  @State photoCount: number = 0;
  @State healthCount: number = 0;
  @State milestoneTotal: number = 0;
  @State milestoneDoneCount: number = 0;
  @State storyChapterCount: number = 0;
  @State pendingSyncCount: number = 0;
  @State growthMeasurements: GrowthMeasurement[] = [];
  // 快速记录业务模型（对照 iOS @State model: CaptureModel?）。
  @State model: CaptureModel = new CaptureModel(ServerConfig.shared.currentRole);
  // 底栏中央「记录」键触发计数（对照 iOS quickCaptureTrigger）。RootPage 自增 → 打开快速记录。
  @Link @Watch('onCaptureSignal') captureSignal: number;
  // RootPage 注入：首页里程碑卡直接切到「里程碑」Tab，避免误进健康。
  onOpenMilestones?: () => void;

  @State private pageIn: boolean = false;
  @State private floatLoop: boolean = false;
  @State private heroBreath: boolean = false;
  @State private viewportW: number = 0;
  @StorageLink('bubuTabBarVisible') tabBarVisible: boolean = true;
  @StorageLink('bubuBackSignal') @Watch('onBackSignal') backSignal: number = 0;
  @StorageLink('bubuHandledCaptureSignal') handledCaptureSignal: number = 0;

  private onCaptureSignal(): void {
    if (this.captureSignal > this.handledCaptureSignal) {
      this.handledCaptureSignal = this.captureSignal;
      this.startQuickCapture();
    }
  }

  private onBackSignal(): void {
    if (this.backSignal <= 0) return;
    if (this.selectedEntry !== null) {
      this.selectedEntry = null;
      this.tabBarVisible = true;
      this.reload();
      return;
    }
    if (this.route !== HomeRoute.home) {
      this.route = HomeRoute.home;
      this.tabBarVisible = true;
      this.reload();
    }
  }

  aboutToAppear(): void {
    this.tabBarVisible = true;
    this.reload();
    this.startHomeMotion();
    if (this.captureSignal > this.handledCaptureSignal) {
      this.handledCaptureSignal = this.captureSignal;
      setTimeout(() => {
        this.startQuickCapture();
      }, 80);
    }
  }

  private startHomeMotion(): void {
    this.pageIn = false;
    this.floatLoop = false;
    this.heroBreath = false;
    animateTo(BubuMotion.gentle, () => { this.pageIn = true; });
    animateTo(BubuMotion.floating, () => { this.floatLoop = true; });
    animateTo(BubuMotion.breathe, () => { this.heroBreath = true; });
  }

  private async reload(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    const entries = await AppDatabase.shared.fetchEntries(false) ?? [];
    this.entries = entries;
    const photos = await AppDatabase.shared.fetchAllPhotos() ?? [];
    const health = await AppDatabase.shared.fetchHealth() ?? [];
    const growth = await AppDatabase.shared.fetchGrowth() ?? [];
    const milestones = await AppDatabase.shared.fetchMilestones() ?? [];
    const capsules = await AppDatabase.shared.fetchCapsules() ?? [];
    this.photoCount = photos.length;
    this.healthCount = health.length;
    this.growthMeasurements = growth;
    this.milestoneTotal = milestones.length;
    this.milestoneDoneCount = milestones.filter(m => m.happenedAt !== undefined).length;
    this.storyChapterCount = milestones.filter(m => m.happenedAt !== undefined && (m.detail ?? '').trim().length > 0).length;
    this.pendingSyncCount =
      this.entries.filter(e => e.syncState !== SyncState.synced).length +
      health.filter(h => h.syncState !== SyncState.synced).length +
      growth.filter(g => g.syncState !== SyncState.synced).length +
      milestones.filter(m => m.syncState !== SyncState.synced).length +
      capsules.filter(c => c.syncState !== SyncState.synced).length;
    // 首张照片缩略图映射（最近两条 + 那年今日）。
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

  private entryList(): Entry[] {
    return this.entries ?? [];
  }

  // 打开快速记录（对照 iOS startQuickCapture）。
  private startQuickCapture(prefillNote: string = ''): void {
    BubuHaptics.tapLight();
    this.model.startQuickCapture(prefillNote);
    this.tabBarVisible = false;
    setTimeout(() => {
      animateTo(BubuMotion.gentle, () => { this.route = HomeRoute.record; });
    }, 40);
  }

  private navigate(route: HomeRoute): void {
    BubuHaptics.selection();
    this.tabBarVisible = false;
    setTimeout(() => {
      animateTo(BubuMotion.gentle, () => { this.route = route; });
    }, 40);
  }

  private openMilestones(): void {
    BubuHaptics.selection();
    this.tabBarVisible = true;
    if (this.onOpenMilestones) {
      this.onOpenMilestones();
    }
  }

  private isCompact(): boolean {
    return this.viewportW <= 0 || this.viewportW < 1500;
  }

  private isNarrow(): boolean {
    return this.viewportW > 0 && this.viewportW < 320;
  }

  build() {
    if (this.route === HomeRoute.record) {
      QuickCaptureSheet({
        model: this.model,
        onSaved: () => {
          this.route = HomeRoute.home;
          this.tabBarVisible = true;
          this.reload();
        },
        onClose: () => {
          this.route = HomeRoute.home;
          this.tabBarVisible = true;
        },
        onNaturalCapture: () => {
          this.navigate(HomeRoute.naturalCapture);
        }
      })
    } else if (this.selectedEntry) {
      Column() {
        this.panelHeader('记录详情')
        EntryDetailView({
          entry: this.selectedEntry!,
          onDismiss: () => {
            this.selectedEntry = null;
            this.reload();
          }
        })
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.route === HomeRoute.profile) {
      Column() {
        this.panelHeader('布布资料')
        ChildProfileView()
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.route === HomeRoute.health) {
      Column() {
        this.panelHeader('布布健康')
        HealthHomeView()
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.route === HomeRoute.growth) {
      Column() {
        this.panelHeader('成长曲线')
        GrowthCurveView()
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.route === HomeRoute.settings) {
      SettingsView({
        onClose: () => {
          this.route = HomeRoute.home;
          this.tabBarVisible = true;
          this.reload();
        }
      })
        .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.route === HomeRoute.timeline) {
      Column() {
        this.panelHeader('时光')
        TimelineView()
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.route === HomeRoute.album) {
      Column() {
        this.panelHeader('照片墙')
        AlbumView()
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.route === HomeRoute.onThisDay) {
      Column() {
        this.panelHeader('那年今日')
        OnThisDayView({
          onSelect: (entry: Entry) => {
            this.tabBarVisible = false;
            this.selectedEntry = entry;
          }
        })
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.route === HomeRoute.naturalCapture) {
      Column() {
        this.panelHeader('一句话智能记录')
        NaturalCaptureBar()
          .padding(16)
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else if (this.route === HomeRoute.birthday) {
      Column() {
        this.panelHeader('下个生日')
        BirthdayCountdownView({ profile: this.profile })
          .layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(BubuColor.cream)
    } else {
      this.homePage()
    }
  }

  @Builder
  homePage() {
    Stack() {
      Scroll() {
        Column({ space: this.isCompact() ? 10 : 12 }) {
          this.greetingRow()
          this.identityCardTop()
          this.primaryActionDock()
          this.dashboardGridTop()
          this.recentMomentsSection()
          this.onThisDaySection()
          this.saveHealthStrip()
          // 给底部悬浮 Tab 栏与浮动按钮留出空间。
	          Blank().height(this.isCompact() ? 142 : 130)
	        }
	        .padding({ left: this.isCompact() ? 12 : 16, right: this.isCompact() ? 12 : 16, top: this.isCompact() ? 6 : 8 })
	        .width('100%')
        .opacity(this.pageIn ? 1 : 0)
        .translate({ x: 0, y: this.pageIn ? 0 : BubuMotion.entranceOffsetY })
        .animation(BubuMotion.gentle)
      }
      .backgroundColor(BubuColor.cream)
      .width('100%').height('100%')

      // 一句话智能记录浮动按钮：对齐 iOS 1.2.0，手机/折叠屏都保留轻量入口。
      this.naturalCaptureFloatingButton()

      // 保存成功贴纸（对照 iOS savedToast）。
      if (this.model.savedFlash) {
        this.savedToast()
      }
    }
	    .alignContent(Alignment.BottomEnd)
	    .width('100%').height('100%')
	    .onAreaChange((_old: Area, area: Area) => {
	      const w = area.width as number;
	      if (w > 0) this.viewportW = w;
	    })
	  }

  // MARK: 顶部问候行（对照 iOS greetingRow + todayStatusPill）

  @Builder
  greetingRow() {
    Row() {
      Column({ space: 1 }) {
        Text(`${this.greetingText()} 呀`)
          .fontSize(this.isCompact() ? 12 : 14)
          .fontWeight(FontWeight.Medium)
          .fontColor(BubuColor.secondaryText)
        if (this.profile) {
          Row({ space: 8 }) {
            Text(this.profile!.name)
              .fontSize(this.isCompact() ? 24 : 28)
              .fontWeight(FontWeight.Bolder)
              .fontColor(BubuColor.warmBrown)
            Text(AgeCalculator.ageDescription(this.profile!.birthday, Date.now()))
              .fontSize(this.isCompact() ? 12 : 14)
              .fontWeight(FontWeight.Medium)
              .fontColor(BubuColor.primary)
          }
          .alignItems(VerticalAlign.Bottom)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.todayStatusPill()

      BubuIconBadge({
        name: BubuIconName.gear,
        badgeSize: this.isCompact() ? 38 : 42,
        iconSize: this.isCompact() ? 18 : 20,
        color: BubuColor.primary,
        fill: '#F2FFFFFF',
        radius: this.isCompact() ? 19 : 21,
        strokeWidth: 2.3
      })
        .margin({ left: 8 })
        .onClick(() => {
          this.navigate(HomeRoute.settings);
        })
    }
    .width('100%')
    .padding({ top: this.isCompact() ? 0 : 2 })
  }

  @Builder
  todayStatusPill() {
    Column({ space: 3 }) {
      Row({ space: 5 }) {
        BubuIcon({ name: BubuIconName.calendar, iconSize: 11, color: BubuColor.secondaryText, strokeWidth: 1.8 })
        Text(this.todayText())
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.secondaryText)
      }
      Row({ space: 5 }) {
        BubuIcon({ name: this.weatherIconName(), iconSize: 12, color: BubuColor.secondaryText, strokeWidth: 1.7 })
        Text(this.weatherMoodText())
          .fontSize(11)
          .fontColor(BubuColor.secondaryText)
      }
    }
    .alignItems(HorizontalAlign.End)
    .padding({ left: this.isCompact() ? 8 : 10, right: this.isCompact() ? 8 : 10, top: this.isCompact() ? 6 : 7, bottom: this.isCompact() ? 6 : 7 })
    .backgroundColor('#85FFFFFF')
    .borderRadius(17)
  }

  // MARK: 布布身份卡（顶部主卡，对照 iOS identityCardTop）

  @Builder
  identityCardTop() {
    if (this.profile) {
      BubuIdentityCard({ profile: this.profile!, compact: this.isCompact() })
	        .scale({ x: this.heroBreath && !this.isCompact() ? 1.006 : 1, y: this.heroBreath && !this.isCompact() ? 1.006 : 1 })
        .animation(BubuMotion.breathe)
      Text('编辑布布资料')
        .fontSize(12)
        .fontColor(BubuColor.primary)
        .alignSelf(ItemAlign.End)
        .onClick(() => {
          this.navigate(HomeRoute.profile);
        })
    } else {
      Row({ space: 14 }) {
        BubuMascotBadge({ badgeSize: 56, expression: BubuExpression.happy })
        Column({ space: 4 }) {
          Text('建立布布的档案')
            .fontSize(18)
            .fontWeight(FontWeight.Bolder)
            .fontColor(BubuColor.warmBrown)
          Text('填上生日，就能看到「相遇第几天」啦 ♡')
            .fontSize(12)
            .fontColor(BubuColor.secondaryText)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('›').fontSize(18).fontColor(BubuColor.secondaryText)
      }
      .width('100%')
      .padding(18)
      .linearGradient({
        angle: 135,
        colors: [[BubuColor.peach, 0.0], [BubuColor.pink, 0.5], [BubuColor.lav, 1.0]]
      })
      .borderRadius(BubuRadius.card)
      .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
      .onClick(() => {
        this.navigate(HomeRoute.profile);
      })
    }
  }

  // MARK: 首屏主操作 — 记录 / 相册 / 健康（对照 iOS primaryActionDock）

  @Builder
  primaryActionDock() {
    Row({ space: this.isCompact() ? 8 : 10 }) {
      // 记录此刻（主操作，占满剩余宽度）。
      Row({ space: this.isCompact() ? 8 : 10 }) {
        BubuIconBadge({
          name: BubuIconName.plus,
          badgeSize: this.isCompact() ? 38 : 44,
          iconSize: this.isCompact() ? 20 : 23,
          color: '#FFFFFF',
          fill: BubuColor.primary,
          radius: this.isCompact() ? 19 : 22,
          strokeWidth: 3
        })
        Column({ space: 2 }) {
          Text('记录此刻')
            .fontSize(this.isCompact() ? 14 : 16)
            .fontWeight(FontWeight.Bolder)
            .fontColor(BubuColor.warmBrown)
          Text('照片、语音、文字一起收好')
            .fontSize(this.isCompact() ? 10 : 11)
            .fontColor(BubuColor.secondaryText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .height(this.isCompact() ? 56 : 64)
      .layoutWeight(1)
      .padding({ left: this.isCompact() ? 10 : 12, right: this.isCompact() ? 8 : 10 })
      .backgroundColor('#F2FFFFFF')
      .borderRadius(this.isCompact() ? 20 : 24)
      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.96 })
      .onClick(() => { this.startQuickCapture(); })

      this.quickDockButton(BubuIconName.photo, '相册', BubuColor.mint, () => {
        this.navigate(HomeRoute.album);
      })
      this.quickDockButton(BubuIconName.health, '健康', BubuColor.sky, () => {
        this.navigate(HomeRoute.health);
      })
    }
    .width('100%')
  }

  @Builder
  quickDockButton(iconName: string, title: string, tint: string, action: () => void) {
    Column({ space: 3 }) {
      BubuIconBadge({
        name: iconName,
        badgeSize: this.isCompact() ? 30 : 34,
        iconSize: this.isCompact() ? 16 : 18,
        color: BubuColor.deepRose,
        fill: tint,
        radius: this.isCompact() ? 15 : 17,
        strokeWidth: 2.1
      })
      Text(title)
        .fontSize(this.isCompact() ? 10 : 11)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      Text(title === '相册' ? `${this.photoCount} 张` : '餐睡')
        .fontSize(this.isCompact() ? 8 : 9)
        .fontColor(BubuColor.secondaryText)
        .maxLines(1)
    }
    .width(this.isCompact() ? 58 : 66).height(this.isCompact() ? 56 : 64)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F2FFFFFF')
    .borderRadius(this.isCompact() ? 19 : 22)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(action)
  }

  // MARK: 紧凑四宫格 — 里程碑 / 成长数据 / 故事 / 今日一问（对照 iOS dashboardGridTop）

  @Builder
	  dashboardGridTop() {
	    if (this.isNarrow()) {
	      Column({ space: 10 }) {
	        this.constellationTile()
	        this.growthTile()
	        this.storyTile()
	        this.dailyQuestionTile()
	      }
	      .width('100%')
	    } else {
	      Column({ space: 10 }) {
	        Row({ space: 10 }) {
	          this.constellationTile()
	          this.growthTile()
	        }.width('100%')
	        Row({ space: 10 }) {
	          this.storyTile()
	          this.dailyQuestionTile()
	        }.width('100%')
	      }
	      .width('100%')
	    }
	  }

  @Builder
  tileSurface(fill: string) {
    // 占位：实际内容由各 tile 自行铺，这里仅留作样式约定参考。
  }

  @Builder
  constellationTile() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        BubuIconBadge({
          name: BubuIconName.sparkles,
          badgeSize: 38,
          iconSize: 16,
          color: BubuColor.deepRose,
          fill: '#61FFC2D6',
          radius: 19,
          strokeWidth: 1.8,
          filled: true
        })
        Column({ space: 2 }) {
          Text('里程碑')
            .fontSize(14)
            .fontWeight(FontWeight.Bolder)
            .fontColor(BubuColor.warmBrown)
          Text(`${this.milestoneDoneCount}/${Math.max(this.milestoneTotal, 1)} 颗`)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.deepRose)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      // 迷你星座装饰（对照 iOS BubuMiniConstellation）。
      Row({ space: 6 }) {
        ForEach([0, 1, 2, 3, 4], (i: number) => {
          BubuIcon({
            name: BubuIconName.star,
            iconSize: 14,
            color: i < this.milestoneDoneCount ? BubuColor.butter : BubuColor.secondaryText,
            strokeWidth: 1.6,
            filled: i < this.milestoneDoneCount
          })
        }, (i: number) => `star-${i}`)
      }
    }
    .layoutWeight(1)
    .height(this.isCompact() ? 96 : 104)
    .padding(this.isCompact() ? 10 : 12)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(BubuColor.card)
    .borderRadius(24)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => { this.openMilestones(); })
  }

  @Builder
  growthTile() {
    Column({ space: this.isCompact() ? 4 : 6 }) {
      Row({ space: 6 }) {
        this.growthStat('身高', 'height', 'cm')
        this.growthStat('体重', 'weight', 'kg')
      }.width('100%')
      // 渐升 bar（装饰，对照 iOS growthBars）。
      Row({ space: 4 }) {
        ForEach([40, 55, 62, 70, 76, 88, 100], (h: number, i: number) => {
          Column()
            .layoutWeight(1)
            .height((this.isCompact() ? 24 : 30) * h / 100)
            .backgroundColor(i === 6 ? BubuColor.primary : BubuColor.peach)
            .borderRadius(3)
        }, (h: number, i: number) => `bar-${i}`)
      }
      .height(this.isCompact() ? 24 : 30)
      .alignItems(VerticalAlign.Bottom)
      .width('100%')
      Text('成长数据')
        .fontSize(11)
        .fontColor(BubuColor.secondaryText)
    }
    .layoutWeight(1)
    .height(this.isCompact() ? 96 : 104)
    .padding(this.isCompact() ? 12 : 14)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(BubuColor.card)
    .borderRadius(24)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => {
      this.navigate(HomeRoute.growth);
    })
  }

  @Builder
  growthStat(title: string, kind: 'height' | 'weight', unit: string) {
    Column({ space: 1 }) {
      Text(title)
        .fontSize(11)
        .fontColor(BubuColor.secondaryText)
      Row({ space: 1 }) {
        Text(this.latestGrowthValue(kind))
          .fontSize(this.isCompact() ? 17 : 19)
          .fontWeight(FontWeight.Bolder)
          .fontColor(BubuColor.warmBrown)
        Text(unit)
          .fontSize(this.isCompact() ? 11 : 12)
          .fontColor(BubuColor.warmBrown)
      }
      .alignItems(VerticalAlign.Bottom)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  private latestGrowthValue(kind: 'height' | 'weight'): string {
    const ordered = this.growthMeasurements
      .slice()
      .sort((a: GrowthMeasurement, b: GrowthMeasurement) => b.measuredAt - a.measuredAt);
    for (const g of ordered) {
      const value = kind === 'height' ? g.heightCm : g.weightKg;
      if (value !== undefined && value !== null) {
        return Math.round(value) === value ? `${Math.round(value)}` : value.toFixed(1);
      }
    }
    return '—';
  }

  @Builder
  storyTile() {
    Row({ space: 10 }) {
      BubuIconBadge({
        name: BubuIconName.sparkles,
        badgeSize: 46,
        iconSize: 24,
        color: BubuColor.deepRose,
        fill: '#FFFFFF',
        radius: 13,
        strokeWidth: 2,
        filled: true
      })
      Column({ space: 3 }) {
        Text('故事绘本')
          .fontSize(14)
          .fontWeight(FontWeight.Bolder)
          .fontColor(BubuColor.warmBrown)
        Text(this.storyHeadline())
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.deepRose)
        Text('自动编成故事')
          .fontSize(10)
          .fontColor(BubuColor.secondaryText)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .layoutWeight(1)
    .height(this.isCompact() ? 96 : 104)
    .padding(this.isCompact() ? 10 : 12)
    .justifyContent(FlexAlign.Center)
    .linearGradient({
      angle: 135,
      colors: [[BubuColor.butter, 0.0], [BubuColor.peach, 0.5], [BubuColor.pink, 1.0]]
    })
    .borderRadius(24)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => {
      this.navigate(HomeRoute.timeline);
    })
  }

  @Builder
  dailyQuestionTile() {
    Row({ space: 9 }) {
      BubuMascotBadge({ badgeSize: 38, expression: BubuExpression.surprised })
      Column({ space: 3 }) {
        Text('今日一问')
          .fontSize(14)
          .fontWeight(FontWeight.Bolder)
          .fontColor(BubuColor.warmBrown)
        Text('答一句就成时光')
          .fontSize(11)
          .fontColor(BubuColor.secondaryText)
          .maxLines(1)
        Text('记录')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(BubuColor.primary)
          .borderRadius(10)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .layoutWeight(1)
    .height(this.isCompact() ? 96 : 104)
    .padding(this.isCompact() ? 10 : 12)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(BubuColor.card)
    .borderRadius(24)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => {
      const birthday = this.profile ? this.profile!.birthday : undefined;
      this.startQuickCapture(`【今日一问】${DailyQuestion.todays(birthday)}\n`);
    })
  }

  private storyHeadline(): string {
    return this.storyChapterCount > 0 ? `已写到第 ${Math.min(this.storyChapterCount, 99)} 篇` : '翻开第一页';
  }

  // MARK: 最近时光（行卡，对照 iOS recentMomentsSection）

  @Builder
  recentMomentsSection() {
    if (this.entryList().length > 0) {
      Column({ space: 10 }) {
        Row() {
          Text('最近时光')
            .fontSize(17)
            .fontWeight(FontWeight.Bolder)
            .fontColor(BubuColor.warmBrown)
          Blank()
          Text('查看全部 ›')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(BubuColor.primary)
            .onClick(() => {
              this.navigate(HomeRoute.timeline);
            })
        }
        .width('100%')
        ForEach(this.entryList().slice(0, 2), (entry: Entry) => {
          this.momentRow(entry)
        }, (entry: Entry) => entry.id)
      }
      .width('100%')
    }
  }

  @Builder
  momentRow(entry: Entry) {
    Row({ space: 12 }) {
      if (this.photoMap.has(entry.id)) {
        Image(this.photoMap.get(entry.id))
          .width(64).height(64)
          .objectFit(ImageFit.Cover)
          .borderRadius(16)
      } else {
        Text(moodEmoji(entry.moodRaw as Mood | undefined))
          .fontSize(30)
          .width(64).height(64)
          .textAlign(TextAlign.Center)
          .backgroundColor('#1FF28C9E')
          .borderRadius(16)
      }
      Column({ space: 2 }) {
        Text(BubuDateFormat.monthDay(new Date(entry.happenedAt)))
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.primary)
        Text(entry.note !== undefined && entry.note.length > 0 ? entry.note : '记录此刻')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (entry.moodRaw !== undefined) {
          Text(`${moodEmoji(entry.moodRaw as Mood)} ${entry.moodRaw}`)
            .fontSize(12)
            .fontColor(BubuColor.secondaryText)
            .maxLines(1)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(BubuColor.card)
    .borderRadius(22)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .onClick(() => {
      BubuHaptics.selection();
      this.tabBarVisible = false;
      animateTo(BubuMotion.gentle, () => { this.selectedEntry = entry; });
    })
  }

  // MARK: 那年今日（对照 iOS onThisDaySection）

  @Builder
  onThisDaySection() {
    if (this.onThisDayEntries().length > 0) {
      Column({ space: 10 }) {
        Row({ space: 6 }) {
        BubuIcon({ name: BubuIconName.calendar, iconSize: 18, color: BubuColor.primary, strokeWidth: 2.1 })
        Text('那年今日')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
          Text('›').fontSize(16).fontColor(BubuColor.secondaryText)
          Blank()
        }
        .width('100%')
        .onClick(() => {
          this.navigate(HomeRoute.onThisDay);
        })

        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.onThisDayEntries().slice(0, 8), (e: Entry) => {
              this.memoryCard(e)
            }, (e: Entry) => e.id)
          }
          .padding({ right: 4 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(BubuColor.card)
      .borderRadius(BubuRadius.card)
    }
  }

  @Builder
  memoryCard(e: Entry) {
    Column({ space: 6 }) {
      if (this.photoMap.has(e.id)) {
        Image(this.photoMap.get(e.id))
          .width(130).height(130)
          .objectFit(ImageFit.Cover)
          .borderRadius(BubuRadius.small)
      } else {
        Text(moodEmoji(e.moodRaw as Mood | undefined))
          .fontSize(40)
          .width(130).height(130)
          .textAlign(TextAlign.Center)
          .backgroundColor('#1FF28C9E')
          .borderRadius(BubuRadius.small)
      }
      if (this.profile) {
        Text(AgeCalculator.compactAge(this.profile!.birthday, e.happenedAt))
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.primary)
      }
      Text(this.yearsAgoText(e.happenedAt))
        .fontSize(11)
        .fontColor(BubuColor.secondaryText)
    }
    .width(130)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      BubuHaptics.selection();
      this.tabBarVisible = false;
      animateTo(BubuMotion.gentle, () => { this.selectedEntry = e; });
    })
  }

  // MARK: 保存健康度（对照 iOS saveHealthStrip）

  @Builder
  saveHealthStrip() {
    Row({ space: 10 }) {
      BubuIcon({
        name: this.pendingSyncCount === 0 ? BubuIconName.checkCloud : BubuIconName.sync,
        iconSize: 22,
        color: this.pendingSyncCount === 0 ? BubuColor.success : BubuColor.primary,
        strokeWidth: 2.2
      })
      Column({ space: 2 }) {
        Text('本地已保存')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text(this.syncSummary())
          .fontSize(11)
          .fontColor(BubuColor.secondaryText)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('查看')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.primary)
    }
    .width('100%')
	    .padding(12)
	    .backgroundColor('#CCFFFFFF')
	    .borderRadius(BubuRadius.small)
	    .onClick(() => { this.navigate(HomeRoute.settings); })
	  }

  // MARK: 浮动按钮 / 保存贴纸（对照 iOS naturalCaptureFloatingButton / savedToast）

  @Builder
  naturalCaptureFloatingButton() {
    Stack() {
      Column({ space: 0 }) {
        BubuIcon({
          name: BubuIconName.magic,
          iconSize: this.isCompact() ? 20 : 22,
          color: '#FFFFFF',
          strokeWidth: 2.4
        })
        Text('AI')
          .fontSize(this.isCompact() ? 9 : 10)
          .fontWeight(FontWeight.Bolder)
          .fontColor(Color.White)
      }
      .width(this.isCompact() ? 50 : 56).height(this.isCompact() ? 50 : 56)
      .justifyContent(FlexAlign.Center)
      .linearGradient({
        angle: 135,
        colors: [[BubuColor.primary, 0.0], [BubuColor.pink, 0.58], [BubuColor.peach, 1.0]]
      })
      .borderRadius(this.isCompact() ? 25 : 28)
      .border({ width: 1.5, color: '#DFFFFFFF' })
      .shadow({ radius: this.floatLoop ? 12 : 9, color: '#3DE15C86', offsetY: this.floatLoop ? 5 : 3 })

      BubuIcon({ name: BubuIconName.sparkles, iconSize: 10, color: BubuColor.butter, strokeWidth: 1.4, filled: true })
        .position({ x: this.isCompact() ? 9 : 10, y: this.isCompact() ? 11 : 12 })
      BubuIcon({ name: BubuIconName.sparkles, iconSize: 9, color: '#FFFFFF', strokeWidth: 1.3, filled: true })
        .position({ x: this.isCompact() ? 42 : 48, y: this.isCompact() ? 12 : 13 })
    }
    .width(this.isCompact() ? 54 : 60).height(this.isCompact() ? 54 : 60)
    .margin({ right: this.isCompact() ? 14 : 18, bottom: this.isCompact() ? 124 : 150 })
    .scale({ x: this.floatLoop ? 1.018 : 1, y: this.floatLoop ? 1.018 : 1 })
    .animation(BubuMotion.floating)
    .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.92 })
    .onClick(() => { this.navigate(HomeRoute.naturalCapture); })
  }

  @Builder
  savedToast() {
    Column() {
      Row({ space: 10 }) {
        BubuMascotBadge({ badgeSize: 44, expression: BubuExpression.yeah })
        Text('已经收好啦')
          .fontSize(BubuFont.body)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
      }
      .padding({ left: 18, right: 18, top: 10, bottom: 10 })
      .backgroundColor(BubuColor.success)
      .borderRadius(28)
      .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
    }
    .width('100%')
    .padding({ top: 16 })
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .position({ x: 0, y: 0 })
  }

  // MARK: 面板头部 + 路由复位

  @Builder
  panelHeader(title: string) {
    Row({ space: 12 }) {
      Button('返回')
        .backgroundColor('#F3F3F3')
        .fontColor(BubuColor.warmBrown)
        .onClick(() => { this.closePanel(); })
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      Blank()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  private closePanel(): void {
    this.route = HomeRoute.home;
    this.selectedEntry = null;
    this.tabBarVisible = true;
    this.reload();
  }

  // MARK: 文案 / 计算（对照 iOS greetingText / todayText / weather / syncSummary / onThisDay）

  private greetingText(): string {
    const h = new Date().getHours();
    if (h >= 5 && h < 11) {
      return '☀︎ 早安';
    } else if (h >= 11 && h < 14) {
      return '🍚 中午好';
    } else if (h >= 14 && h < 18) {
      return '🌤 下午好';
    } else if (h >= 18 && h < 23) {
      return '🌙 晚上好';
    }
    return '💤 夜深了';
  }

  private todayText(): string {
    const now = new Date();
    const weekdays: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return `${now.getMonth() + 1}月${now.getDate()}日 ${weekdays[now.getDay()]}`;
  }

  private weatherIconName(): string {
    const h = new Date().getHours();
    if (h >= 6 && h < 18) {
      return BubuIconName.cloudSun;
    } else if (h >= 18 && h < 23) {
      return BubuIconName.moon;
    }
    return BubuIconName.sparkles;
  }

  private weatherMoodText(): string {
    const h = new Date().getHours();
    if (h >= 6 && h < 12) {
      return '晨光好';
    } else if (h >= 12 && h < 18) {
      return '适合记录';
    } else if (h >= 18 && h < 23) {
      return '晚风轻';
    }
    return '安静时刻';
  }

  private syncSummary(): string {
    if (!ServerConfig.shared.isConfigured) {
      return this.pendingSyncCount === 0 ? '离线也可用，暂无待同步' : `离线可用，${this.pendingSyncCount} 项等服务器`;
    }
    return this.pendingSyncCount === 0 ? '已和家里服务器同步' : `${this.pendingSyncCount} 项正在等待同步`;
  }

  private onThisDayEntries(): Entry[] {
    const now = new Date();
    return this.entryList().filter(e => {
      const d = new Date(e.happenedAt);
      return d.getMonth() === now.getMonth() &&
        d.getDate() === now.getDate() &&
        !this.isSameDay(e.happenedAt, Date.now());
    });
  }

  private isSameDay(a: number, b: number): boolean {
    const da = new Date(a);
    const db = new Date(b);
    return da.getFullYear() === db.getFullYear() && da.getMonth() === db.getMonth() && da.getDate() === db.getDate();
  }

  private yearsAgoText(ms: number): string {
    const years = new Date().getFullYear() - new Date(ms).getFullYear();
    return years <= 0 ? '今年' : `${years}年前的今天`;
  }
}
