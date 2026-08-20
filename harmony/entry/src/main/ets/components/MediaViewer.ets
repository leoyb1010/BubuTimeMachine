import { Media } from '../models/Models';
import { MediaType } from '../models/Enums';
import { MediaStore } from '../services/MediaStore';
import { BubuColor } from '../theme/BubuTheme';
import { VoicePlayerBubble } from './VoiceComponents';
import { APIClient } from '../services/APIClient';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { MediaLibraryService } from '../services/MediaLibraryService';
import { ShareService } from '../services/ShareService';
import { resolveInitialGalleryIndex } from '../services/MediaGalleryModel';

// MARK: - 媒体相册查看器（对照 iOS DesignSystem/Components/MediaViewer.swift MediaGalleryViewer）
// 全屏黑底；左右滑动切换媒体（iOS TabView .page → ArkUI Swiper）；
// 照片支持捏合/双击缩放（iOS UIScrollView 缩放 → ArkUI PinchGesture + scale/offset）；
// 视频用 Video 组件；音频复用 VoicePlayerBubble。右上角关闭。
@Component
export struct MediaGalleryViewer {
  @Require @Prop @Watch('syncInitialIndex') mediaItems: Media[];
  @Require @Prop @Watch('syncInitialIndex') initialMediaID: string;
  // iOS: onDismiss
  onDismiss?: () => void;

  @State private selectedIndex: number = 0;
  @State private remotePaths: Map<string, string> = new Map();
  @State private zoomedMediaIds: Set<string> = new Set();
  @State private toastText: string = '';

  aboutToAppear(): void {
    this.syncInitialIndex();
  }

  private syncInitialIndex(): void {
    this.selectedIndex = resolveInitialGalleryIndex(this.mediaItems, this.initialMediaID);
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
              MediaPageView({
                media: media,
                onRemoteReady: (id: string, path: string): void => { this.setRemotePath(id, path); },
                onRemoteRemoved: (id: string): void => { this.removeRemotePath(id); },
                onZoomChanged: (id: string, zoomed: boolean): void => { this.setZoomed(id, zoomed); }
              })
                .width('100%')
                .height('100%')
            }, (media: Media) => media.id)
          }
          .index(this.selectedIndex)
          .loop(false)
          .indicator(false)
          .cachedCount(1)
          .disableSwipe(this.isCurrentZoomed())
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
          if (this.currentPath().length > 0) {
            Text('保存').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Color.White)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor('#73000000').borderRadius(18)
              .accessibilityText('存到系统相册')
              .onClick(() => { this.saveCurrent(); })
            Text('分享').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Color.White)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor('#73000000').borderRadius(18).margin({ left: 8 })
              .accessibilityText('分享当前媒体')
              .onClick(() => { this.shareCurrent(); })
          }
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
            .accessibilityText('关闭媒体查看器')
            .onClick(() => { if (this.onDismiss) this.onDismiss(); })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 12 })

        if (this.toastText.length > 0) {
          Text(this.toastText).fontSize(13).fontWeight(FontWeight.Bold).fontColor(Color.White)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .backgroundColor('#8C000000').borderRadius(18).margin({ top: 8 })
        }

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
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .alignContent(Alignment.TopEnd)
    .width('100%')
    .height('100%')
  }

  private isCurrentZoomed(): boolean {
    const current = this.currentMedia();
    return current !== undefined && this.zoomedMediaIds.has(current.id);
  }

  private currentMedia(): Media | undefined { return this.mediaItems[this.selectedIndex]; }

  private currentPath(): string {
    const media = this.currentMedia();
    if (!media) return '';
    const local = media.localFileName;
    if (local && MediaStore.shared.exists(local)) return MediaStore.shared.fullPath(local);
    return this.remotePaths.get(media.id) ?? '';
  }

  private setRemotePath(id: string, path: string): void {
    const next = new Map(this.remotePaths);
    next.set(id, path);
    this.remotePaths = next;
  }

  private removeRemotePath(id: string): void {
    const next = new Map(this.remotePaths);
    next.delete(id);
    this.remotePaths = next;
  }

  private setZoomed(id: string, zoomed: boolean): void {
    const next = new Set(this.zoomedMediaIds);
    if (zoomed) next.add(id); else next.delete(id);
    this.zoomedMediaIds = next;
  }

  private async saveCurrent(): Promise<void> {
    const media = this.currentMedia();
    const path = this.currentPath();
    if (!media || path.length === 0) return;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const saved = await MediaLibraryService.save(context, path, media.typeRaw === MediaType.video);
      this.showToast(saved ? '已存到系统相册 ✓' : '已取消保存');
    } catch (e) {
      this.showToast('没存成功，请稍后重试');
    }
  }

  private async shareCurrent(): Promise<void> {
    const media = this.currentMedia();
    const path = this.currentPath();
    if (!media || path.length === 0) return;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await ShareService.shareMedia(context, path, '布布时光', media.typeRaw === MediaType.video);
    } catch (e) {
      this.showToast('暂时没能打开分享');
    }
  }

  private showToast(message: string): void {
    this.toastText = message;
    setTimeout(() => { if (this.toastText === message) this.toastText = ''; }, 2000);
  }
}

