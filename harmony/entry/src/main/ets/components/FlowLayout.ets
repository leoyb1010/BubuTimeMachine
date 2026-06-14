// MARK: - 流式布局（对照 iOS DesignSystem/Components/FlowLayout.swift）
// iOS 用 SwiftUI Layout 协议手算换行；ArkUI 用 Flex({ wrap }) 原生折行容器实现同等「标签自动换行」效果。
// 用法：FlowLayout({ spacing: 8 }) { ForEach(...) { ... } } —— 子内容经 @BuilderParam content 注入。
import { LengthMetrics } from '@kit.ArkUI';

@Component
export struct FlowLayout {
  @Prop spacing: number = 8;
  // 子项内容插槽（对照 iOS Layout 的 subviews）。
  @BuilderParam content: () => void;

  build() {
    Flex({
      wrap: FlexWrap.Wrap,
      direction: FlexDirection.Row,
      // iOS 行内/行间用同一个 spacing；ArkUI 用 space.main/cross 表达。
      space: { main: LengthMetrics.vp(this.spacing), cross: LengthMetrics.vp(this.spacing) }
    }) {
      this.content()
    }
    .width('100%')
  }
}
