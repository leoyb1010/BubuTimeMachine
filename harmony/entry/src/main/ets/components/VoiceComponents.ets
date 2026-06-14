import { BubuColor, BubuRadius } from '../theme/BubuTheme';
import { AudioPlayer } from '../services/media/AudioPlayer';
import { AudioRecorder, RecorderState, RecordResult } from '../services/AudioRecorder';
import { MediaStore } from '../services/MediaStore';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

// MARK: - 波形视图（对照 iOS DesignSystem/Components/VoiceComponents.swift WaveformView）
// 把 0...1 的采样画成一排圆角竖条；可选高亮已播放比例（progress）。
// iOS 用 HStack + Capsule；ArkUI 用 Canvas 逐条绘制（更省节点、对应 ArkUI 推荐）。
@Component
export struct WaveformView {
  @Require @Prop @Watch('onDataChange') samples: number[];
  @Prop @Watch('onDataChange') progress: number = 1;             // 0...1 已播放比例高亮
  @Prop color: string = BubuColor.primary;
  @Prop barWidth: number = 3;
  @Prop spacing: number = 2;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;

  // samples / progress 变更时重绘（Canvas onReady 只触发一次，故用 @Watch 主动重绘）。
  onDataChange(): void {
    if (this.ready) {
      this.draw();
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .onReady(() => { this.ready = true; this.draw(); })
  }

  private draw(): void {
    const ctx = this.ctx;
    const w = ctx.width;
    const h = ctx.height;
    ctx.clearRect(0, 0, w, h);
    const count = this.samples.length;
    if (count === 0) return;

    const step = this.barWidth + this.spacing;
    const totalW = count * step - this.spacing;
    // 居中起点（iOS HStack 居中对齐）。
    let x = Math.max(0, (w - totalW) / 2);
    const radius = this.barWidth / 2;

    for (let i = 0; i < count; i++) {
      const ratio = i / Math.max(count - 1, 1);
      const played = ratio <= this.progress;
      const barH = Math.max(3, this.samples[i] * h);
      const y = (h - barH) / 2;
      ctx.fillStyle = played ? this.color : this.colorAlpha(this.color, 0.25);
      this.roundedBar(ctx, x, y, this.barWidth, barH, radius);
      x += step;
    }
  }

  private roundedBar(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
    const rr = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + rr, y);
    ctx.arcTo(x + w, y, x + w, y + h, rr);
    ctx.arcTo(x + w, y + h, x, y + h, rr);
    ctx.arcTo(x, y + h, x, y, rr);
    ctx.arcTo(x, y, x + w, y, rr);
    ctx.closePath();
    ctx.fill();
  }

  // color.opacity(a) —— 在 #RRGGBB 前拼 alpha。
  private colorAlpha(color: string, a: number): string {
    const hex = color.startsWith('#') ? color.slice(1) : color;
    const rgb = hex.length >= 6 ? hex.slice(hex.length - 6) : hex;
    const av = Math.round(a * 255).toString(16).padStart(2, '0').toUpperCase();
    return `#${av}${rgb}`;
  }
}

// MARK: - 语音录制条（对照 iOS VoiceRecorderBar）
// 一键录音 → 实时波形 + 计时 → 停止。回调返回（沙盒文件名、时长、波形）。
// iOS 用 @State recorder=AudioRecorder()；HarmonyOS 用单例 AudioRecorder.shared + 0.1s UI 轮询同步状态。
@Component
export struct VoiceRecorderBar {
  @Prop tint: string = BubuColor.primary;
  // iOS: onFinished(fileName, duration, waveform)
  onFinished?: (fileName: string, duration: number, waveform: number[]) => void;

  @State private isRecording: boolean = false;
  @State private elapsed: number = 0;
  @State private levels: number[] = [];
  private uiTimer: number = -1;

  aboutToDisappear(): void {
    this.stopUITimer();
  }

  private startUITimer(): void {
    this.stopUITimer();
    this.uiTimer = setInterval(() => {
      const rec = AudioRecorder.shared;
      this.isRecording = rec.state === RecorderState.recording;
      this.elapsed = rec.elapsed;
      // 取尾部 30 个电平驱动实时波形（对照 iOS levels.suffix(30)）。
      const all = rec.currentLevels;
      this.levels = all.length > 30 ? all.slice(all.length - 30) : all.slice();
      if (!this.isRecording) {
        this.stopUITimer();
      }
    }, 100);
  }

  private stopUITimer(): void {
    if (this.uiTimer >= 0) {
      clearInterval(this.uiTimer);
      this.uiTimer = -1;
    }
  }

