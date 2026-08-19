import { BubuColor, BubuFont, BubuRadius, BubuShadow, bubuCardCol } from '../theme/BubuTheme';
import { BubuMascotBadge } from '../components/BubuMascotBadge';
import { BubuExpression } from '../theme/BubuExpression';
import { FirstPersonDiaryView } from './FirstPersonDiaryView';
import { GrowthMovieView } from './GrowthMovieView';
import { FamilyEnsembleView } from './FamilyEnsembleView';
import { GrowthReportView } from './GrowthReportView';
import { BubuStoryView } from './BubuStoryView';
import { CapsuleView } from './CapsuleView';
import { BubuQAView } from './BubuQAView';
import { WeeklyReportView } from './WeeklyReportView';
import { SoundRingView } from './SoundRingView';
import { VoiceArchiveView } from './VoiceArchiveView';
import { BubuIconBadge, BubuIconName } from '../components/BubuIcon';

// MARK: - 布布的魔法屋（对照 iOS Features/AIStudio/AIStudioHomeView.swift）
// 自托管 AI 的创作中心：成长绘本 / 未来胶囊 / 第一人称日记 / 成长电影 / 家人合奏 / 成长报告。
// RootPage 把本组件直接作为「故事」Tab 渲染（无 NavPathStack），故内部用 @State route 就地切换子页。

// 魔法屋能力（对照 iOS 2.11：一个主位 + 回顾 / 创作 / 声音三个分区）。
interface CapabilityTile {
  iconName: string;
  title: string;
  subtitle: string;
  tint: string;       // 背景渐变副色
  route: string;
}

const REVIEW_TILES: CapabilityTile[] = [
  { iconName: BubuIconName.calendar, title: '布布周报', subtitle: '这一周的小故事', tint: BubuColor.peach, route: 'weekly' },
  { iconName: BubuIconName.sparkles, title: '成长报告', subtitle: '整理成长变化', tint: BubuColor.butter, route: 'report' },
  { iconName: BubuIconName.video, title: '成长电影', subtitle: '精选照片成短片', tint: BubuColor.sky, route: 'movie' }
];

const CREATION_TILES: CapabilityTile[] = [
  { iconName: BubuIconName.textBubble, title: '第一人称日记', subtitle: '改写成布布的话', tint: BubuColor.pink, route: 'diary' },
  { iconName: BubuIconName.home, title: '家人合奏', subtitle: '合成完整故事', tint: BubuColor.mint, route: 'ensemble' }
];

const SOUND_TILES: CapabilityTile[] = [
  { iconName: BubuIconName.waveform, title: '声音年轮', subtitle: '一圈是一岁', tint: BubuColor.lav, route: 'soundRing' },
  { iconName: BubuIconName.mic, title: '成长之声', subtitle: '按岁归档的语音', tint: BubuColor.sky, route: 'voiceArchive' }
];

@Component
export struct AIStudioView {
  // 当前子页路由（空 = 魔法屋首页）。对照 iOS NavigationLink 的目的地。
  @State @Watch('syncNavigationDepth') private route: string = '';
  @State private viewportW: number = 0;
  @StorageLink('bubuTabBarVisible') tabBarVisible: boolean = true;
  @StorageLink('bubuBackSignal') @Watch('onBackSignal') backSignal: number = 0;
  @StorageLink('bubuNavigationDepth') navigationDepth: number = 0;
  // 主题主色（对照 iOS env.theme.theme.primary）。
  private theme: string = BubuColor.primary;

  aboutToAppear(): void {
    this.tabBarVisible = true;
    this.syncNavigationDepth();
  }

  private onBackSignal(): void {
    if (this.backSignal <= 0 || this.navigationDepth !== 1) return;
    if (this.route.length > 0) {
      this.route = '';
      this.tabBarVisible = true;
    }
  }

  private syncNavigationDepth(): void {
    this.navigationDepth = this.route.length > 0 ? 1 : 0;
  }

  private isCompact(): boolean {
    return this.viewportW <= 0 || this.viewportW < 1500;
  }

  private isNarrow(): boolean {
    return this.viewportW > 0 && this.viewportW < 320;
  }

  build() {
    if (this.route === 'diary') {
      FirstPersonDiaryView({ onBack: (): void => { this.route = ''; } })
    } else if (this.route === 'movie') {
      GrowthMovieView({ onBack: (): void => { this.route = ''; } })
    } else if (this.route === 'ensemble') {
      FamilyEnsembleView({ onBack: (): void => { this.route = ''; } })
    } else if (this.route === 'report') {
      GrowthReportView({ onBack: (): void => { this.route = ''; } })
    } else if (this.route === 'qa') {
      BubuQAView({ onBack: (): void => { this.route = ''; this.tabBarVisible = true; } })
    } else if (this.route === 'weekly') {
      WeeklyReportView({ onBack: (): void => { this.route = ''; this.tabBarVisible = true; } })
    } else if (this.route === 'soundRing') {
      SoundRingView({ onBack: (): void => { this.route = ''; this.tabBarVisible = true; } })
    } else if (this.route === 'voiceArchive') {
      VoiceArchiveView({ onClose: (): void => { this.route = ''; this.tabBarVisible = true; } })
    } else if (this.route === 'story') {
      // 成长绘本（对照 iOS BubuStoryView 翻页绘本）
      Column() {
        this.subBackBar('布布的成长绘本')
        BubuStoryView({ compact: this.isCompact() })
          .layoutWeight(1)
      }.width('100%').height('100%').justifyContent(FlexAlign.Start).backgroundColor(BubuColor.background)
    } else if (this.route === 'capsule') {
      // 未来胶囊（对照 iOS CapsuleHomeView，收进魔法屋）
      Column() {
        this.subBackBar('未来胶囊')
        CapsuleView()
          .layoutWeight(1)
      }.width('100%').height('100%').justifyContent(FlexAlign.Start).backgroundColor(BubuColor.background)
    } else {
      this.homePage()
    }
  }

