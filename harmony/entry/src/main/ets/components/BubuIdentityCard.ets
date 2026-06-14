import { ChildProfile } from '../models/Models';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor } from '../theme/BubuTheme';
import { BubuMascotBadge, BubuExpression } from './BubuMascotBadge';
import { MediaStore } from '../services/MediaStore';

// MARK: - 布布个人身份卡（对照 iOS DesignSystem/Components/BubuIdentityCard.swift）
// 「学生证/工作证」风格：头像 + 姓名 + 年龄/天数/生日 chip + 条码装饰；轻点翻面看背面（性别/血型/出生地/完整 ID）。
// iOS 用 rotation3DEffect 翻面 + 双层 opacity；ArkUI 用 .rotate(y) + 背面反向旋转 180° 保持文字正向。
// 本文件取代 view/IdentityCard.ets 的精简版（更完整：头像位 / ACTIVE / 条码 / cardNo / 生日月徽章 / FULL ID）。
@Component
export struct BubuIdentityCard {
  @Require @Prop profile: ChildProfile;
  // 翻面：轻点头像看背面，背面任意处轻点翻回。
  @State private flipped: boolean = false;

  // iOS: cardNo 固定文案
  private readonly cardNo: string = 'BUBU20240522';

  private birthdayMs(): number {
    const raw = this.profile.birthday;
    if (!Number.isFinite(raw) || raw <= 0) return Date.now();
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

  // 生日月：与 AppIconManager 同一规则（图标与卡片徽章联动）。
  private isBirthdayMonth(): boolean {
    return new Date().getMonth() === new Date(this.birthdayMs()).getMonth();
  }

  private avatarSrc(): string {
    const name = this.profile.avatarMediaFileName;
    if (name !== undefined && name.length > 0 && MediaStore.shared.exists(name)) {
      return `file://${MediaStore.shared.fullPath(name)}`;
    }
    return '';
  }

  private valueOr(v: string | undefined): string {
    return v !== undefined && v.length > 0 ? v : '未填写';
  }

  private flip(): void {
    // iOS withAnimation(BubuMotion.ceremony) —— 可打断 spring 翻面节奏。
    animateTo({ duration: 420, curve: Curve.EaseInOut }, () => {
      this.flipped = !this.flipped;
    });
  }

  build() {
    Stack() {
      // 正/背面叠放（iOS ZStack + opacity 切换；背面预旋 180°）。
      Stack() {
        Column() {
          this.frontFace()
        }
        .width('100%')
        .opacity(this.flipped ? 0 : 1)
        Column() {
          this.backFace()
        }
        .width('100%')
        .opacity(this.flipped ? 1 : 0)
      }
      .width('100%')

      // 右上角半透明圆点装饰（iOS overlay topTrailing Circle）。
      Circle()
        .width(96)
        .height(96)
        .fill('#2EFFFFFF')
        .offset({ x: 28, y: 36 })
    }
    .alignContent(Alignment.TopEnd)
    .width('100%')
    .clip(true)
    // 奶油马卡龙渐变（peach → pink → lav → white）。
    .linearGradient({
      angle: 135,
      colors: [['#8CF6C6A8', 0.0], ['#73F28C9E', 0.4], ['#73C9A8F2', 0.75], ['#4DFFFFFF', 1.0]]
    })
    .borderRadius(28)
    .border({ width: 1, color: '#73FFFFFF' })
    .shadow({ radius: 14, color: '#1F000000', offsetY: 5 })
    // Y 轴翻转（对照 iOS rotation3DEffect 翻面）。
    .rotate({ x: 0, y: 1, z: 0, angle: this.flipped ? 180 : 0, centerX: '50%', centerY: '50%' })
    .onClick(() => { this.flip(); })
  }

  // MARK: 正面
  @Builder
  frontFace() {
    Column() {
      this.clipBar()

      Row({ space: 10 }) {
        // 头像位（轻点翻面）。
        this.avatarBlock()

        Column({ space: 5 }) {
          Row() {
            Column({ space: 1 }) {
              Text('BUBU IDENTITY')
                .fontSize(9).fontWeight(FontWeight.Bold).fontColor('#B8F28C9E')
              Text(this.profile.name)
                .fontSize(23).fontWeight(FontWeight.Bolder).fontColor(BubuColor.warmBrown)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`中文名 · ${this.profile.name}`)
                .fontSize(10.5).fontWeight(FontWeight.Bold).fontColor('#CCF28C9E')
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text('ACTIVE')
              .fontSize(10).fontWeight(FontWeight.Bolder).fontColor(Color.White)
              .padding({ left: 8, right: 8, top: 5, bottom: 5 })
              .backgroundColor(BubuColor.primary).borderRadius(100)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          this.infoGrid()

          // 条码 + cardNo
          Row({ space: 8 }) {
            this.barcode()
            Column({ space: 2 }) {
              Text(`No.${this.cardNo}`)
                .fontSize(9.5).fontWeight(FontWeight.Bold).fontColor(BubuColor.secondaryText)
              Text('小小探险家 · 家庭认证')
                .fontSize(10.5).fontWeight(FontWeight.Medium).fontColor(BubuColor.primary)
            }
            .alignItems(HorizontalAlign.Start)
            Blank()
          }
          .width('100%')
          .margin({ top: 2 })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 12, right: 12, top: 8, bottom: 10 })
    }
    .width('100%')
  }

  @Builder
  clipBar() {
    Row() {
      // 挂绳孔胶囊
      Stack()
        .width(48).height(6)
        .backgroundColor('#A3FFFFFF').borderRadius(100)
        .shadow({ radius: 3, color: '#0D000000', offsetY: 1 })
      Blank()
      if (this.isBirthdayMonth()) {
        Row({ space: 4 }) {
          Text('🎂').fontSize(12)
          Text('生日月').fontSize(10).fontWeight(FontWeight.Bolder).fontColor(Color.White)
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(BubuColor.primary).borderRadius(100)
      } else {
        Text('✦').fontSize(13).fontWeight(FontWeight.Bold).fontColor(BubuColor.primary)
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 5 })
  }

  @Builder
  avatarBlock() {
    Stack() {
      Stack() {
        if (this.avatarSrc().length > 0) {
          Image(this.avatarSrc())
            .objectFit(ImageFit.Cover)
            .width('100%').height('100%')
        } else {
          BubuMascotBadge({ badgeSize: 82, expression: BubuExpression.happy })
        }
      }
      .width(90).height(96)
      .backgroundColor(BubuColor.cream)
      .borderRadius(22)
      .border({ width: 1, color: '#A6FFFFFF' })
      .clip(true)

      Text('布布')
        .fontSize(11).fontWeight(FontWeight.Bolder).fontColor(Color.White)
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .backgroundColor(BubuColor.primary).borderRadius(100)
        .offset({ x: 6, y: 6 })
    }
    .alignContent(Alignment.BottomEnd)
    .onClick(() => { this.flip(); })
  }

  @Builder
  infoGrid() {
    Column({ space: 5 }) {
      Row({ space: 6 }) {
        this.idChip('AGE', this.ageText())
        this.idChip('DAY', this.daysText())
      }.width('100%')
      Row({ space: 6 }) {
        this.idChip('BIRTH', this.birthdayText())
        this.idChip('FROM', this.profile.birthPlace !== undefined && this.profile.birthPlace.length > 0 ? this.profile.birthPlace : '地球小站')
      }.width('100%')
    }
    .width('100%')
  }

  @Builder
  idChip(title: string, value: string) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(9).fontWeight(FontWeight.Bolder).fontColor('#B3F28C9E')
      Text(value.length > 0 ? value : '未填写')
        .fontSize(11.5).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor('#61FFFFFF')
    .borderRadius(12)
  }

  @Builder
  barcode() {
    // iOS: 12 根高度 [10,15,8,13,17,9] 循环的竖条。
    Row({ space: 2 }) {
      ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], (idx: number) => {
        Stack()
          .width(idx % 4 === 0 ? 3 : 2)
          .height([10, 15, 8, 13, 17, 9][idx % 6])
          .backgroundColor(idx % 3 === 0 ? '#8C5C473D' : '#475C473D')
          .borderRadius(1)
      }, (idx: number) => idx.toString())
    }
    .alignItems(VerticalAlign.Bottom)
    .padding({ left: 7, right: 7, top: 5, bottom: 5 })
    .backgroundColor('#59FFFFFF')
    .borderRadius(10)
  }

