import { BubuColor } from '../theme/BubuTheme';

// MARK: - 通用「即将到来」占位（对照 iOS DesignSystem/Components/ComingSoonView.swift）
// 用于尚未深入的灵魂功能模块，保持温暖、不冷场。
// iOS systemImage（SF Symbol）在 HarmonyOS 无对应位图，统一降级为 emoji 字符（icon 参数传 emoji）。
@Component
export struct ComingSoonView {
  @Require @Prop title: string;
  // NOTE: iOS 用 SF Symbol 名；ArkUI 无 SF Symbol，改用 emoji 占位字符（如 '✨'）。
  @Prop icon: string = '✨';
  @Require @Prop message: string;

  build() {
    // iOS: ZStack { background + 居中 VStack }
    Stack() {
      Column({ space: 18 }) {
        Text(this.icon)
          .fontSize(60)
          .opacity(0.75)
        Text(this.title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text(this.message)
          .fontSize(15)
          .fontColor(BubuColor.secondaryText)
          .textAlign(TextAlign.Center)
      }
      .padding(40)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BubuColor.cream)
  }
}
