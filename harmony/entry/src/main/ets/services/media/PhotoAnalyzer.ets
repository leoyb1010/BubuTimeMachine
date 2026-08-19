import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { geoLocationManager } from '@kit.LocationKit';
import { faceDetector, objectDetection, visionBase } from '@kit.CoreVisionKit';

const DOMAIN = 0x0000;

// MARK: - 图片分析结果（对照 iOS Services/Media/PhotoAnalyzer.swift 的 PhotoAnalysis）
export interface PhotoAnalysis {
  captureDate?: number;     // EXIF 拍摄时间（epoch ms）
  latitude?: number;
  longitude?: number;
  locationName?: string;    // 反向地理编码地名
  tags: string[];           // 场景/物体标签
  faceCount: number;        // 人脸数量
}

// MARK: - 端侧图片分析器（对照 iOS PhotoAnalyzer）
// 全部端侧、零后端、隐私至上：
// - EXIF：拍摄时间 + GPS 坐标（@kit.ImageKit image.ImageSource.getImageProperty）
// - 地名：坐标 → 地名（HarmonyOS @kit.LocationKit geoLocationManager 反向地理编码）
// - 标签/人脸：Core Vision Kit objectDetection / faceDetector，失败时安全降级为空。
export class PhotoAnalyzer {
  static readonly shared = new PhotoAnalyzer();

  private constructor() {}

  // iOS: func analyze(imageData:includeLocation:)
  async analyze(imageData: ArrayBuffer, includeLocation: boolean = true): Promise<PhotoAnalysis> {
    const result: PhotoAnalysis = { tags: [], faceCount: 0 };

    let source: image.ImageSource | null = null;
    try {
      source = image.createImageSource(imageData);

      // 1) EXIF：时间 + GPS
      result.captureDate = await PhotoAnalyzer.exifDate(source);
      if (includeLocation) {
        const coord = await PhotoAnalyzer.gpsCoordinate(source);
        if (coord) {
          result.latitude = coord[0];
          result.longitude = coord[1];
        }
      }

      // 2) 标签 + 人脸（端侧）
      result.tags = await PhotoAnalyzer.classify(source);
      result.faceCount = await PhotoAnalyzer.countFaces(source);
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `图片分析失败: ${JSON.stringify(e)}`);
    } finally {
      if (source) {
        try { source.release(); } catch (e) {}
      }
    }

    // 3) 反向地理编码（需联网，失败静默）
    if (result.latitude !== undefined && result.longitude !== undefined) {
      result.locationName = await PhotoAnalyzer.reverseGeocode(result.latitude, result.longitude);
    }

    // 人脸数转成温暖标签
    if (result.faceCount === 1) {
      result.tags.push('独照');
    } else if (result.faceCount >= 2) {
      result.tags.push('合影');
    }

