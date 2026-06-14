import { drawing, common2D } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MediaStore } from '../MediaStore';
import { ThumbnailProvider } from './ThumbnailProvider';

const DOMAIN = 0x0000;

// MARK: - 年册导出（对照 iOS Services/Media/YearbookExporter.swift）
// 选一个年龄段，把布布这一年导出：封面 + 记录页 + 里程碑 + 家人寄语。
// iOS 用 ImageRenderer 逐页渲染 SwiftUI 视图进 UIGraphicsPDFRenderer 输出单个 PDF。
// NOTE: PDF→图片 —— HarmonyOS 当前无稳定的「视图渲染进 PDF」等价 API。
//   这里用 @kit.ArkGraphics2D drawing 把每页画到一张 A4 像素图（595×842 @2x），
//   逐页导出 PNG（page-1.png ...）到 cacheDir 下的年册目录，返回该目录路径。
//   待 HarmonyOS PDF 生成 API 稳定后，可把这些页面合成单个 PDF。

// A4 @ 72dpi（与 iOS pageSize 一致）
const PAGE_W = 595;
const PAGE_H = 842;
const SCALE = 2;

// iOS: struct Page
export interface YearbookPage {
  date: number;
  note?: string;
  ageText: string;
  authorRole: string;
  imageFileNames: string[];
  mood?: string;
}

// iOS: struct Input
export interface YearbookInput {
  childName: string;
  rangeTitle: string;            // 「1 岁这一年」
  coverImageFileName?: string;
  entries: YearbookPage[];
  milestones: string[];          // 已点亮里程碑标题
  messages: string[];            // 家人寄语
  primaryColorHex: string;       // 对照 iOS theme.primary
  secondaryColorHex: string;     // 对照 iOS theme.secondary
}

const WARM_BROWN = 0xFF5C4D47;
const PAGE_BG = 0xFFFFFDF8;
const SECONDARY_TEXT = 0xFF8A8079;

export class YearbookExporter {
  static readonly shared = new YearbookExporter();
  private mediaStore: MediaStore = MediaStore.shared;

  private constructor() {}

