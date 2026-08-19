import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { dataSharePredicates } from '@kit.ArkData';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppDatabase } from '../data/AppDatabase';
import {
  PhotoEventGroup,
  PhotoIntakeCandidate,
  PhotoIntakeState,
  clusterPhotoCandidates
} from '../models/PhotoIntake';
import { EntryWriter } from './EntryWriter';
import { MediaStore } from './MediaStore';
import { ServerConfig } from './ServerConfig';
import { SyncEngine } from '../sync/SyncEngine';
import { ChildIdentityRecognizer } from './ChildIdentityRecognizer';

export interface PhotoIntakeResult {
  entryId: string;
  acceptedCount: number;
  failedCount: number;
}

export class PhotoIntakeService {
  static readonly shared = new PhotoIntakeService();

  private context: common.UIAbilityContext | null = null;

  private constructor() {}

  initialize(context: common.UIAbilityContext): void {
    this.context = context;
    ChildIdentityRecognizer.shared.initialize(context);
  }

  identityEnabled(): boolean { return ChildIdentityRecognizer.shared.isEnabled(); }

  setIdentityEnabled(enabled: boolean): void { ChildIdentityRecognizer.shared.setEnabled(enabled); }

  async cachedGroups(): Promise<PhotoEventGroup[]> {
    return clusterPhotoCandidates(await AppDatabase.shared.fetchPhotoIntakePending());
  }

  async scanRecent(days: number = 14): Promise<PhotoEventGroup[]> {
    const context = this.context;
    if (!context) throw new Error('照片收件箱还没有初始化');
    const manager = abilityAccessCtrl.createAtManager();
    const permission = await manager.requestPermissionsFromUser(context, ['ohos.permission.READ_IMAGEVIDEO']);
    let denied = false;
    for (const value of permission.authResults) {
      if (value !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) denied = true;
    }
    if (denied) {
      throw new Error('需要允许读取照片，才能扫描最近新增内容');
    }

    const predicates = new dataSharePredicates.DataSharePredicates();
    const sinceSeconds = Math.floor((Date.now() - days * 24 * 60 * 60 * 1000) / 1000);
    predicates.greaterThan(photoAccessHelper.PhotoKeys.DATE_TAKEN, sinceSeconds);
    predicates.orderByDesc(photoAccessHelper.PhotoKeys.DATE_TAKEN);
    predicates.limit(300, 0);
    const columns: string[] = [
      photoAccessHelper.PhotoKeys.DATE_TAKEN,
      photoAccessHelper.PhotoKeys.WIDTH,
      photoAccessHelper.PhotoKeys.HEIGHT,
      photoAccessHelper.PhotoKeys.DURATION,
      photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE,
      photoAccessHelper.PhotoKeys.BURST_KEY
    ];
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const result = await helper.getAssets({ fetchColumns: columns, predicates });
    try {
      const assets = await result.getAllObjects();
      const candidates = assets.map((asset: photoAccessHelper.PhotoAsset): PhotoIntakeCandidate => {
        return {
          assetUri: asset.uri,
          displayName: asset.displayName,
          createdAt: PhotoIntakeService.milliseconds(asset.get(photoAccessHelper.PhotoKeys.DATE_TAKEN)),
          mediaType: asset.photoType,
          width: PhotoIntakeService.number(asset.get(photoAccessHelper.PhotoKeys.WIDTH)),
          height: PhotoIntakeService.number(asset.get(photoAccessHelper.PhotoKeys.HEIGHT)),
          duration: PhotoIntakeService.number(asset.get(photoAccessHelper.PhotoKeys.DURATION)) / 1000,
          subtype: PhotoIntakeService.number(asset.get(photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE)),
          burstKey: PhotoIntakeService.optionalString(asset.get(photoAccessHelper.PhotoKeys.BURST_KEY)),
          state: PhotoIntakeState.discovered,
          isLikelyChild: false
        };
      }).filter((candidate: PhotoIntakeCandidate): boolean => candidate.createdAt > 0);
      if (this.identityEnabled()) {
        const profile = await AppDatabase.shared.fetchChildProfile();
        if (profile?.avatarMediaFileName) {
          const avatarPath = MediaStore.shared.fullPath(profile.avatarMediaFileName);
          let checked = 0;
          for (const candidate of candidates) {
            if (candidate.mediaType !== 1 || checked >= 30) continue;
            candidate.isLikelyChild = await ChildIdentityRecognizer.shared
              .isLikelySamePerson(candidate.assetUri, avatarPath);
            checked += 1;
          }
        }
      }
      await AppDatabase.shared.upsertPhotoIntakeCandidates(candidates);
    } finally {
      result.close();
    }
    return await this.cachedGroups();
  }

  async accept(group: PhotoEventGroup): Promise<PhotoIntakeResult> {
    const pending = await AppDatabase.shared.fetchPhotoIntakePending(300);
    const wanted = new Set<string>(group.assetUris);
    const selected = pending.filter((item: PhotoIntakeCandidate): boolean => wanted.has(item.assetUri));
    const photoNames: string[] = [];
    const videoNames: string[] = [];
    const acceptedUris: string[] = [];
    const failedUris: string[] = [];
    for (const item of selected) {
      const extension = PhotoIntakeService.extension(item.displayName, item.mediaType === 2 ? 'mp4' : 'jpg');
      const fileName = item.mediaType === 2
        ? MediaStore.shared.importFile(item.assetUri, extension)
        : MediaStore.shared.copyIntoStore(item.assetUri, extension);
      if (fileName) {
        if (item.mediaType === 2) videoNames.push(fileName); else photoNames.push(fileName);
        acceptedUris.push(item.assetUri);
      } else {
        failedUris.push(item.assetUri);
      }
    }
    if (acceptedUris.length === 0) throw new Error('这些照片暂时无法读取，请稍后重试');
    const date = new Date(group.startedAt);
    const note = `${date.getMonth() + 1}月${date.getDate()}日的照片`;
    const entryId = await EntryWriter.entryWithPhoto(
      note, photoNames, ServerConfig.shared.currentRole, undefined, null, 0, videoNames, group.startedAt);
    await AppDatabase.shared.markPhotoIntake(acceptedUris, PhotoIntakeState.accepted);
    await AppDatabase.shared.markPhotoIntake(failedUris, PhotoIntakeState.failed);
    SyncEngine.shared.start();
    return { entryId, acceptedCount: acceptedUris.length, failedCount: failedUris.length };
  }

  async ignore(group: PhotoEventGroup): Promise<void> {
    await AppDatabase.shared.markPhotoIntake(group.assetUris, PhotoIntakeState.ignored);
  }

  private static number(value: photoAccessHelper.MemberType): number {
    return typeof value === 'number' ? value as number : Number(value ?? 0);
  }

  private static milliseconds(value: photoAccessHelper.MemberType): number {
    const raw = PhotoIntakeService.number(value);
    return raw > 0 && raw < 10_000_000_000 ? raw * 1000 : raw;
  }

  private static optionalString(value: photoAccessHelper.MemberType): string | undefined {
    return typeof value === 'string' && value.length > 0 ? value : undefined;
  }

  private static extension(displayName: string, fallback: string): string {
    const dot = displayName.lastIndexOf('.');
    return dot >= 0 && dot < displayName.length - 1 ? displayName.substring(dot + 1).toLowerCase() : fallback;
  }
}
