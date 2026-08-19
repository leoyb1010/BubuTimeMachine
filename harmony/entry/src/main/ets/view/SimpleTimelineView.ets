import { Entry, Media, VoiceNote } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { MediaStore } from '../services/MediaStore';
import { BubuColor, BubuFont, BubuRadius } from '../theme/BubuTheme';
import { BubuDateFormat } from '../theme/BubuDateFormat';
import { VoicePlayerBubble } from '../components/VoiceComponents';

interface SimpleTimelineItem {
  entry: Entry;
  cover?: Media;
  voice?: VoiceNote;
}

@Component
export struct SimpleTimelineView {
  onClose: () => void = () => {};
  @State items: SimpleTimelineItem[] = [];

  aboutToAppear(): void { this.reload(); }

  build() {
    Column() {
      Row() {
        Text('布布的时光').fontSize(26).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        Blank()
        Button('关闭').height(48).backgroundColor(BubuColor.primary).fontColor(Color.White).onClick(this.onClose)
      }.width('100%').padding(16)
      Scroll() {
        Column({ space: 18 }) {
          if (this.items.length === 0) {
            Column({ space: 10 }) {
              Text('👶').fontSize(60)
              Text('还没有记录').fontSize(24).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
              Text('回去点“拍一张”，留下第一张照片吧').fontSize(17).fontColor(BubuColor.secondaryText).textAlign(TextAlign.Center)
            }.width('100%').padding({ top: 80, bottom: 80 })
          }
          ForEach(this.items, (item: SimpleTimelineItem) => {
            Column({ space: 10 }) {
              if (item.cover?.localFileName) {
                Image(`file://${MediaStore.shared.fullPath(item.cover.localFileName)}`)
                  .width('100%').height(240).objectFit(ImageFit.Cover).borderRadius(BubuRadius.small)
              }
              Text(BubuDateFormat.longDate(new Date(item.entry.happenedAt)))
                .fontSize(16).fontWeight(FontWeight.Bold).fontColor(BubuColor.deepRose).width('100%')
              if (item.entry.note) {
                Text(item.entry.note).fontSize(21).fontWeight(FontWeight.Medium)
                  .fontColor(BubuColor.warmBrown).maxLines(4).width('100%')
              }
              if (item.voice?.localFileName) {
                VoicePlayerBubble({
                  fileName: item.voice.localFileName,
                  duration: item.voice.durationSeconds,
                  waveform: item.voice.waveformSamples
                })
              }
            }.alignItems(HorizontalAlign.Start).width('100%').padding(16)
            .backgroundColor(BubuColor.card).borderRadius(BubuRadius.card)
          }, (item: SimpleTimelineItem): string => item.entry.id)
        }.width('100%').padding(18)
      }.layoutWeight(1)
    }.width('100%').height('100%').backgroundColor(BubuColor.background)
  }

  private async reload(): Promise<void> {
    const output: SimpleTimelineItem[] = [];
    for (const entry of await AppDatabase.shared.fetchEntries(false)) {
      const media = await AppDatabase.shared.fetchMediaForEntry(entry.id);
      const voices = await AppDatabase.shared.fetchVoiceForEntry(entry.id);
      output.push({
        entry,
        cover: media.find((item: Media): boolean => item.localFileName !== undefined),
        voice: voices.find((item: VoiceNote): boolean => item.localFileName !== undefined)
      });
    }
    this.items = output;
  }
}
