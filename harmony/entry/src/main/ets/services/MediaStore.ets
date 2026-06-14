import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import type { common } from '@kit.AbilityKit';

// MARK: - 媒体存储（对照 iOS MediaStore）
// 把照片/视频/音频落到应用沙盒 filesDir/Media 下，返回相对文件名。离线优先、永不丢。
// 目录结构：filesDir/Media/<原文件>，filesDir/Thumbnails/<缩略图>（对照 iOS Documents/Media、Documents/Thumbnails）。
export class MediaStore {
  static readonly shared = new MediaStore();
  // iOS: publicUploadSoftLimitBytes
  static readonly publicUploadSoftLimitBytes: number = 96 * 1048576;

  private baseDir: string = '';
  private thumbDir: string = '';
  private cacheBase: string = '';

  private constructor() {}

  initialize(context: common.UIAbilityContext): void {
    this.baseDir = context.filesDir + '/Media';
    this.thumbDir = context.filesDir + '/Thumbnails';
    this.cacheBase = context.cacheDir;
    MediaStore.ensureDir(this.baseDir);
    MediaStore.ensureDir(this.thumbDir);
  }

  private static ensureDir(dir: string): void {
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir);
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

  // MARK: 路径解析（对照 iOS mediaURL/thumbnailURL）

  // 缩略图绝对路径。
  thumbnailPath(fileName: string): string {
    return `${this.thumbDir}/${fileName}`;
  }

  // 应用 cache 目录（导出临时文件用，对照 iOS FileManager.temporaryDirectory）。
  cacheDir(): string {
    return this.cacheBase;
  }

  // MARK: 写入（对照 iOS savePhoto / saveBlob / importAudio）

  // iOS: func savePhoto(_ data:preferredExtension:) —— 按数据真实格式嗅探扩展名。
  savePhoto(data: ArrayBuffer, preferredExtension: string = 'jpg'): string | null {
    if (this.baseDir.length === 0) return null;
    const ext = MediaStore.sniffImageExtension(data) ?? preferredExtension;
    const name = `${util.generateRandomUUID(true)}.${ext}`;
    return this.writeData(`${this.baseDir}/${name}`, data) ? name : null;
  }

  // iOS: func saveBlob(_ data:preferredExtension:) —— 任意二进制（时间胶囊加密载荷）。
  saveBlob(data: ArrayBuffer, preferredExtension: string = 'capsule'): string | null {
    if (this.baseDir.length === 0) return null;
    const name = `${util.generateRandomUUID(true)}.${preferredExtension}`;
    return this.writeData(`${this.baseDir}/${name}`, data) ? name : null;
  }

  // iOS: func importAudio(from:) —— 录音临时文件移入沙盒，返回 voice_*.m4a。
  importAudio(srcUri: string): string | null {
    if (this.baseDir.length === 0) return null;
    const name = `voice_${util.generateRandomUUID(true)}.m4a`;
    return this.copyFile(srcUri, `${this.baseDir}/${name}`) ? name : null;
  }

  // iOS: func importFile(from:preferredExtension:)
  importFile(srcUri: string, preferredExtension: string): string | null {
    return this.copyIntoStore(srcUri, preferredExtension);
  }

