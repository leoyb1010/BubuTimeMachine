import { util } from '@kit.ArkTS';
import { ChildProfile, FamilyMember } from '../models/Models';
import { SyncState, Relation, ALL_RELATIONS, relationDefaultEmoji, relationDefaultColorHex, FamilyRole } from '../models/Enums';
import { AppDatabase } from '../data/AppDatabase';
import { ServerConfig } from '../services/ServerConfig';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor, BubuRadius, BubuFont, BubuShadow } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';

// MARK: - 首次启动引导（对照 iOS Features/Onboarding/OnboardingView.swift）
// 温暖的开场：欢迎 → 设置布布生日 → 创建第一个家庭成员（你是谁）。
// 完成后写入 ChildProfile + FamilyMember，回调 onComplete 标记 onboarding 完成。
@Component
export struct OnboardingView {
  // 完成回调（对照 env.hasCompletedOnboarding = true）。
  onComplete?: () => void;

  @State private step: number = 0;
  @State private childName: string = '布布';
  // 默认 6 个月前（对照 Calendar.date(byAdding: .month, value: -6)）。
  @State private birthdayMs: number = Date.now() - 6 * 30 * 86400000;
  @State private selectedRelation: Relation = Relation.mama;
  @State private memberName: string = '';

  build() {
    Stack() {
      // 背景渐变（对照 backgroundGradient：primary 0.18 → secondary 0.12）。
      Column()
        .width('100%').height('100%')
        .linearGradient({
          angle: 180,
          colors: [['#2EF28C9E', 0.0], ['#1FFFC2D6', 1.0]]
        })

      Column() {
        this.progressDots()
        Blank()
        // 步骤内容（对照 switch step）。
        if (this.step === 0) {
          this.welcomeStep()
        } else if (this.step === 1) {
          this.birthdayStep()
        } else {
          this.memberStep()
        }
        Blank()
        this.primaryButton()
      }
      .width('100%')
      .height('100%')
      .padding(28)
    }
    .width('100%')
    .height('100%')
  }

  // 对照 progressDots
  @Builder
  progressDots() {
    Row({ space: 8 }) {
      ForEach([0, 1, 2], (i: number) => {
        Stack()
          .width(i === this.step ? 22 : 8)
          .height(8)
          .backgroundColor(i === this.step ? BubuColor.primary : '#40F28C9E')
          .borderRadius(4)
      }, (i: number) => `${i}`)
    }
    .padding({ top: 12 })
  }

  // MARK: Steps

  // 对照 welcomeStep
  @Builder
  welcomeStep() {
    Column({ space: 24 }) {
      // NOTE: iOS 用 Image("BubuLogo")；本切片未携带 logo 资源，用 emoji 兜底。
      Text('🐻')
        .fontSize(96)
        .width(112).height(112)
        .textAlign(TextAlign.Center)
        .backgroundColor(BubuColor.card)
        .borderRadius(28)
        .shadow({ radius: 16, color: '#4DF28C9E', offsetY: 8 })
      Column({ space: 12 }) {
        Text('欢迎来到布布时光机')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Text('为布布留住每一个值得记住的此刻，\n陪她长大，等她某天亲手翻开。')
          .fontSize(BubuFont.body)
          .fontColor(BubuColor.secondaryText)
          .textAlign(TextAlign.Center)
          .lineHeight(26)
      }
    }
    .alignItems(HorizontalAlign.Center)
  }

