// MARK: - 主题与外观（对照 iOS Features/Settings/ThemeSettingsView.swift）
// 切换全局主题配色（马卡龙色卡网格），选择首页背景模式（主题背景 / 布布照片）。
// iOS 用 LazyVGrid 两列 + segmented Picker；ArkUI 用 Grid 两列 + 自绘分段控件。

import { BubuColor, BubuFont, BubuRadius, BubuSpacing } from '../theme/BubuTheme';
import { ThemeManager, BubuThemeDefinition, HeroBackgroundMode } from '../theme/ThemeManager';
import { promptAction } from '@kit.ArkUI';

@Component
export struct ThemeSettingsView {
  // @Observed 单例，主题切换后驱动重绘。
  @State private manager: ThemeManager = ThemeManager.shared;
  // 用一个本地计数触发 UI 刷新（select / heroMode 改的是单例字段）。
  @State private tick: number = 0;
  @State private heroIndex: number = 0; // 0 主题背景 / 1 布布照片

  aboutToAppear(): void {
    this.heroIndex = this.manager.heroMode === HeroBackgroundMode.photo ? 1 : 0;
  }

  build() {
    Scroll() {
      Column({ space: BubuSpacing.section }) {
        Text('主题配色')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
          .width('100%')

        Grid() {
          ForEach(BubuThemeDefinition.all, (theme: BubuThemeDefinition) => {
            GridItem() {
              this.themeCard(theme)
            }
          }, (theme: BubuThemeDefinition) => theme.id)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(14)
        .rowsGap(14)
        .width('100%')
        .height(BubuThemeDefinition.all.length / 2 * 168)

        Text('首页背景')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
          .width('100%')
          .margin({ top: 8 })

        // 分段控件（对照 iOS .pickerStyle(.segmented)）。
        Row() {
          this.segment('主题背景', 0)
          this.segment('布布照片', 1)
        }
        .width('100%')
        .padding(3)
        .backgroundColor(BubuColor.softFill)
        .borderRadius(10)

        Text('「布布照片」需在「布布的档案」里设置一张背景图。')
          .fontSize(BubuFont.caption)
          .fontColor(BubuColor.secondaryText)
          .width('100%')
      }
      .padding(16)
      .width('100%')
    }
    .backgroundColor(BubuColor.background)
    .width('100%')
    .height('100%')
  }

  @Builder
  segment(title: string, idx: number) {
    Text(title)
      .fontSize(BubuFont.caption)
      .fontColor(this.heroIndex === idx ? BubuColor.warmBrown : BubuColor.secondaryText)
      .fontWeight(this.heroIndex === idx ? FontWeight.Medium : FontWeight.Regular)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 8, bottom: 8 })
      .backgroundColor(this.heroIndex === idx ? BubuColor.card : Color.Transparent)
      .borderRadius(8)
      .onClick(() => {
        this.heroIndex = idx;
        this.manager.heroMode = idx === 1 ? HeroBackgroundMode.photo : HeroBackgroundMode.theme;
      })
  }

  // 主题卡：迷你首页实景预览（mesh 渐变底 + 头像圈 + 强调按钮 + 时光轴卡片缩影）+ 名字。
  @Builder
  themeCard(theme: BubuThemeDefinition) {
    Column({ space: 10 }) {
      this.previewSwatch(theme)
      Row({ space: 6 }) {
        if (theme.id === this.manager.currentThemeId && this.tick >= 0) {
          Text('✓').fontSize(15).fontColor(theme.primary)
        }
        Text(theme.name)
          .fontSize(BubuFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(BubuColor.warmBrown)
      }
    }
    .padding(12)
    .width('100%')
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.card)
    .border({
      width: theme.id === this.manager.currentThemeId ? 2.5 : 0,
      color: theme.primary
    })
    .shadow({ radius: 14, color: '#33B57870', offsetY: 8 })
    .onClick(() => {
      this.manager.select(theme);
      this.tick += 1;
      promptAction.showToast({ message: `已切换到「${theme.name}」` });
    })
  }

  // mesh 调色板做静态斜向渐变近似 hero 观感 + 头像圈 + 胶囊按钮 + 时光轴卡片缩影。
  @Builder
  previewSwatch(theme: BubuThemeDefinition) {
    Stack() {
      // mesh 渐变底。
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 135,
          colors: this.meshColors(theme)
        })
      Column({ space: 6 }) {
        // 头像圈（强调渐变）。
        Stack()
          .width(22)
          .height(22)
          .borderRadius(11)
          .linearGradient({ angle: 135, colors: theme.accentGradientColors })
          .border({ width: 1.5, color: '#CCFFFFFF' })
        // 胶囊主色按钮缩影。
        Column()
          .width(34)
          .height(7)
          .borderRadius(4)
          .backgroundColor(theme.primary)
        // 时光轴卡片缩影。
        Row({ space: 4 }) {
          Column().width(16).height(14).borderRadius(3).backgroundColor(theme.secondary)
          Column({ space: 3 }) {
            Column().width(30).height(4).borderRadius(2).backgroundColor(theme.surfaceTint).opacity(0.5)
            Column().width(22).height(4).borderRadius(2).backgroundColor(theme.surfaceTint).opacity(0.3)
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width(78)
        .height(22)
        .padding({ left: 5 })
        .backgroundColor(BubuColor.card)
        .borderRadius(6)
      }
    }
    .alignContent(Alignment.Center)
    .width('100%')
    .height(96)
    .borderRadius(BubuRadius.small)
    .clip(true)
  }

  // meshPalette → linearGradient colors（等距分布）。
  private meshColors(theme: BubuThemeDefinition): Array<[ResourceColor, number]> {
    const palette = theme.meshPalette.length > 0 ? theme.meshPalette : [theme.primary];
    const out: Array<[ResourceColor, number]> = [];
    const n = palette.length;
    for (let i = 0; i < n; i++) {
      out.push([palette[i], n === 1 ? 0 : i / (n - 1)]);
    }
    return out;
  }
}
