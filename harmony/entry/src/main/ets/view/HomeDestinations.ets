import { ChildProfile } from '../models/Models';
import { AgeCalculator } from '../models/AgeCalculator';
import { BubuColor, BubuFont, BubuRadius } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { BubuMascotBadge, BubuExpression } from '../components/BubuMascotBadge';

// MARK: - 首页导航目的地（对照 iOS Features/Capture/HomeDestinations.swift）
// iOS 用 NavigationStack + navigationDestination(for:) 路由；
// 本切片沿用 HomeView 既有的 @State 索引式导航（RootPage 以 tab index 切换，HomeView 内部以
// HomeRoute 状态切面板）。这里把可达目的地枚举出来，作为 HomeView 内部路由的契约。
export enum HomeRoute {
  home,            // 仪表盘首页
  record,          // 记录此刻（快速记录面板）
  profile,         // 布布资料
  health,          // 布布健康
  growth,          // 成长曲线
  settings,        // 设置
  album,           // 相册 / 照片墙
  timeline,        // 时光轴
  birthday,        // 生日倒计时
  onThisDay,       // 那年今日
  naturalCapture,  // 一句话智能记录
  entryDetail      // 单条记录详情
}

// MARK: - 全屏查看器路由（相册体系共用，对照 iOS MediaViewerRoute）
export interface MediaViewerRoute {
  initialMediaID: string;
}

// MARK: - 生日倒计时（对照 iOS BirthdayCountdownView）
// 首页「天后生日」统计卡的落地页：大数字倒计时 + 即将到来的岁数。
@Component
export struct BirthdayCountdownView {
  @Prop profile: ChildProfile | null = null;

  private nextBirthdayText(birthdayMs: number): string {
    // iOS: Calendar.nextDate(after:matching:.month/.day) → 下一个生日的完整日期。
    const bd = new Date(birthdayMs);
    const now = new Date();
    let next = new Date(now.getFullYear(), bd.getMonth(), bd.getDate());
    if (next.getTime() <= now.getTime()) {
      next = new Date(now.getFullYear() + 1, bd.getMonth(), bd.getDate());
    }
    return BubuDateFormat.longDate(next);
  }

  build() {
    Column({ space: 22 }) {
      if (this.profile) {
        BubuMascotBadge({ badgeSize: 108, expression: BubuExpression.cheer })
        Column({ space: 8 }) {
          Text(`${AgeCalculator.daysUntilNextBirthday(this.profile!.birthday)}`)
            .fontSize(88)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.primary)
          Text(`天后，${this.profile!.name}就 ${AgeCalculator.ageYears(this.profile!.birthday) + 1} 岁啦`)
            .fontSize(BubuFont.headline)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
        }
        Text(this.nextBirthdayText(this.profile!.birthday))
          .fontSize(BubuFont.body)
          .fontColor(BubuColor.secondaryText)
        Column({ space: 6 }) {
          Text('可以提前准备一封时间胶囊，')
          Text('在生日当天「叮」一声打开。')
        }
        .margin({ top: 14 })
        .alignItems(HorizontalAlign.Center)
      } else {
        Text('🎁').fontSize(64)
        Text('先建立布布档案').fontSize(BubuFont.headline).fontColor(BubuColor.warmBrown)
      }
    }
    .padding(32)
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(BubuColor.cream)
  }
}
