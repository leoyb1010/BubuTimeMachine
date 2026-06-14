import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MediaStore } from '../MediaStore';

const DOMAIN = 0x0000;

// MARK: - 缩略图提供者（对照 iOS Services/Media/ThumbnailProvider.swift）
// 统一的图片解码与缓存层（Wave I 流畅度工程核心）。
// 四件事：内存缓存 / 降采样解码 / 缺缩略图落盘补齐 / 预取。
// iOS 用 NSCache + ImageIO CGImageSourceCreateThumbnailAtIndex + actor 后台隔离；
// HarmonyOS 用 Map 内存缓存 + @kit.ImageKit image.ImageSource 的 desiredSize 降采样 +
// Promise 异步（天然不阻塞 UI 线程）。

// iOS: enum SizeClass —— 像素档位
export enum SizeClass {
  grid = 'grid',     // 照片墙网格 cell（小）
  card = 'card',     // 时光轴卡片大图（中）
  detail = 'detail'  // 详情/查看器（大）
}

export function sizeClassMaxPixel(s: SizeClass): number {
  switch (s) {
    case SizeClass.grid: return 320;
    case SizeClass.card: return 900;
    case SizeClass.detail: return 1800;
    default: return 900;
  }
}

// iOS: struct Ref —— 预取入参快照
export interface ThumbnailRef {
  mediaId: string;
  thumbnailFileName?: string;
  localFileName?: string;
  isPhoto: boolean;
}

// 缩略图补齐回传：后台补齐的缩略图文件名回到上层，由调用方更新 Media.thumbnailFileName。
// iOS: ThumbnailBackfillBus（轻量内存队列）。
export type BackfillHandler = (mediaId: string, thumbnailFileName: string) => void;

export class ThumbnailBackfillBus {
  static readonly shared = new ThumbnailBackfillBus();
  private pending: Array<[string, string]> = [];
  private onRecord: BackfillHandler | null = null;

  private constructor() {}

  setHandler(handler: BackfillHandler | null): void {
    this.onRecord = handler;
  }

  record(mediaId: string, thumbnailFileName: string): void {
    const h = this.onRecord;
    if (h) {
      h(mediaId, thumbnailFileName);
    } else {
      this.pending.push([mediaId, thumbnailFileName]);
    }
  }

  // 订阅方就绪后排空积压。
  drain(handler: BackfillHandler): void {
    for (const item of this.pending) {
      handler(item[0], item[1]);
    }
    this.pending = [];
  }
}

export class ThumbnailProvider {
  static readonly shared = new ThumbnailProvider();

  private store: MediaStore = MediaStore.shared;
  // 内存缓存：key = "<mediaId>|<sizeClass>" → PixelMap
  private cache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  // 同一 key 正在进行的解码任务，避免重复解码。
  private inFlight: Map<string, Promise<image.PixelMap | null>> = new Map<string, Promise<image.PixelMap | null>>();
  // 粗略 LRU：键插入顺序 + 上限张数（NSCache 按字节，这里按张数简化）。
  private static readonly maxEntries = 120;

  private constructor() {}

  // iOS: func image(mediaId:thumbnailFileName:localFileName:isPhoto:size:)
  async image(mediaId: string, thumbnailFileName: string | undefined,
              localFileName: string | undefined, isPhoto: boolean,
              size: SizeClass): Promise<image.PixelMap | null> {
    const key = this.cacheKey(mediaId, size);
    const cached = this.cache.get(key);
    if (cached) return cached;

    const running = this.inFlight.get(key);
    if (running) return running;

    const maxPixel = sizeClassMaxPixel(size);
    const thumbPath = thumbnailFileName ? this.store.thumbnailPath(thumbnailFileName) : null;
    const mediaPath = localFileName ? this.store.fullPath(localFileName) : null;

    const task: Promise<image.PixelMap | null> = (async (): Promise<image.PixelMap | null> => {
      // 1) 已有落盘缩略图：降采样解码。
      if (thumbPath && ThumbnailProvider.fileExists(thumbPath)) {
        const img = await ThumbnailProvider.downsample(thumbPath, maxPixel);
        if (img) return img;
      }
      // 2) 无缩略图：从原图降采样到目标档位。
      if (mediaPath && ThumbnailProvider.fileExists(mediaPath)) {
        return await ThumbnailProvider.downsample(mediaPath, maxPixel);
      }
      return null;
    })();

    this.inFlight.set(key, task);
    const result = await task;
    this.inFlight.delete(key);

    if (result) {
      this.setCache(key, result);
      // 缺缩略图时后台补齐落盘，下次命中（不阻塞本次返回）。
      if (thumbnailFileName === undefined && localFileName && isPhoto) {
        this.backfillThumbnail(mediaId, localFileName);
      }
    }
    return result;
  }

