import { BubuColor, BubuFont, BubuRadius, BubuShadow, bubuCardCol } from '../theme/BubuTheme';
import { BubuMascotBadge } from '../components/BubuMascotBadge';
import { BubuExpression } from '../theme/BubuExpression';
import { FirstPersonDiaryView } from './FirstPersonDiaryView';
import { GrowthMovieView } from './GrowthMovieView';
import { FamilyEnsembleView } from './FamilyEnsembleView';
import { GrowthReportView } from './GrowthReportView';

// MARK: - 布布的魔法屋（对照 iOS Features/AIStudio/AIStudioHomeView.swift）
// 自托管 AI 的创作中心：成长绘本 / 未来胶囊 / 第一人称日记 / 成长电影 / 家人合奏 / 成长报告。
// RootPage 把本组件直接作为「故事」Tab 渲染（无 NavPathStack），故内部用 @State route 就地切换子页。

// 魔法屋四块创作能力（对照 iOS creativeGrid 的 capabilityTile）。
interface CapabilityTile {
  icon: string;       // iOS 用 SF Symbol；此处 emoji 兜底
  title: string;
  subtitle: string;
  tint: string;       // 背景渐变副色
  route: string;      // diary / movie / ensemble / report
}

const CAPABILITY_TILES: CapabilityTile[] = [
  { icon: '💬', title: '第一人称日记', subtitle: '改写成布布的话', tint: BubuColor.pink, route: 'diary' },
  { icon: '🎞️', title: '成长电影', subtitle: '精选照片成短片', tint: BubuColor.sky, route: 'movie' },
  { icon: '👨‍👩‍👧', title: '家人合奏', subtitle: '合成完整故事', tint: BubuColor.mint, route: 'ensemble' },
  { icon: '📈', title: '成长报告', subtitle: '整理成长变化', tint: BubuColor.butter, route: 'report' }
];

@Component
export struct AIStudioView {
  // 当前子页路由（空 = 魔法屋首页）。对照 iOS NavigationLink 的目的地。
  @State private route: string = '';
  // 主题主色（对照 iOS env.theme.theme.primary）。
  private theme: string = BubuColor.primary;

  build() {
    if (this.route === 'diary') {
      FirstPersonDiaryView({ onBack: (): void => { this.route = ''; } })
    } else if (this.route === 'movie') {
      GrowthMovieView({ onBack: (): void => { this.route = ''; } })
    } else if (this.route === 'ensemble') {
      FamilyEnsembleView({ onBack: (): void => { this.route = ''; } })
    } else if (this.route === 'report') {
      GrowthReportView({ onBack: (): void => { this.route = ''; } })
    } else {
      this.homePage()
    }
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
      }
      .padding(16)
      .width('100%')
    }
    .backgroundColor(BubuColor.background)
    .width('100%')
    .height('100%')
  }

  // 顶部 banner（对照 iOS banner：主色渐变 + 布布画画表情）。
  @Builder
  banner() {
    Row({ space: 12 }) {
      BubuMascotBadge({ badgeSize: 58, expression: BubuExpression.drawing })
      Column({ space: 4 }) {
        Text('布布的魔法屋')
          .fontSize(BubuFont.title)
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
    .padding(20)
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
  }

  // 未来胶囊卡（lav→sky 信封；对照 iOS capsuleCard）。
  // NOTE: iOS 点进 CapsuleHomeView，本 App 的胶囊 Tab 已单列（RootPage 第 5 个 Tab），此处作视觉占位无跳转。
  @Builder
  capsuleCard() {
    Row({ space: 14 }) {
      Stack() {
        Text('✉️').fontSize(26)
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
  }

  // 创作能力 2×2 宫格（对照 iOS creativeGrid 的 LazyVGrid）。
  @Builder
  creativeGrid() {
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

  // 单块创作能力磁贴（对照 iOS capabilityTile：图标徽 + 标题 + 副标题，渐变卡）。
  @Builder
  capabilityTile(tile: CapabilityTile) {
    Column({ space: 8 }) {
      Row() {
        Stack() {
          Text(tile.icon).fontSize(17)
        }
        .width(36)
        .height(36)
        .backgroundColor(tile.tint)
        .opacity(0.72)
        .borderRadius(13)
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
    .height(112)
    .padding(13)
    .linearGradient({
      angle: 135,
      colors: [['#FAFFFFFF', 0.0], [tile.tint, 1.0]]
    })
    .borderRadius(24)
    .border({ width: 1, color: '#9EFFFFFF' })
    .shadow({ radius: 12, color: '#38B57870', offsetY: 7 })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => { this.route = tile.route; })
  }
}
