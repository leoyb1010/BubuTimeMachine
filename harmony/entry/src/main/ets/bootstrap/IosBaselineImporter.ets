import { preferences } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppDatabase } from '../data/AppDatabase';
import { Entry, ChildProfile, Media, Milestone, HealthRecord, VoiceNote, FamilyMember, GrowthMeasurement, Comment } from '../models/Models';
import { ServerConfig } from '../services/ServerConfig';
import { MediaStore } from '../services/MediaStore';
import { APIClient } from '../services/APIClient';
import { IOS_BASELINE_IMPORT_VERSION, IOS_BASELINE_JSON } from './IosBaselineData';

const DOMAIN = 0x0000;

interface IosBaselinePayload {
  entries: Entry[];
  media: Media[];
  profiles: ChildProfile[];
  milestones: Milestone[];
  members: FamilyMember[];
  health: HealthRecord[];
  growth: GrowthMeasurement[];
  comments: Comment[];
  voiceNotes: VoiceNote[];
}

// Emergency bootstrap used to replace polluted Harmony local data with the verified
// iPhone baseline, then pin cursors so stale server rows cannot immediately re-pollute it.
export class IosBaselineImporter {
  static async runIfNeeded(context: common.UIAbilityContext): Promise<void> {
    const store = await preferences.getPreferences(context, 'bubu_sync_cursor');
    const importedVersion = await store.get('ios_baseline_import_version', '') as string;
    const needsRepair = !(await IosBaselineImporter.hasUsableBaseline());
    if (importedVersion === IOS_BASELINE_IMPORT_VERSION && !needsRepair) return;

    hilog.warn(DOMAIN, 'Bubu', `开始导入 iOS 基准: saved=${importedVersion}, repair=${needsRepair}`);
    const payload = JSON.parse(IOS_BASELINE_JSON) as IosBaselinePayload;
    await AppDatabase.shared.clearServerBackedData();

    for (const profile of payload.profiles) await AppDatabase.shared.upsertChildProfile(profile);
    for (const member of payload.members) await AppDatabase.shared.upsertMember(member);
    for (const entry of payload.entries) await AppDatabase.shared.insertEntry(entry);
    for (const media of payload.media) await AppDatabase.shared.insertMedia(media);
    for (const milestone of payload.milestones) await AppDatabase.shared.upsertMilestone(milestone);
    for (const item of payload.health) await AppDatabase.shared.insertHealth(item);
    for (const item of payload.growth) await AppDatabase.shared.insertGrowth(item);
    for (const comment of payload.comments) await AppDatabase.shared.insertComment(comment);
    for (const note of payload.voiceNotes) await AppDatabase.shared.insertVoiceNote(note);

    await IosBaselineImporter.copyBundledMedia(context, payload);
    await AppDatabase.shared.normalizeMilestonesByTitle();
    await IosBaselineImporter.markServerBaselineReady(store);
    await store.put('ios_baseline_import_version', IOS_BASELINE_IMPORT_VERSION);
    await store.put('ios_baseline_protect_from_server_pull', true);
    await store.flush();

    const entries = await AppDatabase.shared.fetchEntries(true);
    const activeEntries = await AppDatabase.shared.fetchEntries(false);
    const media = await AppDatabase.shared.fetchAllMedia();
    const milestones = await AppDatabase.shared.fetchMilestones();
    const growth = await AppDatabase.shared.fetchGrowth();
    const achieved = milestones.filter((item: Milestone): boolean => item.happenedAt !== undefined).length;
    hilog.warn(
      DOMAIN,
      'Bubu',
      `iOS 基准已导入: version=${IOS_BASELINE_IMPORT_VERSION}, entries=${entries.length}, active=${activeEntries.length}, media=${media.length}, milestones=${milestones.length}, achieved=${achieved}, growth=${growth.length}`
    );
  }

  private static async hasUsableBaseline(): Promise<boolean> {
    const profile = await AppDatabase.shared.fetchChildProfile();
    if (!profile) return false;

    const activeEntries = await AppDatabase.shared.fetchEntries(false);
    const milestones = await AppDatabase.shared.fetchMilestones();
    const growth = await AppDatabase.shared.fetchGrowth();
    const achieved = milestones.filter((item: Milestone): boolean => item.happenedAt !== undefined).length;
    const hasGrowth = growth.some((item: GrowthMeasurement): boolean => {
      return item.heightCm !== undefined && item.weightKg !== undefined;
    });

    return activeEntries.length >= 2
      && milestones.length >= 118
      && milestones.length <= 160
      && achieved >= 18
      && hasGrowth;
  }

  private static async copyBundledMedia(context: common.UIAbilityContext, payload: IosBaselinePayload): Promise<void> {
    const mediaNames = new Set<string>();
    const thumbnailNames = new Set<string>();
    for (const item of payload.media) {
      if (item.localFileName !== undefined && item.localFileName.length > 0) mediaNames.add(item.localFileName);
      if (item.thumbnailFileName !== undefined && item.thumbnailFileName.length > 0) thumbnailNames.add(item.thumbnailFileName);
    }
    for (const profile of payload.profiles) {
      if (profile.avatarMediaFileName !== undefined && profile.avatarMediaFileName.length > 0) {
        mediaNames.add(profile.avatarMediaFileName);
      }
    }

    let copiedMedia = 0;
    let copiedThumbs = 0;
    for (const fileName of mediaNames.values()) {
      if (await IosBaselineImporter.copyRawFile(context, `ios_media/${fileName}`, fileName, false)) copiedMedia += 1;
    }
    for (const fileName of thumbnailNames.values()) {
      if (await IosBaselineImporter.copyRawFile(context, `ios_thumbnails/${fileName}`, fileName, true)) copiedThumbs += 1;
    }
    hilog.warn(DOMAIN, 'Bubu', `iOS 媒体已导入: media=${copiedMedia}/${mediaNames.size}, thumbs=${copiedThumbs}/${thumbnailNames.size}`);
  }

  private static async copyRawFile(context: common.UIAbilityContext, rawPath: string, fileName: string, thumbnail: boolean): Promise<boolean> {
    try {
      const bytes = await context.resourceManager.getRawFileContent(rawPath);
      const data = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      return thumbnail
        ? MediaStore.shared.writeImportedThumbnail(fileName, data)
        : MediaStore.shared.writeImportedMedia(fileName, data);
    } catch (e) {
      hilog.warn(DOMAIN, 'Bubu', `导入媒体失败: ${rawPath}`);
      return false;
    }
  }

  private static async markServerBaselineReady(store: preferences.Preferences): Promise<void> {
    const futureCursor = APIClient.syncTimestampString(new Date(Date.UTC(2099, 0, 1, 0, 0, 0, 0)));
    const collections: string[] = [
      'entries',
      'media',
      'milestones',
      'firsttimes',
      'members',
      'childprofile',
      'healthrecords',
      'vaccinerecords',
      'growthmeasurements',
      'comments',
      'voicenotes',
      'timecapsules'
    ];
    for (const collection of collections) {
      await store.put(`cursor_${collection}`, futureCursor);
    }

    const baselineIdentity = IosBaselineImporter.serverBaselineIdentity();
    if (baselineIdentity.length > 0) {
      await store.put('server_baseline_identity_v4', baselineIdentity);
    }
  }

  private static serverBaselineIdentity(): string {
    const base = ServerConfig.shared.baseURLString.trim().replace(/\/+$/, '');
    const account = ServerConfig.shared.accountEmail.trim().toLowerCase();
    if (base.length === 0 || account.length === 0) return '';
    return `${base}|${account}`;
  }
}