  // MARK: 背面（轻点翻回）。整面反向旋转 180° 使文字正向。
  @Builder
  backFace() {
    Column({ space: 10 }) {
      Row() {
        Text('BUBU IDENTITY · 背面')
          .fontSize(10).fontWeight(FontWeight.Bold).fontColor('#B8F28C9E')
        Blank()
        Text('↩')
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(BubuColor.primary)
      }.width('100%')

      this.backRow('性别', this.valueOr(this.profile.gender))
      this.backRow('血型', this.valueOr(this.profile.bloodType))
      this.backRow('出生地', this.valueOr(this.profile.birthPlace))

      Column({ space: 2 }) {
        Text('FULL ID')
          .fontSize(9).fontWeight(FontWeight.Bolder).fontColor('#B3F28C9E')
        Text(this.profile.id)
          .fontSize(11).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor('#61FFFFFF')
      .borderRadius(12)

      Text('轻点卡片翻回正面')
        .fontSize(10).fontColor(BubuColor.secondaryText)
        .width('100%').textAlign(TextAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .rotate({ x: 0, y: 1, z: 0, angle: 180, centerX: '50%', centerY: '50%' })
  }

  @Builder
  backRow(title: string, value: string) {
    Row() {
      Text(title)
        .fontSize(11).fontWeight(FontWeight.Bold).fontColor('#B3F28C9E')
      Blank()
      Text(value)
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor('#61FFFFFF')
    .borderRadius(12)
  }
}
