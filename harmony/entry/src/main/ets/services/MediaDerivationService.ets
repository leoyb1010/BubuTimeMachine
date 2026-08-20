import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppDatabase } from '../data/AppDatabase';
import { Media } from '../models/Models';
import { MediaType, SyncState } from '../models/Enums';
import { MediaStore } from './MediaStore';
import { ThumbnailBackfillBus, ThumbnailProvider } from './media/ThumbnailProvider';

export class MediaDerivationService {
  static initialize(): void {
    const persist = (mediaId: string, thumbnailFileName: string): void => {
      AppDatabase.shared.updateMediaDerivedFields(mediaId, thumbnailFileName, undefined, undefined, undefined);
    };
    ThumbnailBackfillBus.shared.setHandler(persist);
    ThumbnailBackfillBus.shared.drain(persist);
  }

  static async prepare(media: Media): Promise<void> {
    const fileName = media.localFileName;
    if (!fileName || !MediaStore.shared.exists(fileName)) return;
    const path = MediaStore.shared.fullPath(fileName);
    if (!media.contentHash) media.contentHash = await MediaDerivationService.sha256File(path);
    if (!media.resourceRoleRaw) media.resourceRoleRaw = 'display';
    if (!media.assetGroupID) media.assetGroupID = media.id;
    if (!media.thumbnailFileName) {
      const pixelMap = media.typeRaw === MediaType.video
        ? await ThumbnailProvider.videoFrame(path, 600)
        : media.typeRaw === MediaType.photo ? await ThumbnailProvider.downsample(path, 600) : null;
      if (pixelMap) {
        media.thumbnailFileName = await MediaStore.shared.makePhotoThumbnailFromPixelMap(pixelMap, 600) ?? undefined;
        try { pixelMap.release(); } catch (e) {}
      }
    }
  }

  static async backfillPending(limit: number = 8): Promise<void> {
    const all = await AppDatabase.shared.fetchAllMedia();
    let count = 0;
    for (const media of all) {
      if (count >= limit) break;
      if (!media.localFileName || (media.contentHash && media.thumbnailFileName)) continue;
      await MediaDerivationService.prepare(media);
      await AppDatabase.shared.updateMediaDerivedFields(
        media.id, media.thumbnailFileName, media.contentHash, media.resourceRoleRaw, media.assetGroupID);
      count += 1;
    }
  }

  static async sha256File(path: string): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const size = fileIo.statSync(path).size;
      let readTotal = 0;
      while (readTotal < size) {
        const chunk = new ArrayBuffer(Math.min(1048576, size - readTotal));
        const count = fileIo.readSync(file.fd, chunk);
        if (count <= 0) break;
        await md.update({ data: new Uint8Array(chunk.slice(0, count)) });
        readTotal += count;
      }
      const digest = await md.digest();
      return Array.from(digest.data).map((value: number): string => {
        const hex = value.toString(16);
        return hex.length === 1 ? `0${hex}` : hex;
      }).join('');
    } finally {
      fileIo.closeSync(file);
    }
  }
}
