import { HomeView } from '../view/HomeView';
import { TimelineView } from '../view/TimelineView';
import { MilestonesView } from '../view/MilestonesView';
import { AIStudioView } from '../view/AIStudioView';
import { CapsuleView } from '../view/CapsuleView';
import { HealthHomeView } from '../view/HealthHomeView';
import { BubuColor } from '../theme/BubuTheme';

// MARK: - 根导航（对照 iOS RootTabView）
// 5 Tab：记录此刻 / 时光 / 里程碑 / 布布的故事 / 时间胶囊。
// 健康入口从首页进。全部为真实页面。
@Entry
@Component
struct RootPage {
  @State current: number = 0;

  build() {
    Tabs({ index: this.current }) {
      TabContent() {
        HomeView()
      }.tabBar(this.bar('记录此刻', '🏠', 0))

      TabContent() {
        TimelineView()
      }.tabBar(this.bar('时光', '🕐', 1))

      TabContent() {
        MilestonesView()
      }.tabBar(this.bar('里程碑', '⭐', 2))

      TabContent() {
        AIStudioView()
      }.tabBar(this.bar('故事', '✨', 3))

      TabContent() {
        CapsuleView()
      }.tabBar(this.bar('胶囊', '✉️', 4))
    }
    .barPosition(BarPosition.End)
    .onChange((i: number) => { this.current = i; })
    .backgroundColor(BubuColor.cream)
  }

  @Builder
  bar(label: string, emoji: string, idx: number) {
    Column() {
      Text(emoji).fontSize(20)
      Text(label).fontSize(11)
        .fontColor(this.current === idx ? BubuColor.primary : BubuColor.secondaryText)
    }.padding(4)
  }
}