  // iOS: func prefetch(_ refs:size:)
  prefetch(refs: ThumbnailRef[], size: SizeClass): void {
    for (const r of refs) {
      const key = this.cacheKey(r.mediaId, size);
      if (this.cache.has(key) || this.inFlight.has(key)) continue;
      this.image(r.mediaId, r.thumbnailFileName, r.localFileName, r.isPhoto, size);
    }
  }

  // 主动清缓存（对应 iOS 收到内存警告时 NSCache 自动驱逐）。
  clearCache(): void {
    this.cache.clear();
  }

  // iOS: backfillThumbnail —— 后台为缺失缩略图的老数据生成缩略图并写回沙盒。
  private backfillThumbnail(mediaId: string, mediaName: string): void {
    const mediaPath = this.store.fullPath(mediaName);
    (async (): Promise<void> => {
      try {
        const img = await ThumbnailProvider.downsample(mediaPath, 600);
        if (!img) return;
        const name = await this.store.makePhotoThumbnailFromPixelMap(img, 600);
        if (name) {
          ThumbnailBackfillBus.shared.record(mediaId, name);
        }
      } catch (e) {
        hilog.error(DOMAIN, 'Bubu', `缩略图补齐失败: ${JSON.stringify(e)}`);
      }
    })();
  }

  // MARK: 工具

  private cacheKey(mediaId: string, size: SizeClass): string {
    return `${mediaId}|${size}`;
  }

  private setCache(key: string, value: image.PixelMap): void {
    if (this.cache.size >= ThumbnailProvider.maxEntries) {
      // 粗略 LRU：删最早插入的一项。
      const firstKey: string | undefined = this.cache.keys().next().value as string | undefined;
      if (firstKey !== undefined) {
        const old = this.cache.get(firstKey);
        this.cache.delete(firstKey);
        if (old) {
          try { old.release(); } catch (e) {}
        }
      }
    }
    this.cache.set(key, value);
  }

  private static fileExists(path: string): boolean {
    try {
      return fileIo.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  // iOS: nonisolated static func downsample(url:maxPixel:)
  // ImageIO 降采样 → @kit.ImageKit image.ImageSource：先读尺寸，按长边算 desiredSize 直接解到目标像素。
  static async downsample(path: string, maxPixel: number): Promise<image.PixelMap | null> {
    let source: image.ImageSource | null = null;
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const info: image.ImageInfo = await source.getImageInfo();
      const w = info.size.width;
      const h = info.size.height;
      const longSide = Math.max(w, h);
      const opts: image.DecodingOptions = {};
      if (longSide > maxPixel && longSide > 0) {
        const scale = maxPixel / longSide;
        opts.desiredSize = {
          width: Math.max(1, Math.round(w * scale)),
          height: Math.max(1, Math.round(h * scale))
        };
      }
      const pixelMap = await source.createPixelMap(opts);
      fileIo.closeSync(file);
      return pixelMap;
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `降采样失败: ${JSON.stringify(e)}`);
      return null;
    } finally {
      if (source) {
        try { source.release(); } catch (e) {}
      }
    }
  }

  // 视频首帧缩略图（对照 iOS MediaStore.makeVideoThumbnail 用 AVAssetImageGenerator）。
  // HarmonyOS: @kit.MediaKit media.AVImageGenerator，取 0 时刻帧。
  static async videoFrame(videoPath: string, maxPixel: number): Promise<image.PixelMap | null> {
    let generator: media.AVImageGenerator | null = null;
    try {
      const file = fileIo.openSync(videoPath, fileIo.OpenMode.READ_ONLY);
      const size: number = fileIo.statSync(file.fd).size;
      generator = await media.createAVImageGenerator();
      generator.fdSrc = { fd: file.fd, offset: 0, length: size };
      const queryOpts: media.AVImageQueryOptions = media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC;
      const param: media.PixelMapParams = {
        width: maxPixel,
        height: maxPixel
      };
      const pixelMap: image.PixelMap = await generator.fetchFrameByTime(0, queryOpts, param);
      fileIo.closeSync(file);
      return pixelMap;
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `视频取帧失败: ${JSON.stringify(e)}`);
      return null;
    } finally {
      if (generator) {
        try { await generator.release(); } catch (e) {}
      }
    }
  }
}
