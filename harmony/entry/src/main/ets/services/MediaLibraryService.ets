import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

export class MediaLibraryService {
  static async save(context: common.UIAbilityContext, path: string, isVideo: boolean): Promise<boolean> {
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const extension = MediaLibraryService.extension(path, isVideo ? 'mp4' : 'jpg');
    const config: photoAccessHelper.PhotoCreationConfig = {
      title: `布布时光机_${Date.now()}`,
      fileNameExtension: extension,
      photoType: isVideo ? photoAccessHelper.PhotoType.VIDEO : photoAccessHelper.PhotoType.IMAGE
    };
    const created = await helper.showAssetsCreationDialog([fileUri.getUriFromPath(path)], [config]);
    return created.length > 0;
  }

  private static extension(path: string, fallback: string): string {
    const clean = path.split('?')[0];
    const dot = clean.lastIndexOf('.');
    return dot >= 0 && dot < clean.length - 1 ? clean.substring(dot + 1).toLowerCase() : fallback;
  }
}
