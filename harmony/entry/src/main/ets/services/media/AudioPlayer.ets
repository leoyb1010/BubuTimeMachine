import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

// MARK: - 录音播放器（对照 iOS Services/Media/AudioPlayer.swift）
// 播放沙盒中的语音文件，发布播放进度供 UI 波形高亮。
// iOS 用 AVAudioPlayer + Timer 轮询 currentTime/duration；
// HarmonyOS 用 @kit.MediaKit 的 media.AVPlayer，进度用 0.03s 定时器读 currentTime/duration。
export type ProgressListener = (progress: number, isPlaying: boolean, playingPath: string | null) => void;

export class AudioPlayer {
  static readonly shared = new AudioPlayer();

  // iOS: private(set) var isPlaying / progress / playingURL
  private isPlayingFlag: boolean = false;
  private progressValue: number = 0; // 0...1
  private playingPath: string | null = null;

  private player: media.AVPlayer | null = null;
  private fileFd: number = -1;
  private timer: number = -1;
  private durationMs: number = 0;
  private listener: ProgressListener | null = null;

  private constructor() {}

  // 供 UI 订阅播放进度（对应 iOS @Observable 的属性观察）
  setListener(listener: ProgressListener | null): void {
    this.listener = listener;
  }

  get isPlaying(): boolean {
    return this.isPlayingFlag;
  }

  get progress(): number {
    return this.progressValue;
  }

  get playingURL(): string | null {
    return this.playingPath;
  }

  // iOS: func toggle(url:) —— 同一文件正在播则停，否则播。
  async toggle(path: string): Promise<void> {
    if (this.isPlayingFlag && this.playingPath === path) {
      await this.stop();
    } else {
      await this.play(path);
    }
  }

  // iOS: func play(url:)
  async play(path: string): Promise<void> {
    await this.stop();
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      this.fileFd = file.fd;

      const p: media.AVPlayer = await media.createAVPlayer();
      this.player = p;
      this.playingPath = path;

      // AVPlayer 状态机：initialized → prepared → playing。
      p.on('stateChange', (state: string) => {
        if (state === 'initialized') {
          p.prepare();
        } else if (state === 'prepared') {
          this.durationMs = p.duration;
          p.play();
          this.isPlayingFlag = true;
          this.startTimer();
          this.emit();
        } else if (state === 'completed') {
          // iOS: audioPlayerDidFinishPlaying → stop()
          this.stop();
        }
      });
      p.on('error', () => {
        this.stop();
      });

      p.url = `fd://${this.fileFd}`;
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `播放启动失败: ${JSON.stringify(e)}`);
      this.isPlayingFlag = false;
      this.emit();
    }
  }

  // iOS: func stop()
  async stop(): Promise<void> {
    this.stopTimer();
    if (this.player) {
      try {
        await this.player.reset();
        await this.player.release();
      } catch (e) {
        // 忽略释放异常
      }
      this.player = null;
    }
    if (this.fileFd >= 0) {
      try { fileIo.closeSync(this.fileFd); } catch (e) {}
      this.fileFd = -1;
    }
    this.isPlayingFlag = false;
    this.progressValue = 0;
    this.playingPath = null;
    this.durationMs = 0;
    this.emit();
  }

  // iOS: startTimer() —— 0.03s 间隔
  private startTimer(): void {
    this.stopTimer();
    this.timer = setInterval(() => {
      this.tick();
    }, 30);
  }

  private stopTimer(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  // iOS: tick() —— progress = currentTime / duration
  private tick(): void {
    const p = this.player;
    if (!p || this.durationMs <= 0) return;
    this.progressValue = p.currentTime / this.durationMs;
    this.emit();
  }

  private emit(): void {
    if (this.listener) {
      this.listener(this.progressValue, this.isPlayingFlag, this.playingPath);
    }
  }
}
