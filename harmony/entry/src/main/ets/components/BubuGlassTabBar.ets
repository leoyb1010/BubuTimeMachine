// MARK: - 奶油马卡龙玻璃胶囊底栏（对照 iOS DesignSystem/BubuGlassTabBar.swift）
// 替换系统 TabBar 的视觉外观，路由逻辑由外部 selection 驱动，不改任何跳转。
// 4 个页面 Tab + 1 个中央记录动作（打开「记录此刻」）。
// SwiftUI .ultraThinMaterial Capsule → ArkUI backgroundBlurStyle + 大圆角胶囊。

import { BubuColor, BubuGradient } from '../theme/BubuTheme';
import { BubuMotion } from '../theme/BubuMotion';
import { BubuHaptics } from '../theme/BubuHaptics';
import { BubuIcon, BubuIconName } from './BubuIcon';

// 单个 Tab 项（对照 iOS BubuTabItem）。
export class BubuTabItem {
  id: number;
  title: string;
  iconName: string;

  constructor(id: number, title: string, iconName: string) {
    this.id = id;
    this.title = title;
    this.iconName = iconName;
  }
}

@Component
export struct BubuGlassTabBar {
  @Link selection: number;
  tint: string = BubuColor.primary;
  @Prop compact: boolean = false;
  /// 中央凸起键动作：打开「记录此刻」输入流。
  onCenterTap: () => void = () => {};
  @State private centerBreath: boolean = false;
  @StorageLink('bubuTabBarVisible') tabBarVisible: boolean = true;

  aboutToAppear(): void {
    animateTo(BubuMotion.breathe, () => { this.centerBreath = true; });
  }

  // 四个页面入口（胶囊收进魔法屋，底栏不再拥挤）。
  private readonly left: BubuTabItem[] = [
    new BubuTabItem(0, '首页', BubuIconName.home),
    new BubuTabItem(1, '时光', BubuIconName.clock),
  ];
  private readonly right: BubuTabItem[] = [
    new BubuTabItem(2, '里程碑', BubuIconName.star),
    new BubuTabItem(3, '魔法屋', BubuIconName.magic),
  ];

  build() {
    Row({ space: 2 }) {
      ForEach(this.left, (item: BubuTabItem) => { this.tabButton(item); }, (it: BubuTabItem) => it.id.toString())
      this.centerButton()
      ForEach(this.right, (item: BubuTabItem) => { this.tabButton(item); }, (it: BubuTabItem) => it.id.toString())
    }
    .height(this.compact ? 68 : 78)
    .padding({ left: this.compact ? 7 : 10, right: this.compact ? 7 : 10, top: this.compact ? 7 : 10, bottom: this.compact ? 7 : 10 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#8AFFFFFF')
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(40)
    .border({ width: 1, color: '#9EFFFFFF' })   // white opacity 0.62
    .shadow({ radius: this.compact ? 14 : 18, color: '#47E15C86', offsetY: this.compact ? 7 : 10 })  // deepRose opacity 0.28
    .margin({ left: this.compact ? 8 : 14, right: this.compact ? 8 : 14, bottom: this.compact ? 2 : 6 })
  }

  @Builder
  private tabButton(item: BubuTabItem) {
    Column({ space: 4 }) {
      BubuIcon({
        name: item.iconName,
        iconSize: this.compact ? 18 : 20,
        color: this.selection === item.id ? this.tint : BubuColor.secondaryText,
        strokeWidth: 2.2,
        filled: this.selection === item.id && item.iconName === BubuIconName.star
      })
      Text(item.title)
        .fontSize(this.compact ? 8.5 : 10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.selection === item.id ? this.tint : BubuColor.secondaryText)
    }
    .width(this.compact ? 46 : 58)
    .height(this.compact ? 46 : 52)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#00000000')
    .borderRadius(this.compact ? 14 : 16)
    .animation(BubuMotion.quick)
    .onClick(() => {
      BubuHaptics.selection();
      this.tabBarVisible = true;
      animateTo(BubuMotion.quick, () => { this.selection = item.id; });
    })
  }

  @Builder
  private centerButton() {
    Column({ space: 1 }) {
      BubuIcon({
        name: BubuIconName.plus,
        iconSize: this.compact ? 23 : 26,
        color: '#FFFFFF',
        strokeWidth: 3.2
      })
      Text('记录').fontSize(this.compact ? 7.5 : 9).fontWeight(FontWeight.Bolder).fontColor('#FFFFFF')
    }
    .width(this.compact ? 54 : 60)
    .height(this.compact ? 54 : 60)
    .justifyContent(FlexAlign.Center)
    .linearGradient({
      angle: BubuGradient.angleTopLeadingToBottomTrailing,
      colors: BubuGradient.primaryButtonColors
    })
    .borderRadius(this.compact ? 27 : 30)
    .border({ width: 1.5, color: '#80FFFFFF' })   // white opacity 0.5
    .shadow({ radius: this.centerBreath ? 12 : 8, color: '#73E15C86', offsetY: 4 })
    .scale({ x: this.centerBreath ? 1.018 : 1, y: this.centerBreath ? 1.018 : 1 })
    .animation(BubuMotion.breathe)
    .margin({ left: this.compact ? 2 : 3, right: this.compact ? 2 : 3 })
    .onClick(() => {
      BubuHaptics.tapLight();
      animateTo(BubuMotion.quick, () => { this.onCenterTap(); });
    })
  }
}
