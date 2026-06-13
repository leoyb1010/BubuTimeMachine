import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MediaStore } from './MediaStore';

const DOMAIN = 0x0000;

// MARK: - 录音器（对照 iOS AudioRecorder）
// AVRecorder 录 m4a 到沙盒。一键开始/停止，返回文件名 + 时长。
export class AudioRecorder {
  static readonly shared = new AudioRecorder();
  private recorder: media.AVRecorder | null = null;
  private filePath: string = '';
  private fileFd: number = -1;
  private startedAt: number = 0;

  private constructor() {}

  get isRecording(): boolean {
    return this.recorder !== null;
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
      return true;
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `录音启动失败: ${JSON.stringify(e)}`);
      this.cleanup();
      return false;
    }
  }

  // 停止，返回 {fileName, durationSec}
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
    this.cleanup();
    return { fileName, durationSec: dur };
  }

  async cancel(): Promise<void> {
    if (this.recorder) {
      try { await this.recorder.stop(); await this.recorder.release(); } catch (e) {}
    }
    this.cleanup();
  }

  private cleanup(): void {
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
}
