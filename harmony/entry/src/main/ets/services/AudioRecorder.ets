import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { MediaStore } from './MediaStore';

const DOMAIN = 0x0000;

// MARK: - 录音器（对照 iOS AudioRecorder）
// AVRecorder 录 m4a 到沙盒。一键开始/停止，返回文件名 + 时长 + 波形采样。
// iOS 用 AVAudioRecorder + isMeteringEnabled 实时电平驱动波形；
// HarmonyOS 用 AVRecorder.getAudioCapturerMaxAmplitude() 轮询峰值幅度归一化为 0...1。

// iOS: enum State { idle, recording, finished }
export enum RecorderState {
  idle = 'idle',
  recording = 'recording',
  finished = 'finished'
}

export class AudioRecorder {
  static readonly shared = new AudioRecorder();
  private recorder: media.AVRecorder | null = null;
  private filePath: string = '';
  private fileFd: number = -1;
  private startedAt: number = 0;

  // iOS: private(set) var state / elapsed / levels
  private stateValue: RecorderState = RecorderState.idle;
  private elapsedValue: number = 0;          // 秒
  private levels: number[] = [];             // 实时电平（0...1），驱动波形
  private timer: number = -1;

  private constructor() {}

  get isRecording(): boolean {
    return this.recorder !== null;
  }

  // iOS: state / elapsed / levels（只读暴露给 UI）
  get state(): RecorderState {
    return this.stateValue;
  }

  get elapsed(): number {
    return this.elapsedValue;
  }

  get currentLevels(): number[] {
    return this.levels;
  }

  // iOS: func requestPermission() async -> Bool
  // AVAudioApplication.requestRecordPermission → HarmonyOS abilityAccessCtrl 申请 MICROPHONE。
  async requestPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const mgr = abilityAccessCtrl.createAtManager();
      const perms: Permissions[] = ['ohos.permission.MICROPHONE'];
      const result = await mgr.requestPermissionsFromUser(context, perms);
      const granted = result.authResults;
      return granted.length > 0 && granted[0] === 0;
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `麦克风授权失败: ${JSON.stringify(e)}`);
      return false;
    }
  }

  async start(): Promise<boolean> {
    try {
      this.filePath = MediaStore.shared.newAudioPath();
      const file = fileIo.openSync(this.filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      this.fileFd = file.fd;

      const rec = await media.createAVRecorder();
      const config: media.AVRecorderConfig = {
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: {
          audioBitrate: 48000,
          audioChannels: 1,
          audioCodec: media.CodecMimeType.AUDIO_AAC,
          audioSampleRate: 44100,
          fileFormat: media.ContainerFormatType.CFT_MPEG_4A
        },
        url: `fd://${this.fileFd}`
      };
      await rec.prepare(config);
      await rec.start();
      this.recorder = rec;
      this.startedAt = Date.now();
      this.stateValue = RecorderState.recording;
      this.elapsedValue = 0;
      this.levels = [];
      this.startTimer();
      return true;
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `录音启动失败: ${JSON.stringify(e)}`);
      this.cleanup();
      return false;
    }
  }

  // iOS: func stop() -> (url, duration, waveform)?
  // 停止，返回 {fileName, durationSec, waveform}
  async stop(): Promise<RecordResult | null> {
    if (!this.recorder) return null;
    try {
      await this.recorder.stop();
      await this.recorder.release();
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `录音停止异常: ${JSON.stringify(e)}`);
    }
    const dur = Math.round((Date.now() - this.startedAt) / 1000);
    const fileName = this.filePath.split('/').pop() ?? '';
    // iOS: downsample(levels, to: 40)
    const waveform = AudioRecorder.downsample(this.levels, 40);
    this.stateValue = RecorderState.finished;
    this.cleanup();
    return { fileName, durationSec: dur, waveform };
  }

  async cancel(): Promise<void> {
    if (this.recorder) {
      try { await this.recorder.stop(); await this.recorder.release(); } catch (e) {}
    }
    // iOS: 删除临时录音文件。
    const p = this.filePath;
    this.cleanup();
    this.stateValue = RecorderState.idle;
    if (p.length > 0) {
      try { fileIo.unlinkSync(p); } catch (e) {}
    }
  }

  // iOS: static func timeText(_ seconds:) -> "m:ss"
  static timeText(seconds: number): string {
    const total = Math.floor(seconds);
    const m = Math.floor(total / 60);
    const s = total % 60;
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  }

  // iOS: startTimer() —— 0.05s 采电平 + 累计时长
  private startTimer(): void {
    this.stopTimer();
    this.timer = setInterval(() => {
      this.tick();
    }, 50);
  }

  private stopTimer(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  // iOS: tick() —— updateMeters → averagePower(dB) → 归一化 0...1
  private async tick(): Promise<void> {
    const rec = this.recorder;
    if (!rec || this.stateValue !== RecorderState.recording) return;
    this.elapsedValue = (Date.now() - this.startedAt) / 1000;
    let normalized = 0;
    try {
      // getAudioCapturerMaxAmplitude 返回 0...1 的峰值幅度（部分 SDK 返回原始 PCM 峰值）。
      // NOTE: 不同 SDK 量纲可能不同，这里裁剪到 0...1 与 iOS averagePower 映射后的取值范围对齐。
      const amp: number = await rec.getAudioCapturerMaxAmplitude();
      normalized = Math.max(0, Math.min(1, amp));
    } catch (e) {
      normalized = 0;
    }
    this.levels.push(normalized);
  }

  // iOS: func downsample(_ samples:to:) —— 密集电平降采样为固定数量波形条。
  static downsample(samples: number[], count: number): number[] {
    if (samples.length <= count || count <= 0) return samples;
    const bucket = Math.floor(samples.length / count);
    const out: number[] = [];
    for (let i = 0; i < count; i++) {
      const start = i * bucket;
      const end = Math.min((i + 1) * bucket, samples.length);
      const slice = samples.slice(start, end);
      if (slice.length === 0) {
        out.push(0);
      } else {
        const sum = slice.reduce((a: number, b: number): number => a + b, 0);
        out.push(sum / slice.length);
      }
    }
    return out;
  }

  private cleanup(): void {
    this.stopTimer();
    if (this.fileFd >= 0) {
      try { fileIo.closeSync(this.fileFd); } catch (e) {}
    }
    this.fileFd = -1;
    this.recorder = null;
    this.startedAt = 0;
  }
}

export interface RecordResult {
  fileName: string;
  durationSec: number;
  waveform: number[];
}
