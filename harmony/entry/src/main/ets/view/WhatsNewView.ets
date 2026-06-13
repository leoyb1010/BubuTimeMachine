import { CHANGELOG, ReleaseNote } from '../models/Changelog';
import { BubuColor } from '../theme/BubuTheme';

@Component
export struct WhatsNewView {
  build() {
    Scroll() {
      Column({ space: 14 }) {
        ForEach(CHANGELOG, (note: ReleaseNote) => {
          this.noteCard(note)
        }, (note: ReleaseNote) => note.version)
      }
      .padding(16)
      .width('100%')
    }
    .backgroundColor(BubuColor.cream)
    .width('100%')
    .height('100%')
  }

  @Builder
  noteCard(note: ReleaseNote) {
    Column({ space: 10 }) {
      Row() {
        Text(`v${note.version}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(BubuColor.warmBrown)
        Blank()
        Text(note.date)
          .fontSize(12)
          .fontColor(BubuColor.secondaryText)
      }
      .width('100%')

      Text(note.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(BubuColor.primary)
        .width('100%')

      ForEach(note.highlights, (item: string) => {
        Row({ space: 8 }) {
          Text('·').fontSize(15).fontColor(BubuColor.primary)
          Text(item)
            .fontSize(14)
            .fontColor(BubuColor.warmBrown)
            .layoutWeight(1)
        }
        .width('100%')
      }, (item: string) => item)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(BubuColor.card)
    .borderRadius(16)
  }
}
