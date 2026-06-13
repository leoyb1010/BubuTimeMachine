import { ChildProfile } from '../models/Models';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor, BubuRadius } from '../theme/BubuTheme';

// MARK: - 布布身份卡（对照 iOS BubuIdentityCard）
// 学生证/工作证风格：头像位 + 名字 + 年龄/天数/生日 chip。
@Component
export struct IdentityCard {
  @Prop profile: ChildProfile;

  private get ageText(): string {
    return AgeCalculator.ageDescription(this.profile.birthday, Date.now());
  }
  private get daysText(): string {
    return `第 ${AgeCalculator.daysSinceBirth(this.profile.birthday)} 天`;
  }
  private get birthdayText(): string {
    const d = new Date(this.profile.birthday);
    return `${d.getFullYear()}.${d.getMonth() + 1}.${d.getDate()}`;
  }

  build() {
    Column() {
      Row() {
        Text('BUBU IDENTITY')
          .fontSize(10).fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.primary)
        Blank()
        Text('ACTIVE')
          .fontSize(10).fontWeight(FontWeight.Bold).fontColor(Color.White)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(BubuColor.primary)
          .borderRadius(10)
      }
      .width('100%')

      Text(this.profile.name)
        .fontSize(27).fontWeight(FontWeight.Bolder)
        .fontColor(BubuColor.warmBrown)
        .margin({ top: 6 })
        .alignSelf(ItemAlign.Start)

      // 信息 chip 行
      Row({ space: 8 }) {
        this.chip('AGE', this.ageText)
        this.chip('DAY', this.daysText)
      }
      .width('100%').margin({ top: 12 })

      Row({ space: 8 }) {
        this.chip('BIRTH', this.birthdayText)
        this.chip('FROM', this.profile.birthPlace && this.profile.birthPlace.length > 0 ? this.profile.birthPlace! : '地球小站')
      }
      .width('100%').margin({ top: 8 })
    }
    .padding(16)
    .width('100%')
    .backgroundColor(BubuColor.card)
    .borderRadius(28)
    .shadow({ radius: 12, color: '#1A000000', offsetY: 4 })
  }

  @Builder
  chip(title: string, value: string) {
    Column() {
      Text(title).fontSize(9).fontWeight(FontWeight.Bold).fontColor(BubuColor.primary)
      Text(value).fontSize(13).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor('#61FFFFFF')
    .borderRadius(12)
  }
}
