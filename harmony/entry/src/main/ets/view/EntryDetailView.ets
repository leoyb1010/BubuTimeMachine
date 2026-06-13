import { Entry, ChildProfile, Media } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { MediaStore } from '../services/MediaStore';
import { AgeCalculator } from '../models/AgeCalculator';
import { moodEmoji, Mood } from '../models/Enums';
import { BubuColor } from '../theme/BubuTheme';
import { promptAction } from '@kit.ArkUI';

// MARK: - 记录详情（对照 iOS EntryDetailView）
// 大图 + 原文 + 当时年龄 + 心情 + 删除。
@Component
export struct EntryDetailView {
  @Prop entry: Entry;
  // 关闭/删除后通知父级刷新
  onDismiss?: () => void;

  @State photos: string[] = [];
  @State profile: ChildProfile | null = null;

  aboutToAppear(): void { this.load(); }

  private async load(): Promise<void> {
    this.profile = await AppDatabase.shared.fetchChildProfile();
    const media = await AppDatabase.shared.fetchMediaForEntry(this.entry.id);
    this.photos = media
      .filter(m => m.typeRaw === 'photo' && m.localFileName)
      .map(m => 'file://' + MediaStore.shared.fullPath(m.localFileName!));
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        // 头部：年龄 + 心情 + 日期
        Row() {
          Text(moodEmoji(this.entry.moodRaw as Mood | undefined)).fontSize(28)
          Column() {
            if (this.profile) {
              Text(AgeCalculator.ageDescription(this.profile!.birthday, this.entry.happenedAt))
                .fontSize(16).fontWeight(FontWeight.Bold).fontColor(BubuColor.primary)
            }
            Text(this.dateText(this.entry.happenedAt)).fontSize(12).fontColor(BubuColor.secondaryText)
          }.alignItems(HorizontalAlign.Start).margin({ left: 10 })
          Blank()
          Text(this.entry.authorRole).fontSize(12).fontColor(BubuColor.secondaryText)
        }.width('100%')

        // 照片们
        ForEach(this.photos, (uri: string) => {
          Image(uri).width('100%').borderRadius(16).objectFit(ImageFit.Cover)
        }, (uri: string) => uri)

        // 原文
        if (this.entry.note && this.entry.note.length > 0) {
          Text(this.entry.note)
            .fontSize(16).fontColor(BubuColor.warmBrown).width('100%')
            .padding(16).backgroundColor(BubuColor.card).borderRadius(16)
        }

        // 删除
        Button('删除这条记录')
          .width('100%').backgroundColor('#FFE5E5').fontColor('#D9534F')
          .margin({ top: 20 })
          .onClick(() => { this.confirmDelete(); })
      }
      .padding(16).width('100%')
    }
    .backgroundColor(BubuColor.cream).width('100%').height('100%')
  }

  private confirmDelete(): void {
    promptAction.showDialog({
      title: '删除记录',
      message: '删除后会从时光轴移除（本地软删除，可同步）。',
      buttons: [
        { text: '取消', color: BubuColor.secondaryText },
        { text: '删除', color: '#D9534F' }
      ]
    }).then(async (res) => {
      if (res.index === 1) {
        await AppDatabase.shared.archiveEntry(this.entry.id);
        promptAction.showToast({ message: '已删除' });
        if (this.onDismiss) this.onDismiss();
      }
    });
  }

  private dateText(ms: number): string {
    const d = new Date(ms);
    return `${d.getFullYear()}.${d.getMonth() + 1}.${d.getDate()} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  }
}