  // iOS: func makePDF(_ input:) -> URL?
  // 返回导出目录路径（含 page-N.png）；失败返回 null。
  async makePDF(input: YearbookInput): Promise<string | null> {
    try {
      const cacheBase = this.mediaStore.cacheDir();
      const dir = `${cacheBase}/布布年册-${input.rangeTitle}-${Math.floor(Date.now() / 1000)}`;
      YearbookExporter.mkdirp(dir);

      let pageIndex = 0;
      const primary = YearbookExporter.hexToArgb(input.primaryColorHex, 0xFFF28C9E);

      // 封面
      const cover = await this.loadImage(input.coverImageFileName);
      await this.drawCoverPage(dir, pageIndex++, input, primary, cover);

      // 记录页：每页一条（含照片 + 文字）。
      for (const entry of input.entries) {
        const images: image.PixelMap[] = [];
        for (const name of entry.imageFileNames.slice(0, 4)) {
          const img = await this.loadImage(name);
          if (img) images.push(img);
        }
        await this.drawEntryPage(dir, pageIndex++, entry, primary, images);
      }

      if (input.milestones.length > 0) {
        await this.drawListPage(dir, pageIndex++, '这一年的里程碑', '★', input.milestones, primary);
      }
      if (input.messages.length > 0) {
        await this.drawListPage(dir, pageIndex++, '家人想对你说', '♥', input.messages, primary);
      }

      return dir;
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `年册导出失败: ${JSON.stringify(e)}`);
      return null;
    }
  }

  // MARK: 页面绘制

  // iOS: CoverPage —— 渐变背景 + 封面图 + 名字 + 区间标题
  private async drawCoverPage(dir: string, idx: number, input: YearbookInput,
                              primary: number, cover: image.PixelMap | null): Promise<void> {
    const canvasCtx = YearbookExporter.newCanvas();
    const canvas = canvasCtx.canvas;

    // 渐变背景（primary → secondary）。
    const secondary = YearbookExporter.hexToArgb(input.secondaryColorHex, 0xFFF2B705);
    YearbookExporter.fillRect(canvas, 0, 0, PAGE_W * SCALE, PAGE_H * SCALE, primary);
    // 用半透明 secondary 覆下半屏做简单纵向渐变近似。
    YearbookExporter.fillRectAlpha(canvas, 0, PAGE_H * SCALE * 0.5, PAGE_W * SCALE, PAGE_H * SCALE * 0.5, secondary, 0.6);

    // 封面图（居中，圆角近似用方图）。
    if (cover) {
      const side = 260 * SCALE;
      const x = (PAGE_W * SCALE - side) / 2;
      const y = 200 * SCALE;
      YearbookExporter.drawImageFit(canvas, cover, x, y, side, side);
    }

    YearbookExporter.drawText(canvas, input.childName, PAGE_W * SCALE / 2, 540 * SCALE, 46 * SCALE, 0xFFFFFFFF, true);
    YearbookExporter.drawText(canvas, input.rangeTitle, PAGE_W * SCALE / 2, 590 * SCALE, 28 * SCALE, 0xFFFFFFFF, true);
    YearbookExporter.drawText(canvas, '布布时光机 · 年册', PAGE_W * SCALE / 2, 790 * SCALE, 16 * SCALE, 0xFFFFFFFF, true);

    await YearbookExporter.savePage(canvasCtx, dir, idx);
  }

  // iOS: EntryPage —— 年龄/日期 + 照片网格 + 笔记 + 署名
  private async drawEntryPage(dir: string, idx: number, entry: YearbookPage,
                              primary: number, images: image.PixelMap[]): Promise<void> {
    const canvasCtx = YearbookExporter.newCanvas();
    const canvas = canvasCtx.canvas;
    YearbookExporter.fillRect(canvas, 0, 0, PAGE_W * SCALE, PAGE_H * SCALE, PAGE_BG);

    const pad = 46 * SCALE;
    YearbookExporter.drawText(canvas, entry.ageText, pad, 70 * SCALE, 18 * SCALE, primary, false);
    YearbookExporter.drawTextRight(canvas, YearbookExporter.longDate(entry.date),
      PAGE_W * SCALE - pad, 70 * SCALE, 15 * SCALE, SECONDARY_TEXT);

    let cursorY = 110 * SCALE;
    if (images.length > 0) {
      const single = images.length === 1;
      const cellH = (single ? 360 : 220) * SCALE;
      const cols = single ? 1 : 2;
      const gap = 8 * SCALE;
      const cellW = (PAGE_W * SCALE - pad * 2 - gap * (cols - 1)) / cols;
      for (let i = 0; i < images.length; i++) {
        const col = i % cols;
        const row = Math.floor(i / cols);
        const x = pad + col * (cellW + gap);
        const y = cursorY + row * (cellH + gap);
        YearbookExporter.drawImageFit(canvas, images[i], x, y, cellW, cellH);
      }
      const rows = Math.ceil(images.length / cols);
      cursorY += rows * (cellH + gap) + 16 * SCALE;
    }

    if (entry.note && entry.note.length > 0) {
      cursorY = YearbookExporter.drawWrappedText(canvas, entry.note, pad, cursorY + 24 * SCALE,
        PAGE_W * SCALE - pad * 2, 19 * SCALE, WARM_BROWN);
    }

    const signature = `${entry.mood ?? ''} —— ${entry.authorRole}`;
    YearbookExporter.drawText(canvas, signature, pad, cursorY + 30 * SCALE, 14 * SCALE, SECONDARY_TEXT, false);

    await YearbookExporter.savePage(canvasCtx, dir, idx);
  }

  // iOS: ListPage —— 标题 + 圆点列表（里程碑 / 寄语）
  private async drawListPage(dir: string, idx: number, title: string, icon: string,
                             items: string[], primary: number): Promise<void> {
    const canvasCtx = YearbookExporter.newCanvas();
    const canvas = canvasCtx.canvas;
    YearbookExporter.fillRect(canvas, 0, 0, PAGE_W * SCALE, PAGE_H * SCALE, PAGE_BG);

    const pad = 46 * SCALE;
    YearbookExporter.drawText(canvas, `${icon} ${title}`, pad, 80 * SCALE, 26 * SCALE, WARM_BROWN, false);

    let y = 140 * SCALE;
    for (const item of items.slice(0, 14)) {
      // 圆点
      YearbookExporter.fillCircle(canvas, pad + 4 * SCALE, y - 6 * SCALE, 4 * SCALE, primary);
      y = YearbookExporter.drawWrappedText(canvas, item, pad + 18 * SCALE, y,
        PAGE_W * SCALE - pad * 2 - 18 * SCALE, 18 * SCALE, WARM_BROWN);
      y += 18 * SCALE;
    }

    await YearbookExporter.savePage(canvasCtx, dir, idx);
  }

  // iOS: loadImage —— 用 ThumbnailProvider.downsample(maxPixel:1200)
  private async loadImage(fileName: string | undefined): Promise<image.PixelMap | null> {
    if (!fileName) return null;
    const path = this.mediaStore.fullPath(fileName);
    return await ThumbnailProvider.downsample(path, 1200);
  }

  // MARK: 画布 / 绘制工具

  private static newCanvas(): CanvasContext {
    const opts: image.InitializationOptions = {
      size: { width: PAGE_W * SCALE, height: PAGE_H * SCALE },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    };
    const pixelMap = image.createPixelMapSync(opts);
    const canvas = new drawing.Canvas(pixelMap);
    return { canvas, pixelMap };
  }

  private static fillRect(canvas: drawing.Canvas, x: number, y: number, w: number, h: number, argb: number): void {
    const brush = new drawing.Brush();
    brush.setColor(YearbookExporter.argbToColor(argb));
    canvas.attachBrush(brush);
    canvas.drawRect({ left: x, top: y, right: x + w, bottom: y + h });
    canvas.detachBrush();
  }

  private static fillRectAlpha(canvas: drawing.Canvas, x: number, y: number, w: number, h: number,
                               argb: number, alpha: number): void {
    const c = YearbookExporter.argbToColor(argb);
    c.alpha = Math.round(255 * alpha);
    const brush = new drawing.Brush();
    brush.setColor(c);
    canvas.attachBrush(brush);
    canvas.drawRect({ left: x, top: y, right: x + w, bottom: y + h });
    canvas.detachBrush();
  }

  private static fillCircle(canvas: drawing.Canvas, cx: number, cy: number, r: number, argb: number): void {
    const brush = new drawing.Brush();
    brush.setColor(YearbookExporter.argbToColor(argb));
    canvas.attachBrush(brush);
    canvas.drawCircle(cx, cy, r);
    canvas.detachBrush();
  }

  private static drawImageFit(canvas: drawing.Canvas, pm: image.PixelMap,
                              x: number, y: number, w: number, h: number): void {
    try {
      const info: image.ImageInfo = pm.getImageInfoSync();
      const iw = info.size.width;
      const ih = info.size.height;
      // scaledToFill 近似：等比放大铺满目标框，超出部分忽略（drawImageRect 会拉伸，这里直接铺框）。
      canvas.drawImageRect(pm, { left: x, top: y, right: x + w, bottom: y + h });
    } catch (e) {
      // 绘图失败留空。
    }
  }

  private static drawText(canvas: drawing.Canvas, text: string, x: number, y: number,
                          fontSize: number, argb: number, centered: boolean): void {
    if (text.length === 0) return;
    try {
      const font = new drawing.Font();
      font.setSize(fontSize);
      const blob = drawing.TextBlob.makeFromString(text, font, drawing.TextEncoding.TEXT_ENCODING_UTF8);
      const brush = new drawing.Brush();
      brush.setColor(YearbookExporter.argbToColor(argb));
      canvas.attachBrush(brush);
      let drawX = x;
      if (centered) {
        const width = YearbookExporter.measureText(text, font);
        drawX = x - width / 2;
      }
      canvas.drawTextBlob(blob, drawX, y);
      canvas.detachBrush();
    } catch (e) {
      // 文本绘制失败忽略。
    }
  }

  private static drawTextRight(canvas: drawing.Canvas, text: string, rightX: number, y: number,
                               fontSize: number, argb: number): void {
    if (text.length === 0) return;
    try {
      const font = new drawing.Font();
      font.setSize(fontSize);
      const width = YearbookExporter.measureText(text, font);
      YearbookExporter.drawText(canvas, text, rightX - width, y, fontSize, argb, false);
    } catch (e) {}
  }

  // 简单按字符宽度换行（CJK 友好：按估算字宽断行）。返回绘制后的 y。
  private static drawWrappedText(canvas: drawing.Canvas, text: string, x: number, y: number,
                                 maxWidth: number, fontSize: number, argb: number): number {
    const charW = fontSize * 0.95;            // CJK 近似全角宽
    const perLine = Math.max(1, Math.floor(maxWidth / charW));
    const lineH = fontSize * 1.5;
    let cursorY = y;
    let i = 0;
    while (i < text.length) {
      const line = text.substring(i, i + perLine);
      YearbookExporter.drawText(canvas, line, x, cursorY, fontSize, argb, false);
      cursorY += lineH;
      i += perLine;
    }
    return cursorY;
  }

  private static measureText(text: string, font: drawing.Font): number {
    try {
      return font.measureText(text, drawing.TextEncoding.TEXT_ENCODING_UTF8);
    } catch (e) {
      return text.length * 10;
    }
  }

  private static async savePage(ctx: CanvasContext, dir: string, idx: number): Promise<void> {
    const path = `${dir}/page-${idx + 1}.png`;
    let packer: image.ImagePacker | null = null;
    try {
      packer = image.createImagePacker();
      const opts: image.PackingOption = { format: 'image/png', quality: 100 };
      const buf: ArrayBuffer = await packer.packing(ctx.pixelMap, opts);
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, buf);
      fileIo.closeSync(file);
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `年册页保存失败: ${JSON.stringify(e)}`);
    } finally {
      if (packer) {
        try { packer.release(); } catch (e) {}
      }
      try { ctx.pixelMap.release(); } catch (e) {}
    }
  }

  // MARK: 工具

  private static argbToColor(argb: number): common2D.Color {
    return {
      alpha: (argb >>> 24) & 0xFF,
      red: (argb >>> 16) & 0xFF,
      green: (argb >>> 8) & 0xFF,
      blue: argb & 0xFF
    };
  }

  private static hexToArgb(hex: string, fallback: number): number {
    const cleaned = hex.replace('#', '');
    if (cleaned.length === 6) {
      const v = Number.parseInt(cleaned, 16);
      if (!Number.isNaN(v)) return 0xFF000000 | v;
    }
    return fallback;
  }

  private static longDate(epochMs: number): string {
    const d = new Date(epochMs);
    return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;
  }

  private static mkdirp(dir: string): void {
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
    } catch (e) {}
  }
}

interface CanvasContext {
  canvas: drawing.Canvas;
  pixelMap: image.PixelMap;
}