    return result;
  }

  // MARK: EXIF

  // iOS: exifDate(from props) —— 解析 "yyyy:MM:dd HH:mm:ss"
  private static async exifDate(source: image.ImageSource): Promise<number | undefined> {
    const str = await PhotoAnalyzer.readProperty(source, image.PropertyKey.DATE_TIME_ORIGINAL)
      ?? await PhotoAnalyzer.readProperty(source, image.PropertyKey.DATE_TIME);
    if (!str) return undefined;
    return PhotoAnalyzer.parseExifDate(str);
  }

  // "yyyy:MM:dd HH:mm:ss" → epoch ms。
  static parseExifDate(str: string): number | undefined {
    // 例: 2024:06:14 18:30:05
    const m = str.match(/^(\d{4}):(\d{2}):(\d{2})\s+(\d{2}):(\d{2}):(\d{2})/);
    if (!m) return undefined;
    const year = Number.parseInt(m[1], 10);
    const month = Number.parseInt(m[2], 10) - 1;
    const day = Number.parseInt(m[3], 10);
    const hour = Number.parseInt(m[4], 10);
    const min = Number.parseInt(m[5], 10);
    const sec = Number.parseInt(m[6], 10);
    const d = new Date(year, month, day, hour, min, sec);
    const t = d.getTime();
    return Number.isNaN(t) ? undefined : t;
  }

  // iOS: gpsCoordinate(from props) —— 含 N/S/E/W 符号处理
  private static async gpsCoordinate(source: image.ImageSource): Promise<[number, number] | null> {
    const latStr = await PhotoAnalyzer.readProperty(source, image.PropertyKey.GPS_LATITUDE);
    const lonStr = await PhotoAnalyzer.readProperty(source, image.PropertyKey.GPS_LONGITUDE);
    if (!latStr || !lonStr) return null;
    const lat = PhotoAnalyzer.parseGpsValue(latStr);
    const lon = PhotoAnalyzer.parseGpsValue(lonStr);
    if (lat === undefined || lon === undefined) return null;
    const latRef = (await PhotoAnalyzer.readProperty(source, image.PropertyKey.GPS_LATITUDE_REF)) ?? 'N';
    const lonRef = (await PhotoAnalyzer.readProperty(source, image.PropertyKey.GPS_LONGITUDE_REF)) ?? 'E';
    const signedLat = latRef.toUpperCase().startsWith('S') ? -lat : lat;
    const signedLon = lonRef.toUpperCase().startsWith('W') ? -lon : lon;
    return [signedLat, signedLon];
  }

  // GPS 属性可能是 "31,13,48" 度分秒格式或十进制；都解析为十进制度。
  static parseGpsValue(raw: string): number | undefined {
    const parts = raw.split(',').map((p: string): number => Number.parseFloat(p.trim()));
    if (parts.length >= 3 && !Number.isNaN(parts[0])) {
      return parts[0] + parts[1] / 60 + parts[2] / 3600;
    }
    const single = Number.parseFloat(raw.trim());
    return Number.isNaN(single) ? undefined : single;
  }

  private static async readProperty(source: image.ImageSource, key: string): Promise<string | undefined> {
    try {
      const v: string = await source.getImageProperty(key);
      if (v && v.length > 0) return v;
      return undefined;
    } catch (e) {
      return undefined;
    }
  }

  // MARK: 标签 / 人脸（端侧）

  // iOS 用 VNClassifyImageRequest；HarmonyOS 用 Core Vision 多目标识别的稳定内置标签集。
  private static async classify(source: image.ImageSource): Promise<string[]> {
    let pixelMap: image.PixelMap | null = null;
    let detector: objectDetection.ObjectDetector | null = null;
    try {
      pixelMap = await source.createPixelMap({
        desiredSize: { width: 1024, height: 1024 },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      detector = await objectDetection.ObjectDetector.create();
      const request: visionBase.Request = {
        inputData: { pixelMap },
        scene: visionBase.SceneMode.FOREGROUND
      };
      const response = await detector.process(request);
      const tags = new Set<string>();
      for (const object of response.objects) {
        if (object.score < 0.6) continue;
        for (const label of object.labels) {
          const localized = PhotoAnalyzer.objectLabel(label);
          if (localized) tags.add(localized);
          if (tags.size >= 4) return Array.from(tags);
        }
      }
      return Array.from(tags);
    } catch (e) {
      return [];
    } finally {
      if (detector) try { await detector.destroy(); } catch (e) {}
      if (pixelMap) try { pixelMap.release(); } catch (e) {}
    }
  }

  static objectLabel(label: number): string | undefined {
    const labels: Record<number, string> = {
      1: '小动物', 2: '植物', 3: '建筑', 5: '人像', 6: '桌子', 7: '文字',
      8: '人物', 9: '猫咪', 10: '狗狗', 11: '美食', 12: '汽车', 13: '人物',
      21: '文档', 22: '卡片'
    };
    return labels[label];
  }

  // iOS: countFaces(cgImage:) 用 VNDetectFaceRectanglesRequest。
  private static async countFaces(source: image.ImageSource): Promise<number> {
    let pixelMap: image.PixelMap | null = null;
    try {
      pixelMap = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      if (!(await faceDetector.init())) return 0;
      const faces = await faceDetector.detect({ pixelMap });
      return faces.filter((face: faceDetector.Face): boolean => face.probability >= 0.5).length;
    } catch (e) {
      return 0;
    } finally {
      try { await faceDetector.release(); } catch (e) {}
      if (pixelMap) try { pixelMap.release(); } catch (e) {}
    }
  }

  // iOS: localizedTag —— Vision 英文标识符 → 温暖中文标签（常见育儿场景）。
  // 真正的 classify 接入后由它做映射；现保留以备 HiAI 输出英文标签时复用。
  static localizedTag(identifier: string): string {
    const map: Record<string, string> = {
      'baby': '宝宝', 'child': '孩子', 'people': '人物', 'portrait': '人像',
      'smile': '笑容', 'food': '美食', 'meal': '吃饭', 'fruit': '水果',
      'cake': '蛋糕', 'toy': '玩具', 'dog': '狗狗', 'cat': '猫咪',
      'animal': '小动物', 'flower': '花', 'plant': '植物', 'tree': '树',
      'beach': '海边', 'sea': '大海', 'water': '水', 'snow': '雪',
      'park': '公园', 'grass': '草地', 'sky': '天空', 'outdoor': '户外',
      'indoor': '室内', 'room': '房间', 'bed': '床上', 'sleep': '睡觉',
      'book': '看书', 'car': '汽车', 'vehicle': '车', 'sunset': '夕阳',
      'night': '夜晚', 'birthday': '生日', 'celebration': '庆祝',
      'clothing': '穿搭', 'hat': '帽子', 'festival': '节日'
    };
    const lower = identifier.toLowerCase();
    const keys = Object.keys(map);
    for (const k of keys) {
      if (lower.includes(k)) {
        return map[k];
      }
    }
    return identifier;
  }

  // MARK: 地理编码

  // iOS: reverseGeocode(lat:lon:) 用 MapKit MKReverseGeocodingRequest。
  // HarmonyOS: @kit.LocationKit geoLocationManager.getAddressesFromLocation。
  static async reverseGeocode(lat: number, lon: number): Promise<string | undefined> {
    try {
      const req: geoLocationManager.ReverseGeoCodeRequest = {
        latitude: lat,
        longitude: lon,
        maxItems: 1,
        locale: 'zh'
      };
      const list: geoLocationManager.GeoAddress[] = await geoLocationManager.getAddressesFromLocation(req);
      if (list.length === 0) return undefined;
      const a = list[0];
      const candidates: Array<string | undefined> = [
        a.placeName,
        a.subLocality,
        a.locality,
        a.administrativeArea,
        a.descriptions
      ];
      for (const c of candidates) {
        if (c && c.trim().length > 0) {
          return c.trim();
        }
      }
      return undefined;
    } catch (e) {
      // 无网络 / 无权限 / API 不可用：静默跳过。
      return undefined;
    }
  }
}
