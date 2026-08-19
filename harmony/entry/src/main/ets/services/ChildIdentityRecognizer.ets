import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { faceComparator } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';

export class ChildIdentityRecognizer {
  static readonly shared = new ChildIdentityRecognizer();
  private static readonly storeName: string = 'bubu_photo_identity';
  private context: common.Context | null = null;

  private constructor() {}

  initialize(context: common.Context): void { this.context = context; }

  isEnabled(): boolean {
    if (!this.context) return false;
    const store = preferences.getPreferencesSync(this.context, { name: ChildIdentityRecognizer.storeName });
    return store.getSync('enabled', false) as boolean;
  }

  setEnabled(enabled: boolean): void {
    if (!this.context) return;
    const store = preferences.getPreferencesSync(this.context, { name: ChildIdentityRecognizer.storeName });
    store.putSync('enabled', enabled);
    store.flush();
  }

  async isLikelySamePerson(candidateUri: string, avatarPath: string): Promise<boolean> {
    let candidateSource: image.ImageSource | null = null;
    let avatarSource: image.ImageSource | null = null;
    let candidateMap: image.PixelMap | null = null;
    let avatarMap: image.PixelMap | null = null;
    try {
      candidateSource = image.createImageSource(candidateUri);
      avatarSource = image.createImageSource(avatarPath);
      const options: image.DecodingOptions = { desiredPixelFormat: image.PixelMapFormat.RGBA_8888 };
      candidateMap = await candidateSource.createPixelMap(options);
      avatarMap = await avatarSource.createPixelMap(options);
      if (!(await faceComparator.init())) return false;
      const result = await faceComparator.compareFaces(
        { pixelMap: candidateMap }, { pixelMap: avatarMap });
      return result.isSamePerson && result.similarity >= 0.60;
    } catch (e) {
      return false;
    } finally {
      try { await faceComparator.release(); } catch (e) {}
      if (candidateMap) try { candidateMap.release(); } catch (e) {}
      if (avatarMap) try { avatarMap.release(); } catch (e) {}
      if (candidateSource) try { candidateSource.release(); } catch (e) {}
      if (avatarSource) try { avatarSource.release(); } catch (e) {}
    }
  }
}
