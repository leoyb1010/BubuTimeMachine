import { Media } from '../models/Models';
import { BubuColor } from '../theme/BubuTheme';
import { MediaThumbnail } from '../components/MediaThumbnail';
import { MediaGalleryViewer } from '../components/MediaViewer';
import { AlbumMediaItem } from './SystemAlbum';

// MARK: - 相册详情（对照 iOS Features/Album/AlbumDetailView.swift）
// 三列网格，点图直接全屏查看器（与照片墙一致，不绕记录详情）。
@Component
export struct AlbumDetailView {
  @Require @Prop title: string;
  @Require @Prop items: AlbumMediaItem[];
  // iOS NavigationLink 返回；内部 route 由父级 AlbumView 控制，这里回调返回。
  onBack?: () => void;

  // 分批渲染：大相册（上千张）首屏只挂 90 个缩略图，滚到底自动追加（对照 visibleCount）。
  @State private visibleCount: number = 90;
  // 全屏查看器路由（对照 fullScreenCover(item: viewerRoute)）。
  @State private viewerInitialID: string | null = null;

  // 画廊媒体（对照 galleryMedia = items.map(\.media)）。
  private galleryMedia(): Media[] {
    return this.items.map((i: AlbumMediaItem) => i.media);
  }

  private visibleItems(): AlbumMediaItem[] {
    return this.items.slice(0, this.visibleCount);
  }

  build() {
    Stack() {
      Column() {
        // 顶部标题栏（对照 navigationTitle(title) + inline）。
        Row() {
          Text('‹ 返回')
            .fontSize(16)
            .fontColor(BubuColor.primary)
            .onClick(() => { if (this.onBack) this.onBack(); })
          Blank()
          Text(this.title)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(BubuColor.warmBrown)
          Blank()
          // 占位对齐
          Text('返回 ›').fontSize(16).fontColor(Color.Transparent)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        if (this.items.length === 0) {
          // 对照 ContentUnavailableView("这个相册还是空的", systemImage: "photo")
          Column({ space: 12 }) {
            Text('🖼️').fontSize(52)
            Text('这个相册还是空的').fontSize(16).fontColor(BubuColor.secondaryText)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding({ top: 80 })
        } else {
          Scroll() {
            Column() {
              Grid() {
                ForEach(this.visibleItems(), (item: AlbumMediaItem) => {
                  GridItem() {
                    MediaThumbnail({ media: item.media, cornerRadius: 8 })
                      .aspectRatio(1)
                      .onClick(() => { this.viewerInitialID = item.media.id; })
                  }
                }, (item: AlbumMediaItem) => item.id)
              }
              .columnsTemplate('1fr 1fr 1fr')
              .columnsGap(4)
              .rowsGap(4)
              .padding(8)

              // 触底追加更多（对照 ProgressView + onAppear { visibleCount += 90 }）。
              if (this.visibleCount < this.items.length) {
                Text('加载更多…')
                  .fontSize(13)
                  .fontColor(BubuColor.secondaryText)
                  .padding({ top: 16, bottom: 16 })
                  .onAppear(() => { this.visibleCount += 90; })
              }
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BubuColor.background)

      // 全屏查看器（对照 fullScreenCover）。
      if (this.viewerInitialID !== null) {
        MediaGalleryViewer({
          mediaItems: this.galleryMedia(),
          initialMediaID: this.viewerInitialID,
          onDismiss: () => { this.viewerInitialID = null; }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
