// MARK: - 奶油马卡龙玻璃胶囊底栏（对照 iOS DesignSystem/BubuGlassTabBar.swift）
// 替换系统 TabBar 的视觉外观，路由逻辑由外部 selection 驱动，不改任何跳转。
// 4 个页面 Tab + 1 个中央记录动作（打开「记录此刻」）。
// SwiftUI .ultraThinMaterial Capsule → ArkUI backgroundBlurStyle + 大圆角胶囊。

import { BubuColor, BubuGradient } from '../theme/BubuTheme';

// 单个 Tab 项（对照 iOS BubuTabItem）。
export class BubuTabItem {
  id: number;
  title: string;
  iconText: string;   // iOS 用 SF Symbol；此处用字符/emoji 占位

  constructor(id: number, title: string, iconText: string) {
    this.id = id;
    this.title = title;
    this.iconText = iconText;
  }
}

@Component
export struct BubuGlassTabBar {
  @Link selection: number;
  tint: string = BubuColor.primary;
  /// 中央凸起键动作：打开「记录此刻」输入流。
  onCenterTap: () => void = () => {};

  // 四个页面入口（胶囊收进魔法屋，底栏不再拥挤）。
  private readonly left: BubuTabItem[] = [
    new BubuTabItem(0, '首页', '🏠'),
    new BubuTabItem(1, '时光', '🕐'),
  ];
  private readonly right: BubuTabItem[] = [
    new BubuTabItem(2, '星座', '⭐'),
    new BubuTabItem(3, '魔法屋', '🪄'),
  ];

  build() {
    Row({ space: 2 }) {
      ForEach(this.left, (item: BubuTabItem) => { this.tabButton(item); }, (it: BubuTabItem) => it.id.toString())
      this.centerButton()
      ForEach(this.right, (item: BubuTabItem) => { this.tabButton(item); }, (it: BubuTabItem) => it.id.toString())
    }
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(40)
    .border({ width: 1, color: '#9EFFFFFF' })   // white opacity 0.62
    .shadow({ radius: 18, color: '#47E15C86', offsetY: 10 })  // deepRose opacity 0.28
    .margin({ left: 14, right: 14, bottom: 6 })
  }

  @Builder
  private tabButton(item: BubuTabItem) {
    Column({ space: 3 }) {
      Text(item.iconText).fontSize(18)
      Text(item.title)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.selection === item.id ? this.tint : BubuColor.secondaryText)
    }
    .width(56)
    .height(50)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.selection === item.id ? '#C7FCEDE4' : '#00000000')  // cream2 opacity 0.78
    .borderRadius(16)
    .onClick(() => {
      animateTo({ duration: 320, curve: Curve.Friction }, () => { this.selection = item.id; });
    })
  }

  @Builder
  private centerButton() {
    Column({ space: 1 }) {
      Text('+').fontSize(23).fontWeight(FontWeight.Bolder).fontColor('#FFFFFF')
      Text('记录').fontSize(9).fontWeight(FontWeight.Bolder).fontColor('#FFFFFF')
    }
    .width(58)
    .height(58)
    .justifyContent(FlexAlign.Center)
    .linearGradient({
      angle: BubuGradient.angleTopLeadingToBottomTrailing,
      colors: BubuGradient.primaryButtonColors
    })
    .borderRadius(29)
    .border({ width: 1.5, color: '#80FFFFFF' })   // white opacity 0.5
    .shadow({ radius: 10, color: '#80E15C86', offsetY: 4 })  // deepRose opacity 0.5
    .translate({ x: 0, y: -9 })
    .margin({ left: 3, right: 3 })
    .onClick(() => { this.onCenterTap(); })
  }
}
