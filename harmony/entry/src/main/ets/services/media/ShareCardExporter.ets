import { drawing, common2D } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { MediaStore } from '../MediaStore';
import { ThumbnailProvider } from './ThumbnailProvider';

export enum ShareCardLayout {
  portrait = 'portrait',
  square = 'square',
  thenNow = 'thenNow'
}

export interface ShareCardInput {
  entryId: string;
  childName: string;
  dateText: string;
  ageText?: string;
  note?: string;
  photoPath?: string;
  thenPhotoPath?: string;
  thenDateText?: string;
  thenAgeText?: string;
  eraText: string;
  thenEraText: string;
}

interface CardSize { width: number; height: number; }
interface CardCanvas { canvas: drawing.Canvas; pixelMap: image.PixelMap; }

const CREAM = 0xFFFFF8F1;
const WARM_BROWN = 0xFF5C4D47;
const SECONDARY = 0xFF8A8079;
const PRIMARY = 0xFFF28C9E;
const PEACH = 0xFFFFD6BD;
const WHITE = 0xFFFFFFFF;

export class ShareCardExporter {
  static readonly shared = new ShareCardExporter();
  private constructor() {}

  static size(layout: ShareCardLayout): CardSize {
    if (layout === ShareCardLayout.square) return { width: 1080, height: 1080 };
    if (layout === ShareCardLayout.thenNow) return { width: 1080, height: 1620 };
    return { width: 1080, height: 1440 };
  }

  async renderToFile(input: ShareCardInput, layout: ShareCardLayout): Promise<string> {
    if (layout === ShareCardLayout.thenNow && (!input.photoPath || !input.thenPhotoPath)) {
      throw new Error('那年今日需要两张真实照片');
    }
    const size = ShareCardExporter.size(layout);
    const target = ShareCardExporter.newCanvas(size);
    let photo: image.PixelMap | null = null;
    let thenPhoto: image.PixelMap | null = null;
    try {
      if (input.photoPath) photo = await ThumbnailProvider.downsample(input.photoPath, 1800);
      if (input.thenPhotoPath) thenPhoto = await ThumbnailProvider.downsample(input.thenPhotoPath, 1800);
      if (layout === ShareCardLayout.thenNow) {
        ShareCardExporter.drawThenNow(target.canvas, input, photo!, thenPhoto!);
      } else {
        ShareCardExporter.drawSingle(target.canvas, input, layout, photo);
      }
      const path = `${MediaStore.shared.cacheDir()}/分享卡-${input.entryId}-${layout}.png`;
      await ShareCardExporter.savePNG(target.pixelMap, path);
      return path;
    } finally {
      if (photo) try { photo.release(); } catch (e) {}
      if (thenPhoto) try { thenPhoto.release(); } catch (e) {}
      try { target.pixelMap.release(); } catch (e) {}
    }
  }

  private static drawSingle(canvas: drawing.Canvas, input: ShareCardInput,
                            layout: ShareCardLayout, photo: image.PixelMap | null): void {
    const size = ShareCardExporter.size(layout);
    ShareCardExporter.fill(canvas, 0, 0, size.width, size.height, CREAM);
    if (photo) {
      const photoH = layout === ShareCardLayout.square ? 700 : 980;
      ShareCardExporter.drawImageCover(canvas, photo, 0, 0, size.width, photoH);
      ShareCardExporter.drawText(canvas, input.dateText, 64, photoH + 72, 44, PRIMARY, true);
      if (input.ageText) ShareCardExporter.drawText(canvas, input.ageText, 64, photoH + 124, 30, SECONDARY, true);
      if (input.note) {
        ShareCardExporter.drawWrapped(canvas, input.note, 64, photoH + 188, size.width - 128, 42, WARM_BROWN,
          layout === ShareCardLayout.square ? 2 : 3);
      }
      ShareCardExporter.signature(canvas, input.childName, size.height - 58);
      return;
    }

    ShareCardExporter.fill(canvas, 0, 0, size.width, size.height, PEACH);
    ShareCardExporter.fill(canvas, 0, size.height * 0.55, size.width, size.height * 0.45, CREAM);
    ShareCardExporter.drawText(canvas, input.dateText, size.width / 2, 150, 44, PRIMARY, true, true);
    if (input.ageText) ShareCardExporter.drawText(canvas, input.ageText, size.width / 2, 205, 30, SECONDARY, true, true);
    const note = input.note && input.note.length > 0 ? `「${input.note}」` : '这一天，也值得记住';
    ShareCardExporter.drawWrappedCentered(canvas, note, 90, size.height * 0.36, size.width - 180, 60, WARM_BROWN, 7);
    ShareCardExporter.signature(canvas, input.childName, size.height - 70);
  }

  private static drawThenNow(canvas: drawing.Canvas, input: ShareCardInput,
                             nowPhoto: image.PixelMap, thenPhoto: image.PixelMap): void {
    const size = ShareCardExporter.size(ShareCardLayout.thenNow);
    ShareCardExporter.fill(canvas, 0, 0, size.width, size.height, CREAM);
    ShareCardExporter.drawImageCover(canvas, thenPhoto, 0, 0, size.width, 650);
    ShareCardExporter.fill(canvas, 0, 620, size.width, 30, CREAM);
    ShareCardExporter.drawImageCover(canvas, nowPhoto, 0, 650, size.width, 650);
    ShareCardExporter.label(canvas, input.thenEraText, input.thenDateText ?? '那一年', input.thenAgeText, 42, 565);
    ShareCardExporter.label(canvas, input.eraText, input.dateText, input.ageText, 42, 1215);
    if (input.note) ShareCardExporter.drawWrapped(canvas, input.note, 60, 1385, size.width - 120, 36, WARM_BROWN, 2);
    ShareCardExporter.signature(canvas, input.childName, size.height - 58);
  }

