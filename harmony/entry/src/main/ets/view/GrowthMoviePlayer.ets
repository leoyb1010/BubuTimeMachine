import { MediaStore } from '../services/MediaStore';
import { BubuColor, BubuFont } from '../theme/BubuTheme';

// MARK: - Ken Burns 成长电影播放器（对照 iOS Features/AIStudio/GrowthMoviePlayer.swift）
// 把真实照片串成会动的幻灯片：模板片头 + 缓慢缩放平移 + 字幕 + 可关闭/重播。
// NOTE: iOS 用 ImageIO 降采样 + Timer 推进。HarmonyOS 直接以本地文件路径喂 Image，
//       并用 setInterval 推进进度；缩放/平移用 .scale/.translate + animateTo 模拟 Ken Burns。
//       这是真实照片幻灯片，不是 AVPlayer 视频流（与 iOS 行为一致，不依赖 Video 组件）。

// 电影草稿（对照 iOS MovieDraft，跨视图共享）。
export interface MovieDraft {
  id: string;
  title: string;
  templateRaw: string;       // documentary / travel / birthday / daily
  templateTitle: string;
  templateEmoji: string;
  mediaFiles: string[];      // 本地文件名列表
  captions: string[];
  narration?: string;
}

@Component
export struct GrowthMoviePlayer {
  @Require @Prop draft: MovieDraft;
  tint: string = BubuColor.primary;
  onClose: () => void = () => {};

  @State private index: number = 0;
  @State private zoomIn: boolean = true;
  @State private isPlaying: boolean = true;
  @State private progress: number = 0;       // 当前张进度 0..1
  @State private showIntro: boolean = true;
  // setInterval 句柄（推进定时器）。
  private timerId: number = -1;
  private introTimerId: number = -1;

  // 每张停留秒数（对照 iOS perSlide：daily 更短）。
  private perSlide(): number {
    return this.draft.templateRaw === 'daily' ? 2.3 : 3.2;
  }

  aboutToAppear(): void { this.startTimer(); }

  aboutToDisappear(): void { this.clearTimers(); }

  build() {
    Stack() {
      // 黑底
      Column().width('100%').height('100%').backgroundColor(Color.Black)

      this.currentSlide()

      if (this.showIntro) { this.introOverlay() }

      // 顶部信息 + 底部字幕 + 进度条
      Column() {
        this.topBar()
        Blank()
        if (!this.showIntro) { this.caption() }
        this.progressBar()
      }
      .width('100%')
      .height('100%')
      .padding(16)

      if (this.isFinished()) { this.finishOverlay() }
    }
    .width('100%')
    .height('100%')
    .onClick(() => { if (!this.isFinished()) { this.togglePlay(); } })
  }

  @Builder
  currentSlide() {
    if (this.currentImageSrc().length > 0) {
      Stack() {
        // 背景：暗化模糊铺底（对照 iOS brightness(-0.42) + overlay）。
        Image(this.currentImageSrc())
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
          .brightness(0.58)
          .blur(8)
        // 前景：等比展示 + Ken Burns 缩放平移。
        Image(this.currentImageSrc())
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
          .padding({ left: 18, right: 18, top: 104, bottom: 150 })
          .scale({ x: this.zoomIn ? 1.045 : 1.0, y: this.zoomIn ? 1.045 : 1.0 })
          .translate({ x: this.panOffset() })
          .animation({ duration: this.perSlide() * 1000, curve: Curve.EaseInOut })
      }
      .width('100%')
      .height('100%')
    } else {
      // 无图兜底（对照 iOS 渐变 + 🎬）。
      Stack() {
        Text('🎬').fontSize(80)
      }
      .width('100%')
      .height('100%')
      .linearGradient({ angle: 180, colors: [[this.tint, 0.0], ['#80F28C9E', 1.0]] })
    }
  }

  // Ken Burns 平移：逐张交替左右缓移（对照 iOS panOffset）。
  private panOffset(): number {
    const direction = this.index % 2 === 0 ? 1 : -1;
    return (this.zoomIn ? 9 : -9) * direction;
  }

