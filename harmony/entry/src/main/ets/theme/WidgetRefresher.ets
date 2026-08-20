import { formProvider, formBindingData } from '@kit.FormKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppDatabase } from '../data/AppDatabase';
import { MediaStore } from '../services/MediaStore';
import { MediaDerivationService } from '../services/MediaDerivationService';

export class WidgetRefresher {
  private static readonly snapshotStore: string = 'bubu_widget';
  private static readonly formStore: string = 'bubu_widget_forms';
  private static appContext: common.Context | null = null;
  private static refreshTimer: number = -1;

  static initialize(context: common.Context): void {
    WidgetRefresher.appContext = context;
  }

  static requestRefresh(): void {
    if (WidgetRefresher.refreshTimer >= 0) clearTimeout(WidgetRefresher.refreshTimer);
    WidgetRefresher.refreshTimer = setTimeout(async (): Promise<void> => {
      WidgetRefresher.refreshTimer = -1;
      const context = WidgetRefresher.appContext;
      if (!context) return;
      await WidgetRefresher.publishCurrentSnapshot(context);
      WidgetRefresher.reload(context);
    }, 350);
  }

  static register(context: common.Context, formId: string): void {
    if (formId.length === 0) return;
    const store = preferences.getPreferencesSync(context, { name: WidgetRefresher.formStore });
    const ids = WidgetRefresher.readFormIds(store);
    if (!ids.includes(formId)) {
      ids.push(formId);
      store.putSync('formIds', JSON.stringify(ids));
      store.flush();
    }
  }

  static unregister(context: common.Context, formId: string): void {
    const store = preferences.getPreferencesSync(context, { name: WidgetRefresher.formStore });
    const ids = WidgetRefresher.readFormIds(store).filter((id: string): boolean => id !== formId);
    store.putSync('formIds', JSON.stringify(ids));
    store.flush();
  }

  static async publishCurrentSnapshot(context: common.Context): Promise<void> {
    const profile = await AppDatabase.shared.fetchChildProfile();
    const entries = await AppDatabase.shared.fetchEntries(false);
    const activeEntryIds = new Set<string>(entries.map((entry): string => entry.id));
    const photos = (await AppDatabase.shared.fetchAllMedia()).filter((item): boolean => {
      return item.typeRaw === 'photo' && activeEntryIds.has(item.entryId)
        && (item.resourceRoleRaw === undefined || item.resourceRoleRaw === 'display');
    });
    const milestones = await AppDatabase.shared.fetchMilestones();
    const growth = await AppDatabase.shared.fetchGrowth();
    const achieved = milestones.filter((item): boolean => item.happenedAt !== undefined);
    const next = milestones.find((item): boolean => item.happenedAt === undefined);
    const latest = entries.length > 0 ? entries[0] : undefined;
    let recentPhotoUri = '';
    const recentPhoto = entries.map((entry) => photos.find((photo): boolean => photo.entryId === entry.id))
      .find((photo): boolean => photo !== undefined);
    if (recentPhoto) {
      if ((!recentPhoto.thumbnailFileName || !MediaStore.shared.thumbnailExists(recentPhoto.thumbnailFileName))
        && recentPhoto.localFileName && MediaStore.shared.exists(recentPhoto.localFileName)) {
        await MediaDerivationService.prepare(recentPhoto);
        await AppDatabase.shared.updateMediaDerivedFields(recentPhoto.id, recentPhoto.thumbnailFileName,
          recentPhoto.contentHash, recentPhoto.resourceRoleRaw, recentPhoto.assetGroupID);
      }
      if (recentPhoto.thumbnailFileName && MediaStore.shared.thumbnailExists(recentPhoto.thumbnailFileName)) {
        recentPhotoUri = `file://${MediaStore.shared.thumbnailPath(recentPhoto.thumbnailFileName)}`;
      }
    }
    const measurement = growth.length > 0 ? growth[0] : undefined;
    const store = preferences.getPreferencesSync(context, { name: WidgetRefresher.snapshotStore });
    store.putSync('birthday', profile?.birthday ?? 0);
    store.putSync('childName', profile?.name ?? '布布');
    store.putSync('entryCount', entries.length);
    store.putSync('photoCount', photos.length);
    store.putSync('achievedMilestones', achieved.length);
    store.putSync('totalMilestones', milestones.length);
    store.putSync('recentTitle', latest?.title ?? latest?.note ?? '记录一个新瞬间');
    store.putSync('recentNote', latest?.note ?? '打开 App，留住今天的成长');
    store.putSync('recentPhotoUri', recentPhotoUri);
    store.putSync('latestHeight', measurement?.heightCm ?? 0);
    store.putSync('latestWeight', measurement?.weightKg ?? 0);
    store.putSync('nextMilestone', next?.title ?? '记录新的第一次');
    store.flush();
  }

  static reload(context: common.Context): void {
    const store = preferences.getPreferencesSync(context, { name: WidgetRefresher.formStore });
    for (const id of WidgetRefresher.readFormIds(store)) {
      const empty = formBindingData.createFormBindingData({});
      formProvider.updateForm(id, empty).catch(() => {});
    }
  }

  private static readFormIds(store: preferences.Preferences): string[] {
    try {
      const raw = store.getSync('formIds', '[]') as string;
      const parsed = JSON.parse(raw) as Object;
      if (!Array.isArray(parsed)) return [];
      return (parsed as Object[]).filter((item: Object): boolean => typeof item === 'string')
        .map((item: Object): string => item as string);
    } catch (e) {
      return [];
    }
  }
}