// MARK: - 单页媒体（对照 iOS MediaPageView）
@Component
struct MediaPageView {
  @Require @Prop media: Media;
  onRemoteReady: (id: string, path: string) => void = () => {};
  onRemoteRemoved: (id: string) => void = () => {};
  onZoomChanged: (id: string, zoomed: boolean) => void = () => {};
  @State private remoteFilePath: string = '';
  @State private remoteLoading: boolean = false;
  @State private remoteError: string = '';
  private pageVisible: boolean = false;

  aboutToAppear(): void {
    this.pageVisible = true;
    if (!this.hasLocalFile() && (this.media.remoteURL?.length ?? 0) > 0) this.loadRemote();
  }

  aboutToDisappear(): void { this.pageVisible = false; this.cleanupRemote(); }

  private mediaType(): MediaType {
    return this.media.typeRaw as MediaType;
  }

  // 本地照片路径（file:// uri），无则空串。
  private photoSrc(): string {
    const local = this.media.localFileName;
    if (local !== undefined && local.length > 0 && MediaStore.shared.exists(local)) {
      return `file://${MediaStore.shared.fullPath(local)}`;
    }
    return this.remoteFilePath.length > 0 ? `file://${this.remoteFilePath}` : '';
  }

  private videoSrc(): string {
    const local = this.media.localFileName;
    if (local !== undefined && local.length > 0 && MediaStore.shared.exists(local)) {
      return `file://${MediaStore.shared.fullPath(local)}`;
    }
    return this.remoteFilePath.length > 0 ? `file://${this.remoteFilePath}` : '';
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
      ZoomableImage({
        src: this.photoSrc(),
        onZoomChanged: (zoomed: boolean): void => { this.onZoomChanged(this.media.id, zoomed); }
      })
    } else if ((this.media.remoteURL?.length ?? 0) > 0) {
      this.remotePlaceholder('照片')
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
    } else if ((this.media.remoteURL?.length ?? 0) > 0) {
      this.remotePlaceholder('视频')
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

  @Builder
  remotePlaceholder(kind: string) {
    Column({ space: 12 }) {
      if (this.remoteLoading) {
        LoadingProgress().width(36).height(36).color(Color.White)
        Text(`${kind}正在下载…`).fontSize(15).fontColor('#D9FFFFFF')
      } else {
        Text(this.remoteError.length > 0 ? this.remoteError : `${kind}还没下载好`)
          .fontSize(15).fontColor('#D9FFFFFF')
        Button('重试').fontColor(Color.White).backgroundColor('#29FFFFFF')
          .onClick(() => { this.loadRemote(); })
      }
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  private hasLocalFile(): boolean {
    const local = this.media.localFileName;
    return local !== undefined && local.length > 0 && MediaStore.shared.exists(local);
  }

  private async loadRemote(): Promise<void> {
    const remote = this.media.remoteURL ?? '';
    if (remote.length === 0 || this.remoteLoading || this.remoteFilePath.length > 0) return;
    this.remoteLoading = true;
    this.remoteError = '';
    const extension = this.mediaType() === MediaType.video ? 'mp4' : 'jpg';
    const destination = MediaStore.shared.fullPath(`viewer_${util.generateRandomUUID(true)}.${extension}`);
    try {
      const path = await APIClient.shared.downloadFile(remote, destination);
      if (!this.pageVisible) {
        try { if (fileIo.accessSync(path)) fileIo.unlinkSync(path); } catch (cleanupError) {}
        return;
      }
      this.remoteFilePath = path;
      this.onRemoteReady(this.media.id, path);
    } catch (e) {
      try { if (fileIo.accessSync(destination)) fileIo.unlinkSync(destination); } catch (cleanupError) {}
      this.remoteError = `${this.mediaType() === MediaType.video ? '视频' : '照片'}下载失败，请稍后重试`;
    } finally {
      this.remoteLoading = false;
    }
  }

  private cleanupRemote(): void {
    if (this.remoteFilePath.length === 0) return;
    try { if (fileIo.accessSync(this.remoteFilePath)) fileIo.unlinkSync(this.remoteFilePath); } catch (e) {}
    this.onRemoteRemoved(this.media.id);
    this.remoteFilePath = '';
  }
}

// MARK: - 可缩放图片（对照 iOS ZoomableImageView / ZoomingImageScrollView）
// iOS 用 UIScrollView 双击/捏合缩放 1~5×；ArkUI 用 PinchGesture 实时缩放 + 双击在 1×/2.8× 间切换。
@Component
struct ZoomableImage {
  @Require @Prop src: string;
  onZoomChanged: (zoomed: boolean) => void = () => {};

  @State private scaleValue: number = 1;
  @State private offsetX: number = 0;
  @State private offsetY: number = 0;
  @State private viewportWidth: number = 0;
  @State private viewportHeight: number = 0;
  private baseScale: number = 1;
  private baseOffsetX: number = 0;
  private baseOffsetY: number = 0;
  private readonly minScale: number = 1;
  private readonly maxScale: number = 5;
  private readonly doubleTapScale: number = 2.8;

  build() {
    Image(this.src)
      .objectFit(ImageFit.Contain)
      .width('100%')
      .height('100%')
      .scale({ x: this.scaleValue, y: this.scaleValue })
      .translate({ x: this.offsetX, y: this.offsetY })
      .onAreaChange((_old: Area, area: Area) => {
        this.viewportWidth = area.width as number;
        this.viewportHeight = area.height as number;
        this.clampPosition();
      })
      .gesture(
        // 捏合缩放（对照 iOS minimumZoomScale 1 / maximumZoomScale 5）。
        PinchGesture()
          .onActionStart(() => { this.baseScale = this.scaleValue; })
          .onActionUpdate((event: GestureEvent) => {
            const next = this.baseScale * event.scale;
            this.scaleValue = Math.max(this.minScale, Math.min(this.maxScale, next));
            this.onZoomChanged(this.scaleValue > 1.01);
          })
          .onActionEnd(() => {
            if (this.scaleValue <= 1.01) this.resetPosition();
            else this.clampPosition();
          })
      )
      .gesture(
        TapGesture({ count: 2 })
          .onAction(() => {
            this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
              this.scaleValue = this.scaleValue > 1.01 ? this.minScale : this.doubleTapScale;
              if (this.scaleValue === this.minScale) {
                this.offsetX = 0;
                this.offsetY = 0;
              }
              this.onZoomChanged(this.scaleValue > 1.01);
            });
          })
      )
      // 放大后图片接管单指平移；1× 时在下方 judge 中拒绝，让原生 Swiper 独占横滑。
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.All, distance: 8, isFingerCountLimited: true })
          .tag('zoom-pan')
          .onActionStart(() => {
            this.baseOffsetX = this.offsetX;
            this.baseOffsetY = this.offsetY;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.scaleValue <= 1.01) return;
            const pan = event as PanGestureEvent;
            this.offsetX = this.baseOffsetX + pan.offsetX;
            this.offsetY = this.baseOffsetY + pan.offsetY;
            this.clampPosition();
          })
          .onActionEnd((event: GestureEvent) => {
            if (this.scaleValue <= 1.01) this.resetPosition();
          })
      )
      .onGestureJudgeBegin((info: GestureInfo, _event: BaseGestureEvent): GestureJudgeResult => {
        if (info.tag === 'zoom-pan' && this.scaleValue <= 1.01) return GestureJudgeResult.REJECT;
        return GestureJudgeResult.CONTINUE;
      })
  }

  private resetPosition(): void {
    this.scaleValue = 1;
    this.offsetX = 0;
    this.offsetY = 0;
    this.onZoomChanged(false);
  }

  private clampPosition(): void {
    if (this.scaleValue <= 1.01) {
      this.offsetX = 0;
      this.offsetY = 0;
      return;
    }
    const maxX = Math.max(0, this.viewportWidth * (this.scaleValue - 1) / 2);
    const maxY = Math.max(0, this.viewportHeight * (this.scaleValue - 1) / 2);
    this.offsetX = Math.max(-maxX, Math.min(maxX, this.offsetX));
    this.offsetY = Math.max(-maxY, Math.min(maxY, this.offsetY));
  }
}
