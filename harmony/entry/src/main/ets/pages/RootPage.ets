import { HomeView } from '../view/HomeView';
import { TimelineView } from '../view/TimelineView';
import { BubuColor } from '../theme/BubuTheme';

// MARK: - 根导航（对照 iOS RootTabView）
// 5 Tab：记录此刻 / 时光 / 里程碑 / 布布的故事 / 时间胶囊。
// 首页已实现；其余 Tab 为占位，待 H6/H7 填充。
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
        this.comingSoon('里程碑', '布布点亮的每一个第一次')
      }.tabBar(this.bar('里程碑', '⭐', 2))

      TabContent() {
        this.comingSoon('布布的故事', 'AI 成长电影 / 第一人称日记')
      }.tabBar(this.bar('故事', '✨', 3))

      TabContent() {
        this.comingSoon('时间胶囊', '写给未来布布的信')
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

  @Builder
  comingSoon(title: string, subtitle: string) {
    Column({ space: 10 }) {
      Text('🐣').fontSize(56)
      Text(title).fontSize(20).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
      Text(subtitle).fontSize(13).fontColor(BubuColor.secondaryText)
      Text('敬请期待').fontSize(12).fontColor(BubuColor.primary).margin({ top: 8 })
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .backgroundColor(BubuColor.cream)
  }
}
