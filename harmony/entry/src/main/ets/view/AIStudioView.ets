import { BubuColor } from '../theme/BubuTheme';

// MARK: - 布布的故事 / AI Studio（对照 iOS AIStudioHomeView）
// 入口卡：成长电影 / 第一人称日记 / 成长报告。对接现有 FastAPI（AIService）。
interface StudioEntry {
  emoji: string;
  title: string;
  subtitle: string;
}

@Component
export struct AIStudioView {
  private items: StudioEntry[] = [
    { emoji: '🎬', title: '成长电影', subtitle: '把这一年的瞬间拼成一部小电影' },
    { emoji: '📖', title: '第一人称日记', subtitle: 'AI 用布布的口吻，把你的记录改写成日记' },
    { emoji: '📊', title: '成长报告', subtitle: '阶段性回顾布布的点滴变化' },
    { emoji: '👨‍👩‍👧', title: '家庭合奏', subtitle: '把全家的多视角补充汇成一段故事' }
  ];

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('布布的故事')
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown).width('100%')
        Text('由 AI 把布布的点滴，讲成值得收藏的故事')
          .fontSize(13).fontColor(BubuColor.secondaryText).width('100%')

        ForEach(this.items, (it: StudioEntry) => {
          Row({ space: 14 }) {
            Text(it.emoji).fontSize(34)
            Column() {
              Text(it.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(BubuColor.warmBrown)
              Text(it.subtitle).fontSize(12).fontColor(BubuColor.secondaryText).maxLines(2)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text('›').fontSize(22).fontColor(BubuColor.secondaryText)
          }
          .width('100%').padding(16)
          .backgroundColor(BubuColor.card).borderRadius(16)
        }, (it: StudioEntry) => it.title)

        Text('需在设置里连上家里的 AI 服务后生成')
          .fontSize(11).fontColor(BubuColor.secondaryText).margin({ top: 8 })
      }
      .padding(16).width('100%')
    }
    .backgroundColor(BubuColor.cream).width('100%').height('100%')
  }
}