  // 对照 birthdayStep
  @Builder
  birthdayStep() {
    Column({ space: 22 }) {
      Text('👶').fontSize(64)
      Text('布布是哪天来到世界的？')
        .fontSize(BubuFont.title)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)

      Column({ space: 16 }) {
        Row() {
          Text('名字').fontSize(BubuFont.body).fontColor(BubuColor.secondaryText)
          Blank()
          TextInput({ text: this.childName, placeholder: '布布' })
            .fontSize(BubuFont.headline)
            .fontColor(BubuColor.warmBrown)
            .textAlign(TextAlign.End)
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .onChange((v: string) => { this.childName = v; })
        }
        .width('100%')

        Divider().color(BubuColor.hairline)

        Row() {
          Text('生日').fontSize(BubuFont.body).fontColor(BubuColor.secondaryText)
          Blank()
          Text(BubuDateFormat.longDate(new Date(this.birthdayMs)))
            .fontSize(BubuFont.body)
            .fontColor(BubuColor.primary)
            .onClick(() => { this.pickBirthday(); })
        }
        .width('100%')
      }
      .width('100%')
      .padding(20)
      .backgroundColor(BubuColor.card)
      .borderRadius(BubuRadius.card)
      .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })

      // 实时年龄预览（对照 AgeCalculator.ageDescription）。
      Text(`现在的布布：${AgeCalculator.ageDescription(this.birthdayMs, Date.now())}`)
        .fontSize(BubuFont.headline)
        .fontWeight(FontWeight.Medium)
        .fontColor(BubuColor.primary)
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }

  // 对照 memberStep
  @Builder
  memberStep() {
    Column({ space: 22 }) {
      Text(relationDefaultEmoji(this.selectedRelation)).fontSize(64)
      Text('你是布布的……')
        .fontSize(BubuFont.title)
        .fontWeight(FontWeight.Bold)
        .fontColor(BubuColor.warmBrown)

      // 关系选择（对照 LazyVGrid 4 列）。
      Grid() {
        ForEach(ALL_RELATIONS, (rel: Relation) => {
          GridItem() {
            Column({ space: 4 }) {
              Text(relationDefaultEmoji(rel)).fontSize(28)
              Text(rel).fontSize(13).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
            }
            .width('100%')
            .padding({ top: 10, bottom: 10 })
            .backgroundColor(this.selectedRelation === rel ? '#2EF28C9E' : BubuColor.softFill)
            .borderRadius(14)
            .border({ width: this.selectedRelation === rel ? 2 : 0, color: BubuColor.primary })
            .onClick(() => { this.selectedRelation = rel; })
          }
        }, (rel: Relation) => rel)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
      .height(Math.ceil(ALL_RELATIONS.length / 4) * 78)

      TextInput({ text: this.memberName, placeholder: '也可以填你的名字（选填）' })
        .fontSize(BubuFont.body)
        .textAlign(TextAlign.Center)
        .width('100%')
        .backgroundColor(BubuColor.card)
        .borderRadius(BubuRadius.small)
        .onChange((v: string) => { this.memberName = v; })
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }

  // MARK: Button（对照 primaryButton）
  @Builder
  primaryButton() {
    Text(this.step < 2 ? '继续' : '开始记录布布的成长')
      .fontSize(BubuFont.headline)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .textAlign(TextAlign.Center)
      .width('100%')
      .height(58)
      .backgroundColor(BubuColor.primary)
      .borderRadius(BubuRadius.button)
      .shadow({ radius: BubuShadow.cardRadius, color: BubuShadow.cardColor, offsetY: BubuShadow.cardOffsetY })
      .onClick(() => { this.advance(); })
  }

  private pickBirthday(): void {
    DatePickerDialog.show({
      start: new Date(2015, 0, 1),
      end: new Date(),
      selected: new Date(this.birthdayMs),
      onDateAccept: (value: Date) => { this.birthdayMs = value.getTime(); }
    });
  }

  // 对照 advance()
  private advance(): void {
    if (this.step < 2) {
      this.step += 1;
    } else {
      this.finish();
    }
  }

  // 对照 finish()：创建布布档案 + 第一个成员（主账号）。
  private async finish(): Promise<void> {
    const now = Date.now();
    const name = this.childName.length === 0 ? '布布' : this.childName;
    const profile: ChildProfile = {
      id: util.generateRandomUUID(true),
      name: name,
      birthday: this.birthdayMs,
      syncState: SyncState.local,
      createdAt: now
    };
    await AppDatabase.shared.upsertChildProfile(profile);

    const displayName = this.memberName.length === 0 ? this.selectedRelation : this.memberName;
    const member: FamilyMember = {
      id: util.generateRandomUUID(true),
      name: displayName,
      relation: this.selectedRelation,
      avatarEmoji: relationDefaultEmoji(this.selectedRelation),
      themeColorHex: relationDefaultColorHex(this.selectedRelation),
      isPrimary: true,
      syncState: SyncState.local,
      createdAt: now
    };
    await AppDatabase.shared.upsertMember(member);

    // 持久化身份与名字（对照 env.config.childName / currentRoleRaw）。
    await ServerConfig.shared.setChildName(profile.name);
    await ServerConfig.shared.setRole(this.selectedRelation as string as FamilyRole);

    if (this.onComplete) this.onComplete();
  }
}
