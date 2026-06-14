import { Media } from '../models/Models';
import { MediaType } from '../models/Enums';
import { MediaStore } from '../services/MediaStore';
import { BubuColor, BubuRadius } from '../theme/BubuTheme';

// MARK: - 媒体缩略图（对照 iOS DesignSystem/Components/MediaThumbnail.swift）
// iOS 经 ThumbnailProvider 统一加载（内存缓存 / 降采样 / 后台补齐）；
// HarmonyOS 切片直接走本地路径：优先缩略图文件，其次原始媒体文件；远端未落地时呼吸占位。
// 视频/音频在左下角叠加角标。
@Component
export struct MediaThumbnail {
  @Require @Prop media: Media;
  @Prop cornerRadius: number = BubuRadius.small;

  // 本地无文件但有远端 URL：等同步引擎下载落地（对照 iOS isAwaitingRemote）。
  @State private pulse: boolean = false;

  private mediaType(): MediaType {
    return this.media.typeRaw as MediaType;
  }

  private isAwaitingRemote(): boolean {
    const hasLocal = this.media.localFileName !== undefined && this.media.localFileName.length > 0;
    const hasRemote = this.media.remoteURL !== undefined && this.media.remoteURL.length > 0;
    return !hasLocal && hasRemote;
  }

  // 解析可显示的本地图片路径：缩略图优先，否则原图（仅照片）。返回 file:// uri 或空串。
  private imageSrc(): string {
    const store = MediaStore.shared;
    const thumb = this.media.thumbnailFileName;
    if (thumb !== undefined && thumb.length > 0) {
      // NOTE: MediaStore 未暴露缩略图 exists 校验；直接拼路径，缺失时由 Image .alt() 兜底显示占位。
      return `file://${store.thumbnailPath(thumb)}`;
    }
    const local = this.media.localFileName;
    if (local !== undefined && local.length > 0 && this.mediaType() === MediaType.photo && store.exists(local)) {
      return `file://${store.fullPath(local)}`;
    }
    return '';
  }

  private placeholderSymbol(): string {
    switch (this.mediaType()) {
      case MediaType.video: return '🎬';
      case MediaType.audio: return '🎵';
      default: return '🖼️';
    }
  }

  aboutToAppear(): void {
    if (this.isAwaitingRemote()) {
      this.startPulse();
    }
  }

  private startPulse(): void {
    // iOS: .easeInOut(0.9).repeatForever(autoreverses: true)
    animateTo({
      duration: 900,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, () => {
      this.pulse = true;
    });
  }

  build() {
    Stack() {
      if (this.imageSrc().length > 0) {
        Image(this.imageSrc())
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      } else {
        // 占位（呼吸闪烁提示「正在取」）。
        Stack() {
          Text(this.placeholderSymbol())
            .fontSize(28)
            .fontColor(BubuColor.secondaryText)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(BubuColor.cream)
        .opacity(this.isAwaitingRemote() ? (this.pulse ? 0.55 : 1.0) : 1.0)
      }

      // 视频/音频角标（对照 iOS play.circle.fill / waveform）。
      if (this.mediaType() !== MediaType.photo) {
        Text(this.mediaType() === MediaType.video ? '▶' : '〰')
          .fontSize(20)
          .fontColor(Color.White)
          .shadow({ radius: 2, color: '#80000000' })
          .margin(8)
      }
    }
    .alignContent(Alignment.BottomStart)
    .clip(true)
    .borderRadius(this.cornerRadius)
  }
}
