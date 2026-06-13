import { HomeView } from '../view/HomeView';
import { TimelineView } from '../view/TimelineView';
import { MilestonesView } from '../view/MilestonesView';
import { AIStudioView } from '../view/AIStudioView';
import { CapsuleView } from '../view/CapsuleView';
import { BubuColor } from '../theme/BubuTheme';

// MARK: - 根导航（对照 iOS RootTabView）
// 5 Tab：记录此刻 / 时光 / 里程碑 / 布布的故事 / 时间胶囊。
// 健康入口从首页进。全部为真实页面。
@Entry
@Component
struct RootPage {
  @State current: number = 0;

  build() {
    Column() {
      Stack() {
        if (this.current === 0) {
          HomeView()
        } else if (this.current === 1) {
          TimelineView()
        } else if (this.current === 2) {
          MilestonesView()
        } else if (this.current === 3) {
          AIStudioView()
        } else {
          CapsuleView()
        }
      }
      .layoutWeight(1)
      .width('100%')

      Row() {
        this.bar('记录此刻', '🏠', 0)
        this.bar('时光', '🕐', 1)
        this.bar('里程碑', '⭐', 2)
        this.bar('故事', '✨', 3)
        this.bar('胶囊', '✉️', 4)
      }
      .width('100%')
      .height(118)
      .padding({ top: 8, bottom: 8 })
      .backgroundColor('#FFF9F6')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BubuColor.cream)
  }

  @Builder
  bar(label: string, emoji: string, idx: number) {
    Column() {
      Text(emoji).fontSize(20)
      Text(label).fontSize(11)
        .fontColor(this.current === idx ? BubuColor.primary : BubuColor.secondaryText)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(4)
    .onClick(() => { this.current = idx; })
  }
}
