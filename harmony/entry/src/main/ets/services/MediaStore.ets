import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import type { common } from '@kit.AbilityKit';

// MARK: - 媒体存储（对照 iOS MediaStore）
// 把照片/视频/音频落到应用沙盒 filesDir/Media 下，返回相对文件名。离线优先、永不丢。
export class MediaStore {
  static readonly shared = new MediaStore();
  private baseDir: string = '';

  private constructor() {}

  initialize(context: common.UIAbilityContext): void {
    this.baseDir = context.filesDir + '/Media';
    try {
      if (!fileIo.accessSync(this.baseDir)) {
        fileIo.mkdirSync(this.baseDir);
      }
    } catch (e) {
      // 目录已存在等忽略
    }
  }

  // 把一个临时/源文件拷进沙盒，返回相对文件名
  copyIntoStore(srcUri: string, ext: string): string | null {
    if (this.baseDir.length === 0) return null;
    const name = `${util.generateRandomUUID(true)}.${ext}`;
    const dst = `${this.baseDir}/${name}`;
    try {
      const src = fileIo.openSync(srcUri, fileIo.OpenMode.READ_ONLY);
      const out = fileIo.openSync(dst, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      fileIo.copyFileSync(src.fd, out.fd);
      fileIo.closeSync(src);
      fileIo.closeSync(out);
      return name;
    } catch (e) {
      return null;
    }
  }

  fullPath(fileName: string): string {
    return `${this.baseDir}/${fileName}`;
  }

  exists(fileName: string): boolean {
    try {
      return fileIo.accessSync(`${this.baseDir}/${fileName}`);
    } catch (e) {
      return false;
    }
  }

  // 给录音分配一个落盘路径
  newAudioPath(): string {
    const name = `voice_${util.generateRandomUUID(true)}.m4a`;
    return `${this.baseDir}/${name}`;
  }
}