  private static label(canvas: drawing.Canvas, era: string, date: string, age: string | undefined,
                       x: number, y: number): void {
    const text = `${era} · ${date}${age ? ` · ${age}` : ''}`;
    ShareCardExporter.fill(canvas, x - 18, y - 45, Math.min(920, text.length * 36 + 40), 66, PRIMARY);
    ShareCardExporter.drawText(canvas, text, x, y, 32, WHITE, true);
  }

  private static signature(canvas: drawing.Canvas, childName: string, y: number): void {
    ShareCardExporter.drawText(canvas, `布布时光机 · ${childName}的成长时光`, 54, y, 28, SECONDARY, true);
  }

  private static newCanvas(size: CardSize): CardCanvas {
    const options: image.InitializationOptions = {
      size: { width: size.width, height: size.height },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    };
    const pixelMap = image.createPixelMapSync(options);
    return { canvas: new drawing.Canvas(pixelMap), pixelMap };
  }

  private static fill(canvas: drawing.Canvas, x: number, y: number, width: number, height: number, argb: number): void {
    const brush = new drawing.Brush();
    brush.setColor(ShareCardExporter.color(argb));
    canvas.attachBrush(brush);
    canvas.drawRect({ left: x, top: y, right: x + width, bottom: y + height });
    canvas.detachBrush();
  }

  private static drawImageCover(canvas: drawing.Canvas, pixelMap: image.PixelMap,
                                x: number, y: number, width: number, height: number): void {
    const info = pixelMap.getImageInfoSync();
    const sourceRatio = info.size.width / info.size.height;
    const targetRatio = width / height;
    let source: common2D.Rect;
    if (sourceRatio > targetRatio) {
      const sourceWidth = info.size.height * targetRatio;
      const left = (info.size.width - sourceWidth) / 2;
      source = { left, top: 0, right: left + sourceWidth, bottom: info.size.height };
    } else {
      const sourceHeight = info.size.width / targetRatio;
      const top = (info.size.height - sourceHeight) / 2;
      source = { left: 0, top, right: info.size.width, bottom: top + sourceHeight };
    }
    canvas.drawImageRectWithSrc(pixelMap, source, { left: x, top: y, right: x + width, bottom: y + height });
  }

  private static drawText(canvas: drawing.Canvas, text: string, x: number, y: number,
                          size: number, argb: number, bold: boolean, centered: boolean = false): void {
    if (text.length === 0) return;
    const font = new drawing.Font();
    font.setSize(size);
    font.enableEmbolden(bold);
    const blob = drawing.TextBlob.makeFromString(text, font, drawing.TextEncoding.TEXT_ENCODING_UTF8);
    const brush = new drawing.Brush();
    brush.setColor(ShareCardExporter.color(argb));
    canvas.attachBrush(brush);
    const drawX = centered ? x - font.measureText(text, drawing.TextEncoding.TEXT_ENCODING_UTF8) / 2 : x;
    canvas.drawTextBlob(blob, drawX, y);
    canvas.detachBrush();
  }

  private static drawWrapped(canvas: drawing.Canvas, text: string, x: number, y: number,
                             maxWidth: number, size: number, argb: number, maxLines: number): void {
    const perLine = Math.max(1, Math.floor(maxWidth / (size * 0.95)));
    for (let line = 0; line < maxLines && line * perLine < text.length; line++) {
      const start = line * perLine;
      let value = text.substring(start, start + perLine);
      if (line === maxLines - 1 && start + perLine < text.length) value = value.substring(0, Math.max(1, value.length - 1)) + '…';
      ShareCardExporter.drawText(canvas, value, x, y + line * size * 1.45, size, argb, true);
    }
  }

  private static drawWrappedCentered(canvas: drawing.Canvas, text: string, x: number, y: number,
                                     maxWidth: number, size: number, argb: number, maxLines: number): void {
    const perLine = Math.max(1, Math.floor(maxWidth / (size * 0.95)));
    const lines = Math.min(maxLines, Math.ceil(text.length / perLine));
    for (let line = 0; line < lines; line++) {
      const start = line * perLine;
      let value = text.substring(start, start + perLine);
      if (line === lines - 1 && start + perLine < text.length) value = value.substring(0, Math.max(1, value.length - 1)) + '…';
      ShareCardExporter.drawText(canvas, value, x + maxWidth / 2, y + line * size * 1.5, size, argb, true, true);
    }
  }

  private static async savePNG(pixelMap: image.PixelMap, path: string): Promise<void> {
    const packer = image.createImagePacker();
    try {
      const data = await packer.packing(pixelMap, { format: 'image/png', quality: 100 });
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, data);
      fileIo.closeSync(file);
    } finally {
      try { packer.release(); } catch (e) {}
    }
  }

  private static color(argb: number): common2D.Color {
    return { alpha: (argb >>> 24) & 0xFF, red: (argb >>> 16) & 0xFF, green: (argb >>> 8) & 0xFF, blue: argb & 0xFF };
  }
}
