import { Media } from '../models/Models';
import { MediaType } from '../models/Enums';
import { MediaStore } from '../services/MediaStore';
import { BubuColor } from '../theme/BubuTheme';
import { VoicePlayerBubble } from './VoiceComponents';

// MARK: - 媒体相册查看器（对照 iOS DesignSystem/Components/MediaViewer.swift MediaGalleryViewer）
// 全屏黑底；左右滑动切换媒体（iOS TabView .page → ArkUI Swiper）；
// 照片支持捏合/双击缩放（iOS UIScrollView 缩放 → ArkUI PinchGesture + scale/offset）；
// 视频用 Video 组件；音频复用 VoicePlayerBubble。右上角关闭。
@Component
export struct MediaGalleryViewer {
  @Require @Prop mediaItems: Media[];
  @Require @Prop initialMediaID: string;
  // iOS: onDismiss
  onDismiss?: () => void;

  @State private selectedIndex: number = 0;

  aboutToAppear(): void {
    const idx = this.mediaItems.findIndex((m: Media) => m.id === this.initialMediaID);
    this.selectedIndex = idx >= 0 ? idx : 0;
  }

  build() {
    Stack() {
      // 底层：黑底 + 媒体分页
      Stack() {
        if (this.mediaItems.length === 0) {
          // iOS ContentUnavailableView
          Column({ space: 12 }) {
            Text('🖼️').fontSize(48)
            Text('没有可查看的媒体').fontSize(16).fontColor(Color.White)
          }
        } else {
          Swiper() {
            ForEach(this.mediaItems, (media: Media) => {
              MediaPageView({ media: media })
                .width('100%')
                .height('100%')
            }, (media: Media) => media.id)
          }
          .index(this.selectedIndex)
          .loop(false)
          .indicator(false)
          .width('100%')
          .height('100%')
          .onChange((index: number) => { this.selectedIndex = index; })
        }
      }
      .alignContent(Alignment.Center)
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)

      // 关闭按钮 + 底部页码/提示
      Column() {
        Row() {
          Blank()
          Text('✕')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .width(40)
            .height(40)
            .backgroundColor('#73000000')
            .borderRadius(20)
            .onClick(() => { if (this.onDismiss) this.onDismiss(); })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 12 })

        Blank()

        if (this.mediaItems.length > 1) {
          Text(`${this.selectedIndex + 1} / ${this.mediaItems.length} · 左右滑动`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor('#6B000000')
            .borderRadius(100)
            .margin({ bottom: 18 })
        } else if (this.mediaItems.length === 1) {
          Text('双击或捏合可放大')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#DBFFFFFF')
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor('#5C000000')
            .borderRadius(100)
            .margin({ bottom: 18 })
        }
      }
      .width('100%')
      .height('100%')
    }
    .alignContent(Alignment.TopEnd)
    .width('100%')
    .height('100%')
  }
}

// MARK: - 单页媒体（对照 iOS MediaPageView）
@Component
struct MediaPageView {
  @Require @Prop media: Media;

  private mediaType(): MediaType {
    return this.media.typeRaw as MediaType;
  }

  // 本地照片路径（file:// uri），无则空串。
  private photoSrc(): string {
    const local = this.media.localFileName;
    if (local !== undefined && local.length > 0 && MediaStore.shared.exists(local)) {
      return `file://${MediaStore.shared.fullPath(local)}`;
    }
    // NOTE: 远端图片在 iOS 走 APIClient.downloadFile 鉴权下载；本切片仅支持本地与裸 remoteURL。
    const remote = this.media.remoteURL;
    return remote !== undefined ? remote : '';
  }

  private videoSrc(): string {
    const local = this.media.localFileName;
    if (local !== undefined && local.length > 0 && MediaStore.shared.exists(local)) {
      return `file://${MediaStore.shared.fullPath(local)}`;
    }
    const remote = this.media.remoteURL;
    return remote !== undefined ? remote : '';
  }

  build() {
    if (this.mediaType() === MediaType.photo) {
      this.photoPage()
    } else if (this.mediaType() === MediaType.video) {
      this.videoPage()
    } else {
      this.audioPage()
    }
  }

  @Builder
  photoPage() {
    if (this.photoSrc().length > 0) {
      ZoomableImage({ src: this.photoSrc() })
    } else {
      this.missing('本地照片文件找不到了')
    }
  }

  @Builder
  videoPage() {
    if (this.videoSrc().length > 0) {
      Video({ src: this.videoSrc() })
        .controls(true)
        .objectFit(ImageFit.Contain)
        .width('100%')
        .height('100%')
    } else {
      this.missing('本地视频文件找不到了')
    }
  }

  @Builder
  audioPage() {
    Column({ space: 16 }) {
      Text('🎙️').fontSize(62).fontColor('#E6FFFFFF')
      if (this.media.localFileName !== undefined && this.media.localFileName.length > 0) {
        VoicePlayerBubble({
          fileName: this.media.localFileName,
          duration: this.media.durationSeconds !== undefined ? this.media.durationSeconds : 0,
          waveform: [],
          tint: BubuColor.primary
        })
          .padding(16)
          .backgroundColor('#1FFFFFFF')
          .borderRadius(22)
      } else {
        Text('本地音频文件找不到了').fontColor('#CCFFFFFF')
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(16)
  }

  @Builder
  missing(text: string) {
    Column({ space: 14 }) {
      Text('⚠️').fontSize(42)
      Text(text).fontSize(16).fontColor('#D9FFFFFF')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

// MARK: - 可缩放图片（对照 iOS ZoomableImageView / ZoomingImageScrollView）
// iOS 用 UIScrollView 双击/捏合缩放 1~5×；ArkUI 用 PinchGesture 实时缩放 + 双击在 1×/2.8× 间切换。
@Component
struct ZoomableImage {
  @Require @Prop src: string;

  @State private scaleValue: number = 1;
  private baseScale: number = 1;
  private readonly minScale: number = 1;
  private readonly maxScale: number = 5;
  private readonly doubleTapScale: number = 2.8;

  build() {
    Image(this.src)
      .objectFit(ImageFit.Contain)
      .width('100%')
      .height('100%')
      .scale({ x: this.scaleValue, y: this.scaleValue })
      .gesture(
        // 捏合缩放（对照 iOS minimumZoomScale 1 / maximumZoomScale 5）。
        PinchGesture()
          .onActionStart(() => { this.baseScale = this.scaleValue; })
          .onActionUpdate((event: GestureEvent) => {
            const next = this.baseScale * event.scale;
            this.scaleValue = Math.max(this.minScale, Math.min(this.maxScale, next));
          })
      )
      .onClick((event: ClickEvent) => {
        // 双击切换（ArkUI onClick 无 doubleClick 计数，这里以单击在缩放态间切换近似 iOS 双击）。
        // NOTE: 完整双击手势可改用 TapGesture(count:2)；此处用 onClick 简化以保证编译与基础体验。
        animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
          this.scaleValue = this.scaleValue > 1.01 ? this.minScale : this.doubleTapScale;
        });
      })
  }
}
