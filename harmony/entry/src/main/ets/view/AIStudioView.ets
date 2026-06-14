import { BubuColor, BubuFont, BubuRadius, BubuShadow, bubuCardCol } from '../theme/BubuTheme';
import { BubuMascotBadge } from '../components/BubuMascotBadge';
import { BubuExpression } from '../theme/BubuExpression';
import { FirstPersonDiaryView } from './FirstPersonDiaryView';
import { GrowthMovieView } from './GrowthMovieView';
import { FamilyEnsembleView } from './FamilyEnsembleView';
import { GrowthReportView } from './GrowthReportView';
import { BubuStoryView } from './BubuStoryView';
import { CapsuleView } from './CapsuleView';
import { BubuIconBadge, BubuIconName } from '../components/BubuIcon';

// MARK: - 布布的魔法屋（对照 iOS Features/AIStudio/AIStudioHomeView.swift）
// 自托管 AI 的创作中心：成长绘本 / 未来胶囊 / 第一人称日记 / 成长电影 / 家人合奏 / 成长报告。
// RootPage 把本组件直接作为「故事」Tab 渲染（无 NavPathStack），故内部用 @State route 就地切换子页。

// 魔法屋四块创作能力（对照 iOS creativeGrid 的 capabilityTile）。
interface CapabilityTile {
  iconName: string;
  title: string;
  subtitle: string;
  tint: string;       // 背景渐变副色
  route: string;      // diary / movie / ensemble / report
}

const CAPABILITY_TILES: CapabilityTile[] = [
  { iconName: BubuIconName.textBubble, title: '第一人称日记', subtitle: '改写成布布的话', tint: BubuColor.pink, route: 'diary' },
  { iconName: BubuIconName.video, title: '成长电影', subtitle: '精选照片成短片', tint: BubuColor.sky, route: 'movie' },
  { iconName: BubuIconName.home, title: '家人合奏', subtitle: '合成完整故事', tint: BubuColor.mint, route: 'ensemble' },
  { iconName: BubuIconName.sparkles, title: '成长报告', subtitle: '整理成长变化', tint: BubuColor.butter, route: 'report' }
];

@Component
export struct AIStudioView {
  // 当前子页路由（空 = 魔法屋首页）。对照 iOS NavigationLink 的目的地。
  @State private route: string = '';
  @State private viewportW: number = 0;
  @StorageLink('bubuTabBarVisible') tabBarVisible: boolean = true;
  @StorageLink('bubuBackSignal') @Watch('onBackSignal') backSignal: number = 0;
  // 主题主色（对照 iOS env.theme.theme.primary）。
  private theme: string = BubuColor.primary;

  aboutToAppear(): void {
    this.tabBarVisible = true;
  }

  private onBackSignal(): void {
    if (this.backSignal <= 0) return;
    if (this.route.length > 0) {
      this.route = '';
      this.tabBarVisible = true;
    }
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
        this.storybookCard()
        this.capsuleCard()

        // 「布布的魔法屋」分组标题（对照 iOS caption.semibold）。
	        Text('布布的魔法屋')
	          .fontSize(BubuFont.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor(BubuColor.secondaryText)
          .width('100%')
          .margin({ left: 6, top: 2 })
	
	        this.creativeGrid()
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
  // NOTE: iOS 点进 BubuStoryView（翻页绘本），不在本切片范围内，暂作占位无跳转。
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
  // NOTE: iOS 点进 CapsuleHomeView，本 App 的胶囊 Tab 已单列（RootPage 第 5 个 Tab），此处作视觉占位无跳转。
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

  // 创作能力 2×2 宫格（对照 iOS creativeGrid 的 LazyVGrid）。
  @Builder
	  creativeGrid() {
	    if (this.isNarrow()) {
	      Column({ space: 10 }) {
	        this.capabilityTile(CAPABILITY_TILES[0])
	        this.capabilityTile(CAPABILITY_TILES[1])
	        this.capabilityTile(CAPABILITY_TILES[2])
	        this.capabilityTile(CAPABILITY_TILES[3])
	      }
	      .width('100%')
	    } else {
	      Column({ space: 10 }) {
	        Row({ space: 10 }) {
	          this.capabilityTile(CAPABILITY_TILES[0])
	          this.capabilityTile(CAPABILITY_TILES[1])
	        }.width('100%')
	        Row({ space: 10 }) {
	          this.capabilityTile(CAPABILITY_TILES[2])
	          this.capabilityTile(CAPABILITY_TILES[3])
	        }.width('100%')
	      }
	      .width('100%')
	    }
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
