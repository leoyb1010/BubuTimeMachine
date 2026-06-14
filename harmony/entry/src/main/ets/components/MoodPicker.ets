import { Mood, ALL_MOODS, moodEmoji } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';

// MARK: - 心情选择器（对照 iOS DesignSystem/Components/MoodPicker.swift）
// 横向一排心情 emoji，给每个此刻一种情绪。轻点选中，再点取消（toggle）。
// iOS 用 @Binding selection: Mood?；ArkUI 用 @Prop 当前值 + onChange 回调回传（父持有真相源）。
@Component
export struct MoodPicker {
  @Prop selection?: Mood;
  @Prop tint: string = BubuColor.primary;
  // iOS @Binding 的写回：选中 mood 或 undefined（取消）。
  onChange?: (mood: Mood | undefined) => void;

  build() {
    Column({ space: 10 }) {
      Text('此刻的心情')
        .fontSize(15)
        .fontColor(BubuColor.secondaryText)
        .alignSelf(ItemAlign.Start)

      Scroll() {
        Row({ space: 10 }) {
          ForEach(ALL_MOODS, (mood: Mood) => {
            this.moodCell(mood)
          }, (mood: Mood) => mood)
        }
        .padding({ top: 2, bottom: 2 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .align(Alignment.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  moodCell(mood: Mood) {
    Column({ space: 3 }) {
      Text(moodEmoji(mood)).fontSize(26)
      Text(mood) // Mood 的值即中文标签（rawValue）
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(BubuColor.warmBrown)
    }
    .justifyContent(FlexAlign.Center)
    .width(58)
    .height(62)
    .backgroundColor(this.selection === mood ? this.tintAlpha18() : BubuColor.card)
    .borderRadius(14)
    .border({ width: 2, color: this.selection === mood ? this.tint : Color.Transparent })
    // iOS scaleEffect(selected ? 1.05 : 1)
    .scale({ x: this.selection === mood ? 1.05 : 1, y: this.selection === mood ? 1.05 : 1 })
    .onClick(() => {
      const next: Mood | undefined = this.selection === mood ? undefined : mood;
      // iOS withAnimation(BubuMotion.quick) { selection = ... }
      animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        this.selection = next;
      });
      if (this.onChange) {
        this.onChange(next);
      }
    })
  }

  // tint.opacity(0.18) —— 在 #RRGGBB 前拼 alpha（约 0x2E ≈ 18%）。
  private tintAlpha18(): string {
    const hex = this.tint.startsWith('#') ? this.tint.slice(1) : this.tint;
    const rgb = hex.length >= 6 ? hex.slice(hex.length - 6) : hex;
    return `#2E${rgb}`;
  }
}
