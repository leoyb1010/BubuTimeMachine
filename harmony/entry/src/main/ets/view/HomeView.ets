import { ChildProfile, Entry } from '../models/Models';
import { Mood, SyncState, moodEmoji, FamilyRole } from '../models/Enums';
import { AppDatabase } from '../data/AppDatabase';
import { ServerConfig } from '../services/ServerConfig';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor, BubuFont, BubuRadius, BubuShadow } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { IdentityCard } from './IdentityCard';
import { ChildProfileView } from './ChildProfileView';
import { HealthHomeView } from './HealthHomeView';
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
import { HomeRoute, BirthdayCountdownView } from './HomeDestinations';
import { promptAction } from '@kit.ArkUI';

// MARK: - 首页 · 成长仪表盘（对照 iOS Features/Capture/CaptureHomeView.swift）
// 专属布布的主屏：问候 → 身份卡 → 主操作（记录/相册/健康）→ 紧凑四宫格（星座/成长/故事/今日一问）
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
  @State pendingSyncCount: number = 0;
  // 快速记录业务模型（对照 iOS @State model: CaptureModel?）。
  @State model: CaptureModel = new CaptureModel(ServerConfig.shared.currentRole);
  // 底栏中央「记录」键触发计数（对照 iOS quickCaptureTrigger）。RootPage 自增 → 打开快速记录。
  @Link @Watch('onCaptureSignal') captureSignal: number;

  private onCaptureSignal(): void {
    if (this.captureSignal > 0) this.startQuickCapture();
  }

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    const entries = await AppDatabase.shared.fetchEntries(false) ?? [];
    this.entries = entries;
    const photos = await AppDatabase.shared.fetchAllPhotos() ?? [];
    const health = await AppDatabase.shared.fetchHealth() ?? [];
    const milestones = await AppDatabase.shared.fetchMilestones() ?? [];
    const capsules = await AppDatabase.shared.fetchCapsules() ?? [];
    this.photoCount = photos.length;
    this.healthCount = health.length;
    this.milestoneTotal = milestones.length;
    this.milestoneDoneCount = milestones.filter(m => m.happenedAt !== undefined).length;
    this.pendingSyncCount =
      this.entries.filter(e => e.syncState !== SyncState.synced).length +
      health.filter(h => h.syncState !== SyncState.synced).length +
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
    this.model.startQuickCapture(prefillNote);
    this.route = HomeRoute.record;
  }

  build() {
    if (this.route === HomeRoute.record) {
      QuickCaptureSheet({
        model: this.model,
        onSaved: () => {
          this.route = HomeRoute.home;
          this.reload();
        },
        onClose: () => {
          this.route = HomeRoute.home;
        },
        onNaturalCapture: () => {
          // 一句话智能记录：本切片回落到把焦点留在写一句（与 iOS NaturalCapturePanel 等价入口）。
          promptAction.showToast({ message: '在「写一句」里写下此刻，保存时会智能规整' });
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
    } else if (this.route === HomeRoute.settings) {
      SettingsView({
        onClose: () => {
          this.route = HomeRoute.home;
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
          onSelect: (entry: Entry) => { this.selectedEntry = entry; }
        })
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
        Column({ space: 12 }) {
          this.greetingRow()
          this.identityCardTop()
          this.primaryActionDock()
          this.dashboardGridTop()
          this.recentMomentsSection()
          this.onThisDaySection()
          this.saveHealthStrip()
          // 给底部悬浮 Tab 栏与浮动按钮留出空间。
          Blank().height(110)
        }
        .padding({ left: 16, right: 16, top: 8 })
        .width('100%')
      }
      .backgroundColor(BubuColor.cream)
      .width('100%').height('100%')

      // 一句话智能记录浮动按钮（对照 iOS naturalCaptureFloatingButton）。
      this.naturalCaptureFloatingButton()

      // 保存成功贴纸（对照 iOS savedToast）。
      if (this.model.savedFlash) {
        this.savedToast()
      }
    }
    .alignContent(Alignment.BottomEnd)
    .width('100%').height('100%')
  }

  // MARK: 顶部问候行（对照 iOS greetingRow + todayStatusPill）

  @Builder
  greetingRow() {
    Row() {
      Column({ space: 1 }) {
        Text(`${this.greetingText()} 呀`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(BubuColor.secondaryText)
        if (this.profile) {
          Row({ space: 8 }) {
            Text(this.profile!.name)
              .fontSize(28)
              .fontWeight(FontWeight.Bolder)
              .fontColor(BubuColor.warmBrown)
            Text(AgeCalculator.ageDescription(this.profile!.birthday, Date.now()))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(BubuColor.primary)
          }
          .alignItems(VerticalAlign.Bottom)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.todayStatusPill()

      Text('⚙️')
        .fontSize(18)
        .width(42).height(42)
        .textAlign(TextAlign.Center)
        .backgroundColor('#F2FFFFFF')
        .borderRadius(21)
        .margin({ left: 8 })
        .onClick(() => { this.route = HomeRoute.settings; })
    }
    .width('100%')
    .padding({ top: 2 })
  }

  @Builder
  todayStatusPill() {
    Column({ space: 3 }) {
      Row({ space: 5 }) {
        Text('📅').fontSize(10)
        Text(this.todayText())
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.secondaryText)
      }
      Row({ space: 5 }) {
        Text(this.weatherSymbol()).fontSize(11)
        Text(this.weatherMoodText())
          .fontSize(11)
          .fontColor(BubuColor.secondaryText)
      }
    }
    .alignItems(HorizontalAlign.End)
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .backgroundColor('#85FFFFFF')
    .borderRadius(17)
  }

  // MARK: 布布身份卡（顶部主卡，对照 iOS identityCardTop）

  @Builder
  identityCardTop() {
    if (this.profile) {
      IdentityCard({ profile: this.profile! })
      Text('编辑布布资料')
        .fontSize(12)
        .fontColor(BubuColor.primary)
        .alignSelf(ItemAlign.End)
        .onClick(() => { this.route = HomeRoute.profile; })
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
      .onClick(() => { this.route = HomeRoute.profile; })
    }
  }

  // MARK: 首屏主操作 — 记录 / 相册 / 健康（对照 iOS primaryActionDock）

  @Builder
  primaryActionDock() {
    Row({ space: 10 }) {
      // 记录此刻（主操作，占满剩余宽度）。
      Row({ space: 10 }) {
        Text('+')
          .fontSize(20)
          .fontWeight(FontWeight.Bolder)
          .fontColor(Color.White)
          .width(42).height(42)
          .textAlign(TextAlign.Center)
          .linearGradient({ angle: 135, colors: [[BubuColor.primary, 0.0], [BubuColor.deepRose, 1.0]] })
          .borderRadius(21)
        Column({ space: 2 }) {
          Text('记录此刻')
            .fontSize(16)
            .fontWeight(FontWeight.Bolder)
            .fontColor(BubuColor.warmBrown)
          Text('照片、语音、文字一起收好')
            .fontSize(11)
            .fontColor(BubuColor.secondaryText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .height(64)
      .layoutWeight(1)
      .padding({ left: 12, right: 10 })
      .backgroundColor('#F2FFFFFF')
      .borderRadius(24)
      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.96 })
      .onClick(() => { this.startQuickCapture(); })

      this.quickDockButton('🖼️', '相册', `${this.photoCount} 张`, BubuColor.mint, () => { this.route = HomeRoute.album; })
      this.quickDockButton('🩺', '健康', '餐睡', BubuColor.sky, () => { this.route = HomeRoute.health; })
    }
    .width('100%')
  }

  @Builder
  quickDockButton(icon: string, title: string, subtitle: string, tint: string, action: () => void) {
    Column({ space: 3 }) {
      Text(icon)
        .fontSize(16)
        .width(28).height(28)
        .textAlign(TextAlign.Center)
        .backgroundColor(tint)
        .borderRadius(14)
      Text(title)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)
      Text(subtitle)
        .fontSize(9)
        .fontColor(BubuColor.secondaryText)
        .maxLines(1)
    }
    .width(66).height(64)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F2FFFFFF')
    .borderRadius(22)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(action)
  }

  // MARK: 紧凑四宫格 — 成长星座 / 成长数据 / 故事 / 今日一问（对照 iOS dashboardGridTop）

  @Builder
  dashboardGridTop() {
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

  @Builder
  tileSurface(fill: string) {
    // 占位：实际内容由各 tile 自行铺，这里仅留作样式约定参考。
  }

  @Builder
  constellationTile() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text('✨')
          .fontSize(15)
          .width(34).height(34)
          .textAlign(TextAlign.Center)
          .backgroundColor('#61FFC2D6')
          .borderRadius(17)
        Column({ space: 2 }) {
          Text('成长星座')
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
          Text(i < this.milestoneDoneCount ? '★' : '☆')
            .fontSize(14)
            .fontColor(i < this.milestoneDoneCount ? BubuColor.butter : BubuColor.secondaryText)
        }, (i: number) => `star-${i}`)
      }
    }
    .layoutWeight(1)
    .height(104)
    .padding(12)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(BubuColor.card)
    .borderRadius(24)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => { this.route = HomeRoute.health; })
  }

  @Builder
  growthTile() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        this.growthStat('身高', '—', 'cm')
        this.growthStat('体重', '—', 'kg')
      }.width('100%')
      // 渐升 bar（装饰，对照 iOS growthBars）。
      Row({ space: 4 }) {
        ForEach([40, 55, 62, 70, 76, 88, 100], (h: number, i: number) => {
          Column()
            .layoutWeight(1)
            .height(30 * h / 100)
            .backgroundColor(i === 6 ? BubuColor.primary : BubuColor.peach)
            .borderRadius(3)
        }, (h: number, i: number) => `bar-${i}`)
      }
      .height(30)
      .alignItems(VerticalAlign.Bottom)
      .width('100%')
      Text('成长数据')
        .fontSize(11)
        .fontColor(BubuColor.secondaryText)
    }
    .layoutWeight(1)
    .height(104)
    .padding(14)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(BubuColor.card)
    .borderRadius(24)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => { this.route = HomeRoute.health; })
  }

  @Builder
  growthStat(title: string, value: string, unit: string) {
    Column({ space: 1 }) {
      Text(title)
        .fontSize(11)
        .fontColor(BubuColor.secondaryText)
      Row({ space: 1 }) {
        Text(value)
          .fontSize(19)
          .fontWeight(FontWeight.Bolder)
          .fontColor(BubuColor.warmBrown)
        Text(unit)
          .fontSize(12)
          .fontColor(BubuColor.warmBrown)
      }
      .alignItems(VerticalAlign.Bottom)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  storyTile() {
    Row({ space: 10 }) {
      Text('✦')
        .fontSize(24)
        .width(46).height(52)
        .textAlign(TextAlign.Center)
        .backgroundColor('#FFFFFF')
        .fontColor(BubuColor.deepRose)
        .borderRadius(13)
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
    .height(104)
    .padding(12)
    .justifyContent(FlexAlign.Center)
    .linearGradient({
      angle: 135,
      colors: [[BubuColor.butter, 0.0], [BubuColor.peach, 0.5], [BubuColor.pink, 1.0]]
    })
    .borderRadius(24)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => { this.route = HomeRoute.timeline; })
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
    .height(104)
    .padding(12)
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
    return this.milestoneDoneCount > 0 ? `已写到第 ${Math.min(this.milestoneDoneCount, 99)} 篇` : '翻开第一页';
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
            .onClick(() => { this.route = HomeRoute.timeline; })
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
    .onClick(() => { this.selectedEntry = entry; })
  }

  // MARK: 那年今日（对照 iOS onThisDaySection）

  @Builder
  onThisDaySection() {
    if (this.onThisDayEntries().length > 0) {
      Column({ space: 10 }) {
        Row({ space: 6 }) {
          Text('📅').fontSize(18)
          Text('那年今日')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
          Text('›').fontSize(16).fontColor(BubuColor.secondaryText)
          Blank()
        }
        .width('100%')
        .onClick(() => { this.route = HomeRoute.onThisDay; })

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
    .onClick(() => { this.selectedEntry = e; })
  }

  // MARK: 保存健康度（对照 iOS saveHealthStrip）

  @Builder
  saveHealthStrip() {
    Row({ space: 10 }) {
      Text(this.pendingSyncCount === 0 ? '☁️' : '🔄')
        .fontSize(22)
        .fontColor(this.pendingSyncCount === 0 ? BubuColor.success : BubuColor.primary)
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
    .onClick(() => { this.route = HomeRoute.settings; })
  }

  // MARK: 浮动按钮 / 保存贴纸（对照 iOS naturalCaptureFloatingButton / savedToast）

  @Builder
  naturalCaptureFloatingButton() {
    Column() {
      Text('AI')
        .fontSize(13)
        .fontWeight(FontWeight.Bolder)
        .fontColor(Color.White)
    }
    .width(66).height(66)
    .justifyContent(FlexAlign.Center)
    .linearGradient({
      angle: 135,
      colors: [['#FFFFFF', 0.0], [BubuColor.pink, 0.6], [BubuColor.lav, 1.0]]
    })
    .borderRadius(33)
    .border({ width: 2, color: '#D1FFFFFF' })
    .shadow({ radius: 16, color: '#47E15C86', offsetY: 8 })
    .margin({ right: 18, bottom: 98 })
    .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.92 })
    .onClick(() => { this.startQuickCapture(); })
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

  private weatherSymbol(): string {
    const h = new Date().getHours();
    if (h >= 6 && h < 18) {
      return '⛅';
    } else if (h >= 18 && h < 23) {
      return '🌙';
    }
    return '✨';
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