  // 子页返回栏（对照 iOS navigationTitle + 返回）。
  @Builder
  subBackBar(title: string) {
    Row({ space: 8 }) {
      Text('‹ 返回').fontSize(BubuFont.body).fontColor(BubuColor.primary)
        .onClick(() => { this.route = ''; this.tabBarVisible = true; })
      Blank()
      Text(title).fontSize(BubuFont.body).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Blank()
      Text('   ').fontSize(BubuFont.body)
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  @Builder
  homePage() {
    Scroll() {
      Column({ space: 18 }) {
        this.banner()
        this.askBubuCard()
        this.storybookCard()
        this.capsuleCard()

        this.sectionHeader('回顾', '把已经发生的整理给你看')
        this.tileGrid(REVIEW_TILES)
        this.sectionHeader('创作', '把素材改写成新的东西')
        this.tileGrid(CREATION_TILES)
        this.sectionHeader('声音', '听见布布慢慢长大')
        this.tileGrid(SOUND_TILES)
	        Blank().height(130)
	      }
      .padding(16)
      .width('100%')
    }
	    .backgroundColor(BubuColor.background)
	    .width('100%')
	    .height('100%')
	    .onAreaChange((_old: Area, area: Area) => {
	      const w = area.width as number;
	      if (w > 0) this.viewportW = w;
	    })
	  }

  // 魔法屋主位：家庭记忆问答比普通磁贴更像整个页面的入口。
  @Builder
  askBubuCard() {
    Row({ space: 14 }) {
      BubuIconBadge({
        name: BubuIconName.textBubble,
        badgeSize: 60,
        iconSize: 28,
        color: '#FFFFFF',
        fill: BubuColor.primary,
        radius: 18,
        strokeWidth: 2.5
      })
      Column({ space: 4 }) {
        Text('问问布布')
          .fontSize(18)
          .fontWeight(FontWeight.Bolder)
          .fontColor(BubuColor.warmBrown)
        Text('她这几年的记录，都可以直接问')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(BubuColor.secondaryText)
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›').fontSize(18).fontWeight(FontWeight.Bolder).fontColor(BubuColor.secondaryText)
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#F2FFFFFF')
    .borderRadius(24)
    .border({ width: 1, color: '#99FFFFFF' })
    .shadow({ radius: 12, color: '#38DCC9FF', offsetY: 6 })
    .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.97 })
    .accessibilityText('问问布布，她这几年的记录都可以直接问')
    .onClick(() => { this.tabBarVisible = false; this.route = 'qa'; })
  }

  // 顶部 banner（对照 iOS banner：主色渐变 + 布布画画表情）。
  @Builder
  banner() {
    Row({ space: 12 }) {
	      BubuMascotBadge({ badgeSize: this.isCompact() ? 48 : 58, expression: BubuExpression.drawing })
      Column({ space: 4 }) {
        Text('布布的魔法屋')
	          .fontSize(this.isCompact() ? 23 : BubuFont.title)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
        Text('故事、电影、报告和未来胶囊')
          .fontSize(BubuFont.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
	    .padding(this.isCompact() ? 16 : 20)
    .linearGradient({
      angle: 135,
      colors: [[this.theme, 0.0], ['#BFF28C9E', 1.0]]
    })
    .borderRadius(BubuRadius.card)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
  }

  // 成长绘本主卡（butter→peach→pink；对照 iOS storybookCard）。
  // 点击后进入真实成长绘本阅读器。
  @Builder
  storybookCard() {
    Row({ space: 14 }) {
      // iOS BubuDreamPhoto 梦境照片占位，此处简化为渐变方块 + 装饰符号。
      Stack() {
        Text('✦').fontSize(26).fontColor('#FFFFFF')
      }
      .width(60)
      .height(72)
      .linearGradient({ angle: 135, colors: [[BubuColor.peach, 0.0], [BubuColor.pink, 1.0]] })
      .borderRadius(16)
      .border({ width: 3, color: '#FFFFFF' })
      .rotate({ angle: -4 })
      .shadow({ radius: 6, color: '#29000000', offsetY: 3 })

      Column({ space: 4 }) {
        Text('成长绘本')
          .fontSize(19)
          .fontWeight(FontWeight.Bolder)
          .fontColor('#FFFFFF')
        Text('由你记录的点滴，自动编织成可翻页的故事')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F2FFFFFF')
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
    }
    .width('100%')
    .padding(18)
    .linearGradient({
      angle: 135,
      colors: [[BubuColor.butter, 0.0], [BubuColor.peach, 0.5], [BubuColor.pink, 1.0]]
    })
    .borderRadius(BubuRadius.card)
    .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
    .onClick(() => { this.tabBarVisible = false; this.route = 'story'; })
  }

  // 未来胶囊卡（lav→sky 信封；对照 iOS capsuleCard）。
  // 点击后进入未来胶囊真实列表、创建与恢复流程。
  @Builder
  capsuleCard() {
    Row({ space: 14 }) {
      Stack() {
        BubuIconBadge({
          name: BubuIconName.send,
          badgeSize: 54,
          iconSize: 25,
          color: '#FFFFFF',
          fill: '#00000000',
          radius: 17,
          strokeWidth: 2.4
        })
      }
      .width(60)
      .height(60)
      .linearGradient({ angle: 135, colors: [[BubuColor.lav, 0.0], [BubuColor.sky, 1.0]] })
      .borderRadius(18)
      .border({ width: 2, color: '#B3FFFFFF' })
      .shadow({ radius: 10, color: '#59DCC9FF', offsetY: 5 })

      Column({ space: 4 }) {
        Text('未来胶囊')
          .fontSize(17)
          .fontWeight(FontWeight.Bolder)
          .fontColor(BubuColor.warmBrown)
        Text('把今天的话，寄给未来的布布')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(BubuColor.secondaryText)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›').fontSize(15).fontWeight(FontWeight.Bolder).fontColor(BubuColor.secondaryText)
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#F2FFFFFF')
    .borderRadius(24)
    .border({ width: 1, color: '#99FFFFFF' })
    .shadow({ radius: 12, color: '#38DCC9FF', offsetY: 6 })
    .onClick(() => { this.tabBarVisible = false; this.route = 'capsule'; })
  }

  @Builder
  sectionHeader(title: string, subtitle: string) {
    Column({ space: 2 }) {
      Text(title).fontSize(15).fontWeight(FontWeight.Bolder).fontColor(BubuColor.warmBrown)
      Text(subtitle).fontSize(12).fontColor(BubuColor.secondaryText)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ left: 6 })
  }

  // 手机端固定两列；奇数项最后一行保留一个空位，维持清晰分区。
  @Builder
  tileGrid(tiles: CapabilityTile[]) {
	    if (this.isNarrow()) {
	      Column({ space: 10 }) {
	        ForEach(tiles, (tile: CapabilityTile) => { this.capabilityTile(tile) }, (tile: CapabilityTile) => tile.route)
	      }
	      .width('100%')
	    } else {
	      Column({ space: 10 }) {
	        ForEach(this.tileRows(tiles), (row: CapabilityTile[]) => {
          Row({ space: 10 }) {
            this.capabilityTile(row[0])
            if (row.length > 1) {
              this.capabilityTile(row[1])
            } else {
              Blank().layoutWeight(1)
            }
          }.width('100%')
        }, (row: CapabilityTile[]) => row[0].route)
	      }
	      .width('100%')
	    }
	  }

  private tileRows(tiles: CapabilityTile[]): CapabilityTile[][] {
    const rows: CapabilityTile[][] = [];
    for (let i = 0; i < tiles.length; i += 2) rows.push(tiles.slice(i, i + 2));
    return rows;
  }

  // 单块创作能力磁贴（对照 iOS capabilityTile：图标徽 + 标题 + 副标题，渐变卡）。
  @Builder
  capabilityTile(tile: CapabilityTile) {
    Column({ space: 8 }) {
      Row() {
        BubuIconBadge({
          name: tile.iconName,
          badgeSize: 40,
          iconSize: 20,
          color: BubuColor.deepRose,
          fill: tile.tint,
          radius: 15,
          strokeWidth: 2.1,
          filled: tile.iconName === BubuIconName.sparkles
        })
          .opacity(0.82)
        Blank()
        Text('›').fontSize(13).fontWeight(FontWeight.Bolder).fontColor(BubuColor.secondaryText).opacity(0.72)
      }
      .width('100%')

      Blank()

      Text(tile.title)
        .fontSize(15)
        .fontWeight(FontWeight.Bolder)
        .fontColor(BubuColor.warmBrown)
        .maxLines(1)
      Text(tile.subtitle)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(BubuColor.secondaryText)
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
	    .height(this.isCompact() ? 116 : 126)
    .padding({ left: 14, right: 14, top: 13, bottom: 14 })
    .linearGradient({
      angle: 135,
      colors: [['#FAFFFFFF', 0.0], [tile.tint, 1.0]]
    })
    .borderRadius(24)
    .border({ width: 1, color: '#9EFFFFFF' })
    .shadow({ radius: 12, color: '#38B57870', offsetY: 7 })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => { this.tabBarVisible = false; this.route = tile.route; })
  }
}
