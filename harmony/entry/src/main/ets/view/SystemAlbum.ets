import { Media, Entry } from '../models/Models';
import { MediaType } from '../models/Enums';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { MediaStore } from '../services/MediaStore';

// MARK: - 系统相册（纯计算，不建表）（对照 iOS Features/Album/SystemAlbum.swift）
// V1 直接从 Entry + Media 动态生成；上传新照片后自动出现在对应相册。

// 相册里的一项（媒体 + 所属记录），照片墙/相册详情共用（对照 AlbumMediaItem）。
export interface AlbumMediaItem {
  id: string;          // = media.id（对照 Identifiable id: UUID）
  media: Media;
  entry: Entry;
}

// 系统相册（对照 SystemAlbum struct）。
export interface SystemAlbum {
  id: string;
  title: string;
  subtitle: string;
  icon: string;        // SF Symbol 名；UI 层按需映射 emoji
  items: AlbumMediaItem[];
}

// 封面 = 第一项（对照 SystemAlbum.cover）。
export function albumCover(a: SystemAlbum): AlbumMediaItem | undefined {
  return a.items.length > 0 ? a.items[0] : undefined;
}

// 数量（对照 SystemAlbum.count）。
export function albumCount(a: SystemAlbum): number {
  return a.items.length;
}

// MARK: - SystemAlbumFactory（对照 enum SystemAlbumFactory）
export class SystemAlbumFactory {

  // 全部照片 / 最近上传 / 小视频 / 有地点（空相册不展示，「全部照片」始终保留）。
  static featured(items: AlbumMediaItem[]): SystemAlbum[] {
    const photos = items.filter((i: AlbumMediaItem) => i.media.typeRaw === MediaType.photo);
    const videos = items.filter((i: AlbumMediaItem) => i.media.typeRaw === MediaType.video);
    const recent = items.slice(0, 60);
    const withLocation = items.filter((i: AlbumMediaItem) => {
      const hasName = i.entry.locationName !== undefined && i.entry.locationName.length > 0;
      return hasName || i.entry.latitude !== undefined;
    });

    const albums: SystemAlbum[] = [
      {
        id: 'all-photos', title: '全部照片',
        subtitle: '每一张长大的证据', icon: 'photo.stack', items: photos
      }
    ];
    if (recent.length > 0) {
      albums.push({
        id: 'recent', title: '最近上传',
        subtitle: `最新的 ${recent.length} 个瞬间`, icon: 'clock', items: recent
      });
    }
    if (videos.length > 0) {
      albums.push({
        id: 'videos', title: '小视频',
        subtitle: '会动的回忆', icon: 'video', items: videos
      });
    }
    if (withLocation.length > 0) {
      albums.push({
        id: 'with-location', title: '有地点',
        subtitle: '去过的地方', icon: 'mappin.and.ellipse', items: withLocation
      });
    }
    return albums;
  }

  // 按月份（2026年6月…），新月份在前。
  static monthly(items: AlbumMediaItem[]): SystemAlbum[] {
    const groups = new Map<string, AlbumMediaItem[]>();
    for (const item of items) {
      const d = new Date(item.entry.happenedAt);
      const key = `${SystemAlbumFactory.pad4(d.getFullYear())}-${SystemAlbumFactory.pad2(d.getMonth() + 1)}`;
      const arr = groups.get(key) ?? [];
      arr.push(item);
      groups.set(key, arr);
    }
    const keys = Array.from(groups.keys()).sort((a: string, b: string) => (a < b ? 1 : (a > b ? -1 : 0)));
    const out: SystemAlbum[] = [];
    for (const key of keys) {
      const group = groups.get(key);
      if (!group || group.length === 0) continue;
      const parts = key.split('-');
      const year = Number(parts[0]) || 0;
      const month = Number(parts[1]) || 0;
      out.push({
        id: `month-${key}`,
        title: `${year}年${month}月`,
        subtitle: `${group.length} 个瞬间`,
        icon: 'calendar',
        items: group
      });
    }
    return out;
  }

  // 按月龄（12 个月、13 个月…），大月龄在前；没有生日时返回空。
  static byAgeMonth(items: AlbumMediaItem[], birthdayMs: number | undefined): SystemAlbum[] {
    if (birthdayMs === undefined) return [];
    const groups = new Map<number, AlbumMediaItem[]>();
    for (const item of items) {
      const m = Math.max(0, SystemAlbumFactory.monthsBetween(birthdayMs, item.entry.happenedAt));
      const arr = groups.get(m) ?? [];
      arr.push(item);
      groups.set(m, arr);
    }
    const keys = Array.from(groups.keys()).sort((a: number, b: number) => b - a);
    const out: SystemAlbum[] = [];
    for (const month of keys) {
      const group = groups.get(month);
      if (!group || group.length === 0) continue;
      let title: string;
      if (month < 12) {
        title = `${month} 个月`;
      } else {
        const rem = month % 12;
        title = rem === 0 ? `${Math.floor(month / 12)} 岁` : `${Math.floor(month / 12)} 岁 ${rem} 个月`;
      }
      out.push({
        id: `age-${month}`,
        title: title,
        subtitle: `${group.length} 个瞬间`,
        icon: 'birthday.cake',
        items: group
      });
    }
    return out;
  }

  // —— 工具 ——

  // 历法月差（对照 Calendar.dateComponents([.month], from:to:)）。
  private static monthsBetween(fromMs: number, toMs: number): number {
    const f = new Date(fromMs);
    const t = new Date(toMs);
    let months = (t.getFullYear() - f.getFullYear()) * 12 + (t.getMonth() - f.getMonth());
    if (t.getDate() < f.getDate()) months -= 1;
    return months;
  }

  private static pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  private static pad4(n: number): string {
    let s = `${n}`;
    while (s.length < 4) s = `0${s}`;
    return s;
  }
}

// MARK: - 系统相册接入（对照 iOS PHPhotoLibrary / PhotosPicker）
// iOS 经 PhotosPicker 选择系统相册照片再导入 MediaStore；HarmonyOS 用 photoAccessHelper.PhotoViewPicker
// 拉起系统图库选择器，返回选中 uri，再由 MediaStore 拷入应用沙盒（落本地、离线优先）。
// 隐私：只在用户主动选择时读取所选项，不申请全量相册权限。
export class SystemAlbumPicker {
  // 拉起系统图库，最多选 maxCount 张图片，返回选中文件的 uri 列表。
  static async pickPhotos(maxCount: number = 9): Promise<string[]> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = maxCount;
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select(options);
      return result.photoUris ?? [];
    } catch (e) {
      // 用户取消或无权限：温和降级为空（对照 iOS 选择器取消即什么都不做）。
      return [];
    }
  }

  // 把系统相册选中的 uri 拷入应用沙盒，返回相对文件名（落本地，对照 iOS importPickedItem）。
  static importIntoStore(srcUri: string): string | null {
    // 默认按 jpg 处理；MediaStore.copyIntoStore 仅按扩展名落盘，原图类型由系统选择器保证。
    return MediaStore.shared.copyIntoStore(srcUri, 'jpg');
  }
}
