// MARK: - 仪式动画（对照 iOS DesignSystem/CeremonyAnimation.swift）
// 里程碑 / 人生第一次完成时的温暖仪式感。轻量、温柔，不喧宾夺主。
// SwiftUI ZStack + spring 入场 + sparkleRing → ArkUI Stack + animateTo + 放射星点。
// NOTE: iOS 用 BubuMascotBadge（吉祥物徽章）；该组件由另一组维护（Components/），
//       此处用 emoji 占位，接入后可替换为真正的吉祥物组件。

import { BubuColor, BubuFont, BubuShadow } from '../theme/BubuTheme';
import { BubuHaptics } from '../theme/BubuHaptics';
import { rangeArray } from './MacaronComponents2';

@Component
export struct CeremonyAnimation {
  title: string = '';
  subtitle: string = '';
  onDismiss: () => void = () => {};
  reduceMotion: boolean = false;
  @State private appear: boolean = false;
  @State private sparkle: boolean = false;

  aboutToAppear(): void {
    BubuHaptics.success();
    if (this.reduceMotion) { this.appear = true; return; }
    // 卡片弹入（对照 spring(0.48,0.72)）。
    animateTo({ duration: 480, curve: Curve.Friction }, () => { this.appear = true; });
    // 星点放射淡出（对照 easeOut 1.1s，delay 0.18）。
    setTimeout(() => {
      animateTo({ duration: 1100, curve: Curve.EaseOut }, () => { this.sparkle = true; });
    }, 180);
  }

  build() {
    Stack() {
      // 庆祝背景：渐变 + 半透明覆盖（点击关闭）。
      this.celebrationBackground()

      // 弹层卡片
      Column({ space: 18 }) {
        // 吉祥物 + 星环
        Stack() {
          if (!this.reduceMotion) {
            this.sparkleRing()
          }
          Text('🎉')
            .fontSize(72)
            .scale({ x: this.appear ? 1 : 0.64, y: this.appear ? 1 : 0.64 })
        }
        .width(120)
        .height(120)

        Text(this.title.replace('🎉 ', ''))
          .fontSize(BubuFont.title)
          .fontWeight(FontWeight.Bolder)
          .fontColor(BubuColor.warmBrown)
          .textAlign(TextAlign.Center)

        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(BubuFont.body)
            .fontColor(BubuColor.secondaryText)
            .textAlign(TextAlign.Center)
        }

        // 关闭按钮（胶囊）
        Text('收好这一刻')
          .fontSize(BubuFont.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .padding({ left: 26, right: 26, top: 12, bottom: 12 })
          .backgroundColor(BubuColor.primary)
          .borderRadius(24)
          .margin({ top: 4 })
          .onClick(() => { this.onDismiss(); })
      }
      .padding({ left: 26, right: 26, top: 30, bottom: 30 })
      .constraintSize({ maxWidth: 340 })
      .borderRadius(32)
      .backgroundBlurStyle(BlurStyle.Regular)
      .border({ width: 1, color: '#76FFFFFF' })
      .shadow({ radius: 24, color: BubuShadow.cardColor, offsetY: 12 })
      .scale({ x: this.appear ? 1 : 0.86, y: this.appear ? 1 : 0.86 })
      .opacity(this.appear ? 1 : 0)
      .margin(24)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private celebrationBackground() {
    Stack() {
      Column()
        .width('100%').height('100%')
        .linearGradient({
          angle: 135,
          colors: [
            [BubuColor.background, 0.0],
            ['#29F28C9E', 0.5],   // primary opacity 0.16 近似
            [BubuColor.card, 1.0]
          ]
        })
      // 半透明覆盖（点击关闭）
      Column()
        .width('100%').height('100%')
        .backgroundColor('#33FFFFFF')
        .onClick(() => { this.onDismiss(); })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private sparkleRing() {
    Stack() {
      ForEach(rangeArray(10), (i: number) => {
        Text(i % 2 === 0 ? '✦' : '★')
          .fontSize(i % 2 === 0 ? 15 : 10)
          .fontColor('#D1F28C9E')   // primary opacity 0.82
          .translate({ x: 0, y: this.sparkle ? -78 : -38 })
          .rotate({ angle: (i / 10) * 360 })
          .opacity(this.sparkle ? 0 : 1)
      }, (i: number) => i.toString())
    }
  }
}
