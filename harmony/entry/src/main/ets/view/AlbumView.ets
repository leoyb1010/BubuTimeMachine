import { Media } from '../models/Models';
import { AppDatabase } from '../data/AppDatabase';
import { MediaStore } from '../services/MediaStore';
import { BubuColor } from '../theme/BubuTheme';

// MARK: - 照片墙（对照 iOS AlbumHomeView）
// 把所有记录里的照片汇成一个网格。
@Component
export struct AlbumView {
  @State photos: Media[] = [];

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.photos = await AppDatabase.shared.fetchAllPhotos();
  }

  private uri(m: Media): string {
    return m.localFileName ? 'file://' + MediaStore.shared.fullPath(m.localFileName) : '';
  }

  build() {
    Column() {
      Text('照片墙')
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(BubuColor.warmBrown)
        .width('100%').padding({ left: 16, top: 16, bottom: 8 })

      if (this.photos.length === 0) {
        Column({ space: 10 }) {
          Text('📷').fontSize(56)
          Text('还没有照片').fontSize(15).fontColor(BubuColor.warmBrown)
          Text('记录时加一张照片，就会出现在这里').fontSize(12).fontColor(BubuColor.secondaryText)
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.photos, (m: Media) => {
            GridItem() {
              Image(this.uri(m))
                .width('100%').aspectRatio(1).borderRadius(10).objectFit(ImageFit.Cover)
            }
          }, (m: Media) => m.id)
        }
        .columnsTemplate('1fr 1fr 1fr').columnsGap(6).rowsGap(6)
        .layoutWeight(1).padding({ left: 12, right: 12 })
      }
    }
    .width('100%').height('100%').backgroundColor(BubuColor.cream)
  }
}
