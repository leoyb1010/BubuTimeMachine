import { ChildProfile } from '../models/Models';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor, BubuRadius } from '../theme/BubuTheme';

// MARK: - 布布身份卡（对照 iOS BubuIdentityCard）
// 学生证/工作证风格：头像位 + 名字 + 年龄/天数/生日 chip。
@Component
export struct IdentityCard {
  @Prop profile: ChildProfile;
  // 轻点翻面：正面年龄/天数，背面性别/血型/出生地（对照 iOS 身份卡背面）
  @State flipped: boolean = false;

  private flip(): void {
    animateTo({ duration: 420, curve: Curve.EaseInOut }, () => {
      this.flipped = !this.flipped;
    });
  }

  private birthdayMs(): number {
    const raw = this.profile.birthday;
    if (!Number.isFinite(raw) || raw <= 0) {
      return Date.now();
    }
    return raw;
  }

  private ageText(): string {
    return AgeCalculator.ageDescription(this.birthdayMs(), Date.now());
  }

  private daysText(): string {
    return `第 ${AgeCalculator.daysSinceBirth(this.birthdayMs())} 天`;
  }

  private birthdayText(): string {
    const d = new Date(this.birthdayMs());
    return `${d.getFullYear()}.${d.getMonth() + 1}.${d.getDate()}`;
  }

  build() {
    Column() {
      if (!this.flipped) {
        this.frontFace()
      } else {
        this.backFace()
      }
    }
    .padding(16)
    .width('100%')
    .linearGradient({
      angle: 135,
      colors: [['#FFFFFF', 0.0], ['#FFF1F3', 0.55], ['#FDE8EC', 1.0]]
    })
    .borderRadius(28)
    .border({ width: 1, color: '#33FFFFFF' })
    .shadow({ radius: 14, color: '#1F000000', offsetY: 5 })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    // Y 轴翻转动画：神似 iOS rotation3DEffect 翻面
    .rotate({ x: 0, y: 1, z: 0, angle: this.flipped ? 180 : 0, centerX: '50%', centerY: '50%' })
    .onClick(() => { this.flip(); })
  }

  @Builder
  frontFace() {
    Column() {
      Row() {
        Text('BUBU IDENTITY')
          .fontSize(10).fontWeight(FontWeight.Bold).fontColor(BubuColor.primary)
        Blank()
        Text('ACTIVE')
          .fontSize(10).fontWeight(FontWeight.Bold).fontColor(Color.White)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(BubuColor.primary).borderRadius(10)
      }.width('100%')

      Text(this.profile.name)
        .fontSize(27).fontWeight(FontWeight.Bolder).fontColor(BubuColor.warmBrown)
        .margin({ top: 6 }).alignSelf(ItemAlign.Start)

      Row({ space: 8 }) {
        this.chip('AGE', this.ageText())
        this.chip('DAY', this.daysText())
      }.width('100%').margin({ top: 12 })

      Row({ space: 8 }) {
        this.chip('BIRTH', this.birthdayText())
        this.chip('FROM', this.profile.birthPlace && this.profile.birthPlace.length > 0 ? this.profile.birthPlace! : '地球小站')
      }.width('100%').margin({ top: 8 })

      Text('轻点翻面看更多 ›').fontSize(10).fontColor(BubuColor.secondaryText)
        .alignSelf(ItemAlign.End).margin({ top: 8 })
    }
    .width('100%')
  }

  @Builder
  backFace() {
    // 背面内容反向旋转 180°，使翻过来后文字正向（对照 iOS 背面）
    Column({ space: 10 }) {
      Text('BUBU IDENTITY · 背面')
        .fontSize(10).fontWeight(FontWeight.Bold).fontColor(BubuColor.primary)
        .alignSelf(ItemAlign.Start)
      this.backRow('性别', this.valueOr(this.profile.gender))
      this.backRow('血型', this.valueOr(this.profile.bloodType))
      this.backRow('出生地', this.valueOr(this.profile.birthPlace))
      Text('轻点翻回正面').fontSize(10).fontColor(BubuColor.secondaryText)
        .alignSelf(ItemAlign.Center).margin({ top: 6 })
    }
    .width('100%')
    .rotate({ x: 0, y: 1, z: 0, angle: 180, centerX: '50%', centerY: '50%' })
  }

  @Builder
  backRow(title: string, value: string) {
    Row() {
      Text(title).fontSize(12).fontWeight(FontWeight.Bold).fontColor(BubuColor.primary)
      Blank()
      Text(value).fontSize(14).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
    }
    .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor('#61FFFFFF').borderRadius(12)
  }

  private valueOr(v: string | undefined): string {
    return v && v.length > 0 ? v : '未填写';
  }

  @Builder
  chip(title: string, value: string) {
    Row({ space: 8 }) {
      Text(title)
        .fontSize(9)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.primary)
        .width(42)
        .maxLines(1)
      Text(value.length > 0 ? value : '未填写')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(BubuColor.warmBrown)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(VerticalAlign.Center)
    .layoutWeight(1)
    .height(42)
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor('#61FFFFFF')
    .borderRadius(12)
  }
}