  private currentImageSrc(): string {
    if (this.index < 0 || this.index >= this.draft.mediaFiles.length) return '';
    const name = this.draft.mediaFiles[this.index];
    if (name.length === 0) return '';
    return `file://${MediaStore.shared.fullPath(name)}`;
  }

  @Builder
  topBar() {
    Row({ space: 10 }) {
      Text('✕')
        .fontSize(28)
        .fontColor('#F2FFFFFF')
        .width(48)
        .height(48)
        .textAlign(TextAlign.Center)
        .onClick(() => { this.onClose(); })
      Column({ space: 2 }) {
        Text(this.draft.title)
          .fontSize(BubuFont.caption)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .maxLines(1)
        Text(this.draft.templateTitle)
          .fontSize(12)
          .fontColor('#C7FFFFFF')
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
    }
    .width('100%')
  }

  @Builder
  introOverlay() {
    Column({ space: 14 }) {
      Text(this.draft.templateEmoji).fontSize(68)
      Text(this.draft.title)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
      Text(this.draft.templateTitle)
        .fontSize(BubuFont.headline)
        .fontColor('#DBFFFFFF')
    }
    .padding(28)
    .backgroundColor('#57000000')
    .borderRadius(28)
  }

  @Builder
  caption() {
    if (this.index >= 0 && this.index < this.draft.captions.length && this.draft.captions[this.index].length > 0) {
      Text(this.draft.captions[this.index])
        .fontSize(20)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .padding({ left: 18, right: 18, top: 12, bottom: 12 })
        .backgroundColor('#57000000')
        .borderRadius(20)
        .margin({ bottom: 12 })
    }
  }

  @Builder
  progressBar() {
    Stack() {
      Column()
        .width('100%')
        .height(4)
        .backgroundColor('#40FFFFFF')
        .borderRadius(2)
      Column()
        .width(`${this.overallProgress() * 100}%`)
        .height(4)
        .backgroundColor('#FFFFFF')
        .borderRadius(2)
    }
    .alignContent(Alignment.Start)
    .width('100%')
    .height(4)
    .margin({ top: 6, bottom: 2 })
  }

  @Builder
  finishOverlay() {
    Column({ space: 14 }) {
      Text('放完啦')
        .fontSize(BubuFont.title)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
      Row({ space: 12 }) {
        Text('↺ 重播')
          .fontSize(BubuFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor(this.tint)
          .borderRadius(20)
          .onClick(() => { this.replay(); })
        Text('关闭')
          .fontSize(BubuFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor('#2EFFFFFF')
          .borderRadius(20)
          .onClick(() => { this.onClose(); })
      }
    }
    .padding(28)
    .backgroundColor('#73000000')
    .borderRadius(28)
  }

  private overallProgress(): number {
    if (this.draft.mediaFiles.length === 0) return 0;
    return (this.index + this.progress) / this.draft.mediaFiles.length;
  }

  private isFinished(): boolean {
    return !this.isPlaying && this.index >= this.draft.mediaFiles.length - 1 && this.progress >= 1;
  }

  // 启动片头 + 推进定时器（对照 iOS startTimer，0.05s tick）。
  private startTimer(): void {
    this.zoomIn = true;
    this.showIntro = true;
    this.clearTimers();
    this.introTimerId = setTimeout(() => { this.showIntro = false; }, 1100);
    this.timerId = setInterval(() => { this.tick(); }, 50);
  }

  private tick(): void {
    if (!this.isPlaying || this.showIntro) return;
    this.progress += 0.05 / this.perSlide();
    if (this.progress >= 1) { this.advance(); }
  }

  private advance(): void {
    if (this.index < this.draft.mediaFiles.length - 1) {
      this.progress = 0;
      this.index += 1;
      this.zoomIn = !this.zoomIn;
    } else {
      this.progress = 1;
      this.isPlaying = false;
      this.clearTimers();
    }
  }

  private togglePlay(): void { this.isPlaying = !this.isPlaying; }

  private replay(): void {
    this.index = 0;
    this.progress = 0;
    this.isPlaying = true;
    this.startTimer();
  }

  private clearTimers(): void {
    if (this.timerId !== -1) { clearInterval(this.timerId); this.timerId = -1; }
    if (this.introTimerId !== -1) { clearTimeout(this.introTimerId); this.introTimerId = -1; }
  }
}