  private writeData(path: string, data: ArrayBuffer): boolean {
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, data);
      fileIo.closeSync(file);
      return true;
    } catch (e) {
      return false;
    }
  }

  private copyFile(srcUri: string, dst: string): boolean {
    try {
      if (fileIo.accessSync(dst)) {
        fileIo.unlinkSync(dst);
      }
      const src = fileIo.openSync(srcUri, fileIo.OpenMode.READ_ONLY);
      const out = fileIo.openSync(dst, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      fileIo.copyFileSync(src.fd, out.fd);
      fileIo.closeSync(src);
      fileIo.closeSync(out);
      return true;
    } catch (e) {
      return false;
    }
  }

  // iOS: static func sniffImageExtension(_ data:) —— 按文件头识别 JPEG/PNG/GIF/HEIC/AVIF。
  static sniffImageExtension(data: ArrayBuffer): string | null {
    if (data.byteLength < 12) return null;
    const b = new Uint8Array(data.slice(0, 12));
    if (b[0] === 0xFF && b[1] === 0xD8) return 'jpg';
    if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4E && b[3] === 0x47) return 'png';
    if (b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46) return 'gif';
    // ISO BMFF：offset 4 起为 "ftyp"，再看 brand。
    if (b[4] === 0x66 && b[5] === 0x74 && b[6] === 0x79 && b[7] === 0x70) {
      const brand = String.fromCharCode(b[8], b[9], b[10], b[11]);
      if (brand.startsWith('heic') || brand.startsWith('heix') || brand.startsWith('mif1')) return 'heic';
      if (brand.startsWith('avif')) return 'avif';
    }
    return null;
  }

  // MARK: 读取（对照 iOS data(forMedia:) / blob(named:)）

  // 读取媒体二进制（同步）。
  dataForMedia(fileName: string): ArrayBuffer | null {
    return MediaStore.readFile(`${this.baseDir}/${fileName}`);
  }

  // iOS: func blob(named:)
  blob(fileName: string): ArrayBuffer | null {
    return MediaStore.readFile(`${this.baseDir}/${fileName}`);
  }

  private static readFile(path: string): ArrayBuffer | null {
    try {
      const stat = fileIo.statSync(path);
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      return buf;
    } catch (e) {
      return null;
    }
  }

  // iOS: func fileSize(forMedia:) / fileSize(at:)
  fileSizeForMedia(fileName: string): number | null {
    return MediaStore.fileSizeAt(`${this.baseDir}/${fileName}`);
  }

  static fileSizeAt(path: string): number | null {
    try {
      return fileIo.statSync(path).size;
    } catch (e) {
      return null;
    }
  }

  // MARK: 删除（对照 iOS deleteMedia/deleteThumbnail/deleteLocalFiles）

  deleteMedia(fileName: string): void {
    try { fileIo.unlinkSync(`${this.baseDir}/${fileName}`); } catch (e) {}
  }

  deleteThumbnail(fileName: string): void {
    try { fileIo.unlinkSync(`${this.thumbDir}/${fileName}`); } catch (e) {}
  }

  deleteLocalFiles(mediaFileName?: string, thumbnailName?: string): void {
    if (mediaFileName) this.deleteMedia(mediaFileName);
    if (thumbnailName) this.deleteThumbnail(thumbnailName);
  }

  // MARK: 缩略图（对照 iOS makePhotoThumbnail / makeVideoThumbnail）

  // iOS: func makePhotoThumbnail(fromImage:maxPixel:) —— 等比缩放并写 jpg，返回 thumb_*.jpg。
  // 此处接收已解码的 PixelMap（由 ThumbnailProvider 降采样得到），编码为 jpg 落盘。
  async makePhotoThumbnailFromPixelMap(pixelMap: image.PixelMap, maxPixel: number = 600): Promise<string | null> {
    if (this.thumbDir.length === 0) return null;
    let packer: image.ImagePacker | null = null;
    try {
      packer = image.createImagePacker();
      const opts: image.PackingOption = { format: 'image/jpeg', quality: 70 };
      const buf: ArrayBuffer = await packer.packing(pixelMap, opts);
      const name = `thumb_${util.generateRandomUUID(true)}.jpg`;
      const ok = this.writeData(`${this.thumbDir}/${name}`, buf);
      return ok ? name : null;
    } catch (e) {
      return null;
    } finally {
      if (packer) {
        try { packer.release(); } catch (e) {}
      }
    }
  }

  // iOS: func makeVideoThumbnail(fromVideo:maxPixel:) —— 取视频首帧，落盘 jpg。
  // 取帧逻辑在 ThumbnailProvider.videoFrame（@kit.MediaKit AVImageGenerator），此处只负责落盘。
  async makeVideoThumbnailFromFrame(frame: image.PixelMap, maxPixel: number = 600): Promise<string | null> {
    return await this.makePhotoThumbnailFromPixelMap(frame, maxPixel);
  }
}