  private timeString(t: number): string {
    const s = Math.floor(t);
    const m = Math.floor(s / 60);
    const sec = s % 60;
    return `${m}:${sec < 10 ? '0' : ''}${sec}`;
  }

  private async toggle(): Promise<void> {
    const rec = AudioRecorder.shared;
    if (rec.state === RecorderState.recording) {
      const result: RecordResult | null = await rec.stop();
      this.stopUITimer();
      this.isRecording = false;
      if (result && this.onFinished) {
        // AudioRecorder.stop 已将文件落在沙盒并返回 fileName（对照 iOS importFile）。
        this.onFinished(result.fileName, result.durationSec, result.waveform);
      }
    } else {
      // NOTE: requestPermission 需 UIAbilityContext，运行期由宿主 getContext 提供。
      const ctx = getContext(this) as common.UIAbilityContext;
      const granted = await rec.requestPermission(ctx);
      if (granted) {
        const ok = await rec.start();
        if (ok) {
          this.isRecording = true;
          this.startUITimer();
        }
      } else {
        promptAction.showToast({ message: '请到系统设置里允许布布时光机使用麦克风。' });
      }
    }
  }

  build() {
    Row({ space: 14 }) {
      // 录音按钮（iOS mic.circle.fill / stop.circle.fill）。
      Text(this.isRecording ? '⏹' : '🎙')
        .fontSize(40)
        .fontColor(this.isRecording ? Color.Red : this.tint)
        .onClick(() => { this.toggle(); })

      if (this.isRecording) {
        WaveformView({ samples: this.levels, color: this.tint })
          .height(36)
          .layoutWeight(1)
        Text(this.timeString(this.elapsed))
          .fontSize(16)
          .fontColor(BubuColor.secondaryText)
      } else {
        Text('点一下开始，再点一下收好')
          .fontSize(15)
          .fontColor(BubuColor.secondaryText)
        Blank()
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(16)
    .backgroundColor(BubuColor.card)
    .borderRadius(BubuRadius.card)
    .shadow({ radius: 10, color: '#14000000', offsetY: 3 })
  }
}

// MARK: - 语音播放气泡（对照 iOS VoicePlayerBubble）
// 展示已录语音：播放按钮 + 波形 + 时长。
// iOS 用 @State player=AudioPlayer()；HarmonyOS 用单例 AudioPlayer.shared + listener 订阅进度。
@Component
export struct VoicePlayerBubble {
  @Require @Prop fileName: string;
  @Prop duration: number = 0;
  @Prop waveform: number[] = [];
  @Prop tint: string = BubuColor.primary;

  @State private isPlayingThis: boolean = false;
  @State private progress: number = 0;

  private path(): string {
    return MediaStore.shared.fullPath(this.fileName);
  }

  aboutToAppear(): void {
    // 订阅播放进度（对照 iOS @Observable player.progress / isPlaying / playingURL）。
    AudioPlayer.shared.setListener((progress: number, isPlaying: boolean, playingPath: string | null) => {
      const mine = playingPath === this.path();
      this.isPlayingThis = isPlaying && mine;
      this.progress = mine ? progress : 0;
    });
  }

  aboutToDisappear(): void {
    AudioPlayer.shared.setListener(null);
  }

  private timeString(t: number): string {
    const s = Math.round(t);
    const m = Math.floor(s / 60);
    const sec = s % 60;
    return `${m}:${sec < 10 ? '0' : ''}${sec}`;
  }

  private displaySamples(): number[] {
    if (this.waveform.length > 0) return this.waveform;
    // iOS: waveform.isEmpty ? Array(repeating: 0.3, count: 20)
    const fallback: number[] = [];
    for (let i = 0; i < 20; i++) fallback.push(0.3);
    return fallback;
  }

  build() {
    Row({ space: 12 }) {
      Text(this.isPlayingThis ? '⏸' : '▶')
        .fontSize(32)
        .fontColor(this.tint)
        .onClick(() => { AudioPlayer.shared.toggle(this.path()); })

      WaveformView({
        samples: this.displaySamples(),
        progress: this.isPlayingThis ? this.progress : 0,
        color: this.tint
      })
        .height(30)
        .layoutWeight(1)

      Text(this.timeString(this.duration))
        .fontSize(14)
        .fontColor(BubuColor.secondaryText)
    }
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(this.tintAlpha(this.tint, 0.08))
    .borderRadius(100) // Capsule
  }

  private tintAlpha(color: string, a: number): string {
    const hex = color.startsWith('#') ? color.slice(1) : color;
    const rgb = hex.length >= 6 ? hex.slice(hex.length - 6) : hex;
    const av = Math.round(a * 255).toString(16).padStart(2, '0').toUpperCase();
    return `#${av}${rgb}`;
  }
}
