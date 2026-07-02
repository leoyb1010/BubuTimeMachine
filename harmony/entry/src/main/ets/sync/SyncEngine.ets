import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences, relationalStore } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import { APIClient } from '../services/APIClient';
import { ServerConfig } from '../services/ServerConfig';
import { MediaStore } from '../services/MediaStore';
import { AppDatabase } from '../data/AppDatabase';
import { SyncState, MediaType } from '../models/Enums';
import { Entry, ChildProfile, Media, Milestone, TimeCapsule, HealthRecord, VoiceNote,
  FamilyMember, GrowthMeasurement, VaccineRecord, Comment, FirstTime, PendingDeletion } from '../models/Models';
import { UploadedFileResult } from '../services/DTOs';
import { MILESTONE_PRESETS } from '../models/MilestoneTemplates';

const DOMAIN = 0x0000;

interface GrowthMetricValues {
  heightCm?: number;
  weightKg?: number;
  headCircumferenceCm?: number;
}

// MARK: - 同步引擎（对照 iOS Services/Sync/SyncEngine.swift）
// 双向收敛：本地未同步（local/failed/uploading）的各集合推送到 PocketBase；远端变更按游标拉回本地。
// 离线优先：未配置或断网时静默保持离线，本地全功能可用；联网后自动补传。
// 增量游标 clientUpdatedAt 按集合持久化（Preferences）；任一集合拉取失败该集合游标不推进，下轮补拉。
// 游标回退 60 秒容忍时钟偏差（合并幂等）。轮询 30s；进后台停轮询省电。
// 冲突解决：以 syncState===synced 为「本地无未推改动」的判据——仅当本地已同步时才用远端覆盖，
//           避免踩掉本地草稿（对照 iOS mergeRemoteX 内的 existing.syncState == .synced 判断），
//           等价于「clientUpdatedAt 较新者胜」的实际效果（本地有 dirty 即视为本地较新）。
export class SyncEngine {
  static readonly shared = new SyncEngine();

  // iOS: cursorOverlap = 60s —— 游标回退 60 秒容忍时钟偏差。
  private static readonly cursorOverlapMs: number = 60 * 1000;

  private pollTimerId: number = -1;
  private syncing: boolean = false;
  private needsAnotherSync: boolean = false;
  private strictPullFailures: boolean = false;
  private serverMirrorMode: boolean = false;
  private serverSeen: Map<string, Set<string>> = new Map<string, Set<string>>();
  private cursorStore: preferences.Preferences | null = null;
  private appContext: common.UIAbilityContext | null = null;

  private constructor() {}

  // 由 EntryAbility 注入上下文，打开游标用的 Preferences 实例（对照 iOS UserDefaults）。
  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.appContext = context;
    if (!this.cursorStore) {
      this.cursorStore = await preferences.getPreferences(context, 'bubu_sync_cursor');
    }
  }

  // 回前台：启动 30s 轮询 + 立刻补一轮（对照 iOS start()）。
  start(): void {
    if (!ServerConfig.shared.isConfigured) {
      this.stopPolling();
      return;
    }
    if (this.pollTimerId === -1) {
      this.pollTimerId = setInterval(() => {
        if (ServerConfig.shared.isConfigured) this.syncNow();
      }, 30000);
    }
    this.syncNow();
  }

  // 进后台：停轮询省电（对照 iOS stopPolling()）。
  stopPolling(): void {
    if (this.pollTimerId !== -1) {
      clearInterval(this.pollTimerId);
      this.pollTimerId = -1;
    }
  }

  // 手动触发一次同步（设置页/下拉刷新可调，对照 iOS syncNow → scheduleSync）。
  // 已在跑则置 needsAnotherSync，跑完自动再来一轮（对照 iOS scheduleSync）。
  async syncNow(): Promise<void> {
    const cfg = ServerConfig.shared;
    if (!cfg.isConfigured) return;
    if (this.syncing) {
      this.needsAnotherSync = true;
      return;
    }
    if (!(await this.isServerBaselineReady())) {
      await this.pullServerToLocalNow();
      return;
    }
    this.syncing = true;
    try {
      await this.connectAndSync();
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `同步异常: ${JSON.stringify(e)}`);
    } finally {
      this.syncing = false;
    }
    if (this.needsAnotherSync) {
      this.needsAnotherSync = false;
      await this.syncNow();
    }
  }

  // 手动从服务器补齐本机：清空增量游标后只拉远端，不先推本地。
  // 用于新设备/重装/端间数量不一致时，把 iOS 已上传的数据完整拉回鸿蒙。
  async pullServerToLocalNow(): Promise<string> {
    const cfg = ServerConfig.shared;
    if (!cfg.isConfigured) return '还没有登录服务器';
    if (await this.shouldProtectIosBaselineFromServerPull()) {
      return await this.repairServerFilesWithoutClearingNow();
    }
    if (this.syncing) {
      const idle = await this.waitForIdle(15000);
      if (!idle) {
        this.needsAnotherSync = true;
        return '后台同步还在进行，请稍后再点一次';
      }
    }
    this.syncing = true;
    try {
      const ok = await APIClient.shared.ping();
      if (!ok) return '服务器连接失败，请检查网络和服务器地址';
      const authed = await APIClient.shared.authenticate();
      if (!authed) return '账号或密码验证失败，请重新登录服务器账号';
      await AppDatabase.shared.clearServerBackedData();
      await this.resetCursors();
      this.strictPullFailures = true;
      this.serverMirrorMode = true;
      this.serverSeen.clear();
      await this.pullRemote();
      await this.pruneLocalToServerMirror();
      await AppDatabase.shared.normalizeMilestonesByTitle();
      await this.downloadMissingFiles(true);
      await this.markServerBaselineReady();
      hilog.info(DOMAIN, 'Bubu', '服务器数据已补齐到本机');
      return '服务器数据已同步到本机，本机旧数据已清理';
    } catch (e) {
      const text = SyncEngine.errorText(e);
      hilog.error(DOMAIN, 'Bubu', `从服务器拉取失败: ${text}`);
      return `同步失败：${text}`;
    } finally {
      this.strictPullFailures = false;
      this.serverMirrorMode = false;
      this.serverSeen.clear();
      this.syncing = false;
    }
  }

  private async repairServerFilesWithoutClearingNow(): Promise<string> {
    if (this.syncing) {
      const idle = await this.waitForIdle(15000);
      if (!idle) {
        this.needsAnotherSync = true;
        return '后台同步还在进行，请稍后再点一次';
      }
    }
    this.syncing = true;
    try {
      const ok = await APIClient.shared.ping();
      if (!ok) return '服务器连接失败，请检查网络和服务器地址';
      const authed = await APIClient.shared.authenticate();
      if (!authed) return '账号或密码验证失败，请重新登录服务器账号';

      // 保护触发时不能清本机数据；重新拉全量记录只用于补齐 remoteURL，
      // 再把远端文件下载进本机沙盒。
      await this.resetCursors();
      this.strictPullFailures = true;
      this.serverMirrorMode = true;
      this.serverSeen.clear();
      await this.pullRemote();
      await AppDatabase.shared.normalizeMilestonesByTitle();
      await this.downloadMissingFiles(true);
      await this.markServerBaselineReady();
      hilog.info(DOMAIN, 'Bubu', '已在保护模式下补齐服务器媒体文件');
      return '已保护本机旧数据：未清理旧数据，已补拉服务器记录并补下载图片/语音';
    } catch (e) {
      const text = SyncEngine.errorText(e);
      hilog.error(DOMAIN, 'Bubu', `保护模式补下载失败: ${text}`);
      return `同步失败：${text}`;
    } finally {
      this.strictPullFailures = false;
      this.serverMirrorMode = false;
      this.serverSeen.clear();
      this.syncing = false;
    }
  }

  private async waitForIdle(timeoutMs: number): Promise<boolean> {
    const started = Date.now();
    while (this.syncing && Date.now() - started < timeoutMs) {
      await new Promise<void>((resolve) => {
        setTimeout(() => { resolve(); }, 250);
      });
    }
    return !this.syncing;
  }

  private static errorText(e: Object): string {
    if (e instanceof Error) return e.message;
    const text = JSON.stringify(e);
    return text.length > 0 ? text : '未知错误';
  }

  // 一轮：ping → 登录 → 推本地 → 拉远端 → 补下缺失文件（对照 iOS connectAndSync）。
  private async connectAndSync(): Promise<void> {
    const ok = await APIClient.shared.ping();
    if (!ok) {
      hilog.warn(DOMAIN, 'Bubu', '同步：连不上家里的服务器，离线可用');
      return;
    }
    const authed = await APIClient.shared.authenticate();
    if (!authed) {
      hilog.warn(DOMAIN, 'Bubu', '同步：账号状态需要重新确认');
      return;
    }
    await this.pushLocal();
    await this.pullRemote();
    await this.downloadMissingFiles();
    hilog.info(DOMAIN, 'Bubu', '同步完成');
  }

  // MARK: - 推：本地 → 远端（对照 iOS pushLocal）

  private async pushLocal(): Promise<void> {
    await AppDatabase.shared.normalizeMilestonesByTitle();
    // 先消费删除队列：删除意图优先于数据推送，避免「先推后删」竞态（对照 iOS processPendingDeletions）。
    await this.processPendingDeletions();
    await this.pushEntries();
    await this.pushUnsyncedMedia();
    await this.pushChildProfile();
    await this.pushMilestones();
    await this.pushFirstTimes();
    await this.pushFamilyMembers();
    await this.pushHealthRecords();
    await this.pushVaccineRecords();
    await this.pushGrowthMeasurements();
    await this.pushComments();
    await this.pushVoiceNotes();
    await this.pushTimeCapsules();
  }

  private static isDirty(s: SyncState): boolean {
    return s === SyncState.local || s === SyncState.failed || s === SyncState.uploading;
  }

  // —— 删除队列消费（对照 iOS processPendingDeletions / performRemoteDeletion）——
  // 远端 404 视作完成出队；其余失败留队下轮重试。
  private async processPendingDeletions(): Promise<void> {
    const deletions: PendingDeletion[] = await AppDatabase.shared.fetchPendingDeletions();
    for (const d of deletions) {
      try {
        await APIClient.shared.deleteRecord(d.collection, d.remoteId);
        await AppDatabase.shared.dequeueDeletion(d.id);
      } catch (e) {
        const msg: string = (e instanceof Error) ? e.message : JSON.stringify(e);
        if (msg.indexOf('404') >= 0) {
          await AppDatabase.shared.dequeueDeletion(d.id); // 远端本就不存在，视作完成
        } else {
          hilog.warn(DOMAIN, 'Bubu', `删除同步失败留队重试: ${d.collection}/${d.remoteId}`);
        }
      }
    }
  }

  // —— Entry（对照 iOS pushLocal 的 Entry 循环 + makeDTO(Entry)）——
  private async pushEntries(): Promise<void> {
    const entries: Entry[] = await AppDatabase.shared.fetchEntries(true);
    for (const e of entries) {
      if (!SyncEngine.isDirty(e.syncState)) continue;
      const body: Record<string, Object> = {
        'happenedAt': new Date(e.happenedAt).toISOString(),
        'authorRole': e.authorRole,
        'isArchived': e.isArchived,
        'createdAt': new Date(e.createdAt).toISOString()
      };
      if (e.title !== undefined) body['title'] = e.title;
      if (e.note !== undefined) body['note'] = e.note;
      if (e.firstPersonNote !== undefined) body['firstPersonNote'] = e.firstPersonNote;
      if (e.locationName !== undefined) body['locationName'] = e.locationName;
      if (e.latitude !== undefined) body['latitude'] = e.latitude;
      if (e.longitude !== undefined) body['longitude'] = e.longitude;
      if (e.moodRaw !== undefined) body['mood'] = e.moodRaw;
      if (e.editedAt !== undefined) body['editedAt'] = new Date(e.editedAt).toISOString();
      try {
        const saved = await APIClient.shared.upsert('entries', e.id, body);
        const remoteId = saved['id'] as string;
        await AppDatabase.shared.updateEntryFields(e.id, { remoteId: remoteId, syncState: SyncState.synced });
      } catch (err) {
        await AppDatabase.shared.updateEntryFields(e.id, { syncState: SyncState.failed });
        hilog.warn(DOMAIN, 'Bubu', `推送 Entry 失败 ${e.id}`);
      }
    }
  }

  // —— ChildProfile（对照 iOS pushLocalJSONObjects 的 ChildProfile 分支，含头像补传）——
  private async pushChildProfile(): Promise<void> {
    const p: ChildProfile | null = await AppDatabase.shared.fetchChildProfile();
    if (!p || !SyncEngine.isDirty(p.syncState)) return;
    const body: Record<string, Object> = {
      'name': p.name,
      'birthday': new Date(p.birthday).toISOString(),
      'createdAt': new Date(p.createdAt).toISOString()
    };
    if (p.gender !== undefined) body['gender'] = p.gender;
    if (p.bloodType !== undefined) body['bloodType'] = p.bloodType; // 含血型同步（与 iOS 一致）
    if (p.birthPlace !== undefined) body['birthPlace'] = p.birthPlace;
    try {
      const saved = await APIClient.shared.upsert('childprofile', p.id, body);
      p.remoteId = saved['id'] as string;
      // 头像变更后 avatarRemoteURL 为空 → 补传到 childprofile.avatar（对照 iOS uploadChildAvatar）。
      if (p.avatarMediaFileName !== undefined && p.avatarRemoteURL === undefined) {
        const fileName = p.avatarMediaFileName;
        if (MediaStore.shared.exists(fileName)) {
          const filePath = MediaStore.shared.fullPath(fileName);
          const fields: Record<string, string> = { 'createdAt': new Date(p.createdAt).toISOString() };
          const res: UploadedFileResult = await APIClient.shared.uploadFile(
            'childprofile', p.id, fields, 'avatar', filePath, fileName);
          p.remoteId = res.recordId;
          p.avatarRemoteURL = APIClient.shared.fileURL('childprofile', res.recordId, res.storedFileName);
        }
      }
      p.syncState = SyncState.synced;
      await AppDatabase.shared.upsertChildProfile(p);
    } catch (e) {
      p.syncState = SyncState.failed;
      await AppDatabase.shared.upsertChildProfile(p);
    }
  }

  // —— Milestone（对照 iOS makeDTO(Milestone)）——
  private async pushMilestones(): Promise<void> {
    const items: Milestone[] = await AppDatabase.shared.fetchMilestones();
    for (const m of items) {
      if (!SyncEngine.isDirty(m.syncState)) continue;
      if (SyncEngine.isLocalPresetPlaceholder(m)) {
        m.syncState = SyncState.synced;
        await AppDatabase.shared.upsertMilestone(m);
        continue;
      }
      const body: Record<string, Object> = {
        'title': m.title, 'category': m.category, 'emoji': m.emoji, 'isCustom': m.isCustom,
        'createdAt': new Date(m.createdAt).toISOString()
      };
      if (m.detail !== undefined) body['detail'] = m.detail;
      if (m.happenedAt !== undefined) body['happenedAt'] = new Date(m.happenedAt).toISOString();
      if (m.ageDescription !== undefined) body['ageDescription'] = m.ageDescription;
      try {
        const saved = await APIClient.shared.upsert('milestones', m.id, body);
        m.remoteId = saved['id'] as string;
        m.syncState = SyncState.synced;
        await AppDatabase.shared.upsertMilestone(m);
      } catch (e) {
        m.syncState = SyncState.failed;
        await AppDatabase.shared.upsertMilestone(m);
      }
    }
  }

  // —— FirstTime（对照 iOS makeDTO(FirstTime)）——
  private async pushFirstTimes(): Promise<void> {
    const items: FirstTime[] = await AppDatabase.shared.fetchFirstTimes();
    for (const f of items) {
      if (!SyncEngine.isDirty(f.syncState)) continue;
      const body: Record<string, Object> = {
        'what': f.what, 'happenedAt': new Date(f.happenedAt).toISOString(),
        'detectedByAI': f.detectedByAI, 'confirmedByParent': f.confirmedByParent,
        'createdAt': new Date(f.createdAt).toISOString()
      };
      if (f.entryId !== undefined) body['entryLocalId'] = f.entryId;
      try {
        const saved = await APIClient.shared.upsert('firsttimes', f.id, body);
        f.remoteId = saved['id'] as string;
        f.syncState = SyncState.synced;
        await AppDatabase.shared.insertFirstTime(f);
      } catch (e) {
        f.syncState = SyncState.failed;
        await AppDatabase.shared.insertFirstTime(f);
      }
    }
  }

  // —— FamilyMember（对照 iOS makeDTO(FamilyMember)）——
  private async pushFamilyMembers(): Promise<void> {
    const items: FamilyMember[] = await AppDatabase.shared.fetchMembers();
    for (const m of items) {
      if (!SyncEngine.isDirty(m.syncState)) continue;
      const body: Record<string, Object> = {
        'name': m.name, 'relation': m.relation, 'avatarEmoji': m.avatarEmoji,
        'themeColorHex': m.themeColorHex, 'isPrimary': m.isPrimary,
        'createdAt': new Date(m.createdAt).toISOString()
      };
      try {
        const saved = await APIClient.shared.upsert('members', m.id, body);
        m.remoteId = saved['id'] as string;
        m.syncState = SyncState.synced;
        await AppDatabase.shared.upsertMember(m);
      } catch (e) {
        m.syncState = SyncState.failed;
        await AppDatabase.shared.upsertMember(m);
      }
    }
  }

  // —— HealthRecord（对照 iOS makeDTO(HealthRecord)）——
  private async pushHealthRecords(): Promise<void> {
    const items: HealthRecord[] = await AppDatabase.shared.fetchHealth();
    for (const h of items) {
      if (!SyncEngine.isDirty(h.syncState)) continue;
      const body: Record<string, Object> = {
        'kind': h.kind, 'title': h.title, 'recordedAt': new Date(h.recordedAt).toISOString(),
        'tags': h.tags, 'createdAt': new Date(h.createdAt).toISOString()
      };
      if (h.detail !== undefined) body['detail'] = h.detail;
      if (h.amountText !== undefined) body['amountText'] = h.amountText;
      if (h.reaction !== undefined) body['reaction'] = h.reaction;
      if (h.amountValue !== undefined) body['amountValue'] = h.amountValue;
      if (h.amountUnit !== undefined) body['amountUnit'] = h.amountUnit;
      if (h.startAt !== undefined) body['startAt'] = new Date(h.startAt).toISOString();
      if (h.endAt !== undefined) body['endAt'] = new Date(h.endAt).toISOString();
      if (h.severity !== undefined) body['severity'] = h.severity;
      if (h.temperatureCelsius !== undefined) body['temperatureCelsius'] = h.temperatureCelsius;
      try {
        const saved = await APIClient.shared.upsert('healthrecords', h.id, body);
        h.remoteId = saved['id'] as string;
        h.syncState = SyncState.synced;
        await AppDatabase.shared.insertHealth(h);
      } catch (e) {
        h.syncState = SyncState.failed;
        await AppDatabase.shared.insertHealth(h);
      }
    }
  }

  // —— VaccineRecord（对照 iOS makeDTO(VaccineRecord)）——
  private async pushVaccineRecords(): Promise<void> {
    const items: VaccineRecord[] = await AppDatabase.shared.fetchVaccines();
    for (const v of items) {
      if (!SyncEngine.isDirty(v.syncState)) continue;
      const body: Record<string, Object> = {
        'vaccineName': v.vaccineName, 'injectedAt': new Date(v.injectedAt).toISOString(),
        'sourceRaw': v.source, 'createdAt': new Date(v.createdAt).toISOString()
      };
      if (v.doseId !== undefined) body['doseId'] = v.doseId;
      if (v.doseLabel !== undefined) body['doseLabel'] = v.doseLabel;
      if (v.hospital !== undefined) body['hospital'] = v.hospital;
      if (v.injectionSite !== undefined) body['injectionSite'] = v.injectionSite;
      if (v.reaction !== undefined) body['reaction'] = v.reaction;
      if (v.note !== undefined) body['note'] = v.note;
      try {
        const saved = await APIClient.shared.upsert('vaccinerecords', v.id, body);
        v.remoteId = saved['id'] as string;
        v.syncState = SyncState.synced;
        await AppDatabase.shared.insertVaccine(v);
      } catch (e) {
        if (SyncEngine.isMissingOptionalCollectionError(e, 'vaccinerecords')) {
          try {
            const saved = await APIClient.shared.upsert('healthrecords', v.id, SyncEngine.vaccineHealthFallbackBody(v));
            v.remoteId = saved['id'] as string;
            v.source = 'health-fallback';
            v.syncState = SyncState.synced;
            await AppDatabase.shared.insertVaccine(v);
          } catch (fallbackError) {
            v.syncState = SyncState.failed;
            await AppDatabase.shared.insertVaccine(v);
          }
        } else {
          v.syncState = SyncState.failed;
          await AppDatabase.shared.insertVaccine(v);
        }
      }
    }
  }

  // —— GrowthMeasurement（对照 iOS makeDTO(GrowthMeasurement)）——
  private async pushGrowthMeasurements(): Promise<void> {
    const items: GrowthMeasurement[] = await AppDatabase.shared.fetchGrowth();
    for (const g of items) {
      if (!SyncEngine.isDirty(g.syncState)) continue;
      const body: Record<string, Object> = {
        'measuredAt': new Date(g.measuredAt).toISOString(),
        'sourceRaw': g.source, 'createdAt': new Date(g.createdAt).toISOString()
      };
      if (g.heightCm !== undefined) body['heightCm'] = g.heightCm;
      if (g.weightKg !== undefined) body['weightKg'] = g.weightKg;
      if (g.headCircumferenceCm !== undefined) body['headCircumferenceCm'] = g.headCircumferenceCm;
      if (g.note !== undefined) body['note'] = g.note;
      try {
        const saved = await APIClient.shared.upsert('growthmeasurements', g.id, body);
        g.remoteId = saved['id'] as string;
        g.syncState = SyncState.synced;
        await AppDatabase.shared.insertGrowth(g);
      } catch (e) {
        if (SyncEngine.isMissingOptionalCollectionError(e, 'growthmeasurements')) {
          try {
            const saved = await APIClient.shared.upsert('healthrecords', g.id, SyncEngine.growthHealthFallbackBody(g));
            g.remoteId = saved['id'] as string;
            g.source = 'health-fallback';
            g.syncState = SyncState.synced;
            await AppDatabase.shared.insertGrowth(g);
          } catch (fallbackError) {
            g.syncState = SyncState.failed;
            await AppDatabase.shared.insertGrowth(g);
          }
        } else {
          g.syncState = SyncState.failed;
          await AppDatabase.shared.insertGrowth(g);
        }
      }
    }
  }

  // —— Comment（家人合奏：文字 + 可选语音文件，对照 iOS pushLocalFileObjects 的 Comment 分支）——
  // NOTE: AppDatabase 仅提供按 entryId 查 Comment（fetchCommentsForEntry），故遍历所有 Entry 收集脏评论。
  private async pushComments(): Promise<void> {
    const entries: Entry[] = await AppDatabase.shared.fetchEntries(true);
    for (const e of entries) {
      const comments: Comment[] = await AppDatabase.shared.fetchCommentsForEntry(e.id);
      for (const c of comments) {
        if (!SyncEngine.isDirty(c.syncState)) continue;
        const body: Record<string, Object> = {
          'entryLocalId': c.entryId, 'authorRole': c.authorRole,
          'voiceDuration': c.voiceDuration, 'voiceWaveform': c.voiceWaveform,
          'createdAt': new Date(c.createdAt).toISOString()
        };
        if (c.text !== undefined) body['text'] = c.text;
        try {
          const saved = await APIClient.shared.upsert('comments', c.id, body);
          c.remoteId = saved['id'] as string;
          // 语音补充上传（对照 iOS uploadCommentVoice）。
          if (c.voiceFileName !== undefined && MediaStore.shared.exists(c.voiceFileName)) {
            const filePath = MediaStore.shared.fullPath(c.voiceFileName);
            const fields: Record<string, string> = {
              'entryLocalId': c.entryId, 'authorRole': c.authorRole,
              'createdAt': new Date(c.createdAt).toISOString()
            };
            const res: UploadedFileResult = await APIClient.shared.uploadFile(
              'comments', c.id, fields, 'voiceFile', filePath, c.voiceFileName);
            c.remoteId = res.recordId;
            c.remoteURL = APIClient.shared.fileURL('comments', res.recordId, res.storedFileName);
          }
          c.syncState = SyncState.synced;
          await AppDatabase.shared.insertComment(c);
        } catch (err) {
          c.syncState = SyncState.failed;
          await AppDatabase.shared.insertComment(c);
        }
      }
    }
  }

  // —— VoiceNote（附在 Entry 上的语音，对照 iOS pushLocalFileObjects 的 VoiceNote 分支）——
  private async pushVoiceNotes(): Promise<void> {
    const entries: Entry[] = await AppDatabase.shared.fetchEntries(true);
    for (const e of entries) {
      const notes: VoiceNote[] = await AppDatabase.shared.fetchVoiceForEntry(e.id);
      for (const n of notes) {
        if (!SyncEngine.isDirty(n.syncState)) continue;
        const body: Record<string, Object> = {
          'entryLocalId': n.entryId, 'authorRole': n.authorRole,
          'durationSeconds': n.durationSeconds, 'waveform': n.waveformSamples,
          'createdAt': new Date(n.createdAt).toISOString()
        };
        if (n.transcript !== undefined) body['transcript'] = n.transcript;
        try {
          const saved = await APIClient.shared.upsert('voicenotes', n.id, body);
          n.remoteId = saved['id'] as string;
          // 语音文件上传（对照 iOS uploadVoiceNote）。
          if (n.localFileName !== undefined && MediaStore.shared.exists(n.localFileName)) {
            const filePath = MediaStore.shared.fullPath(n.localFileName);
            const fields: Record<string, string> = {
              'entryLocalId': n.entryId, 'authorRole': n.authorRole,
              'createdAt': new Date(n.createdAt).toISOString()
            };
            const res: UploadedFileResult = await APIClient.shared.uploadFile(
              'voicenotes', n.id, fields, 'file', filePath, n.localFileName);
            n.remoteId = res.recordId;
            n.remoteURL = APIClient.shared.fileURL('voicenotes', res.recordId, res.storedFileName);
          }
          n.syncState = SyncState.synced;
          await this.replaceVoiceNote(n);
        } catch (err) {
          n.syncState = SyncState.failed;
          await this.replaceVoiceNote(n);
        }
      }
    }
  }

  // VoiceNote 无 upsert 方法：先删旧行再插入（id 主键）实现回写（对照 iOS context.save）。
  private async replaceVoiceNote(n: VoiceNote): Promise<void> {
    const store = AppDatabase.shared.raw;
    if (store) {
      try {
        await store.executeSql(`DELETE FROM voice_note WHERE id = '${n.id}'`);
      } catch (e) {}
    }
    await AppDatabase.shared.insertVoiceNote(n);
  }

  // —— Media（照片/视频文件上传，对照 iOS pushUnsyncedMedia / pushMediaItem）——
  private async pushUnsyncedMedia(): Promise<void> {
    const all: Media[] = await AppDatabase.shared.fetchAllMedia();
    for (const m of all) {
      if (!SyncEngine.isDirty(m.syncState)) continue;
      await this.pushMediaItem(m);
    }
  }

  private async pushMediaItem(m: Media): Promise<void> {
    if (m.localFileName === undefined) {
      await this.updateMediaFields(m.id, { syncState: SyncState.failed });
      return;
    }
    const fileName = m.localFileName;
    if (!MediaStore.shared.exists(fileName)) {
      await this.updateMediaFields(m.id, { syncState: SyncState.failed });
      return;
    }
    await this.updateMediaFields(m.id, { syncState: SyncState.uploading });
    const filePath = MediaStore.shared.fullPath(fileName);
    const fields: Record<string, string> = {
      'entryLocalId': m.entryId, 'mediaType': m.typeRaw,
      'aiTags': JSON.stringify(m.aiTags), 'createdAt': new Date(m.createdAt).toISOString()
    };
    if (m.durationSeconds !== undefined) fields['durationSeconds'] = `${m.durationSeconds}`;
    if (m.width !== undefined) fields['width'] = `${m.width}`;
    if (m.height !== undefined) fields['height'] = `${m.height}`;
    try {
      const res: UploadedFileResult = await APIClient.shared.uploadFile(
        'media', m.id, fields, 'file', filePath, fileName);
      const remoteURL = APIClient.shared.fileURL('media', res.recordId, res.storedFileName);
      await this.updateMediaFields(m.id, {
        remoteId: res.recordId, remoteURL: remoteURL, uploadProgress: 1, syncState: SyncState.synced
      });
    } catch (e) {
      await this.updateMediaFields(m.id, { syncState: SyncState.failed });
    }
  }

  // Media 行级更新（AppDatabase 未暴露 update，直接用 raw RdbStore，对照 iOS context.save）。
  private async updateMediaFields(id: string, fields: relationalStore.ValuesBucket): Promise<void> {
    const store = AppDatabase.shared.raw;
    if (!store) return;
    const pred = new relationalStore.RdbPredicates('media');
    pred.equalTo('id', id);
    try {
      await store.update(fields, pred);
    } catch (e) {}
  }

  // —— TimeCapsule（含加密 blob 文件上传，对照 iOS pushTimeCapsules / uploadTimeCapsuleBlob）——
  private async pushTimeCapsules(): Promise<void> {
    const items: TimeCapsule[] = await AppDatabase.shared.fetchCapsules();
    for (const c of items) {
      if (!SyncEngine.isDirty(c.syncState)) continue;
      const body: Record<string, Object> = {
        'title': c.title, 'fromRole': c.fromRole, 'unlockAt': new Date(c.unlockAt).toISOString(),
        'isLocked': c.isLocked, 'createdAt': new Date(c.createdAt).toISOString()
      };
      if (c.coverEmoji !== undefined) body['coverEmoji'] = c.coverEmoji;
      try {
        const saved = await APIClient.shared.upsert('timecapsules', c.id, body);
        c.remoteId = saved['id'] as string;
        // 加密载荷上传（对照 iOS uploadTimeCapsuleBlob）。
        if (c.encryptedBlobFileName !== undefined && MediaStore.shared.exists(c.encryptedBlobFileName)) {
          const filePath = MediaStore.shared.fullPath(c.encryptedBlobFileName);
          const fields: Record<string, string> = {
            'title': c.title, 'fromRole': c.fromRole,
            'unlockAt': new Date(c.unlockAt).toISOString(),
            'createdAt': new Date(c.createdAt).toISOString()
          };
          const res: UploadedFileResult = await APIClient.shared.uploadFile(
            'timecapsules', c.id, fields, 'encryptedBlob', filePath, c.encryptedBlobFileName);
          c.remoteId = res.recordId;
        }
        c.syncState = SyncState.synced;
        await this.replaceCapsule(c);
      } catch (e) {
        c.syncState = SyncState.failed;
        await this.replaceCapsule(c);
      }
    }
  }

  // TimeCapsule 无 upsert：删旧再插（id 主键）回写。
  private async replaceCapsule(c: TimeCapsule): Promise<void> {
    await AppDatabase.shared.deleteCapsule(c.id);
    await AppDatabase.shared.insertCapsule(c);
  }

  // MARK: - 拉：远端 → 本地（对照 iOS pullRemote）
  // 每个集合独立游标：成功才推进，失败下次补拉，互不影响。

  private async pullRemote(): Promise<void> {
    await this.pullEntries();
    await this.pullMedia();
    await this.pullMilestones();
    await this.pullFirstTimes();
    await this.pullFamilyMembers();
    await this.pullChildProfile();
    await this.pullHealthRecords();
    await this.pullVaccineRecords();
    await this.pullGrowthMeasurements();
    await this.pullComments();
    await this.pullVoiceNotes();
    await this.pullTimeCapsules();
  }

  // 通用拉取骨架：拉 → 合并 → 推进游标（对照 iOS pull<DTO>）。
  // mergeFn 抛错由本方法吞掉外层 try；游标只在整批成功后推进。
  private async pullCollection(
    collection: string,
    merge: (r: Record<string, Object>) => Promise<boolean | void>
  ): Promise<void> {
    const startedMs = Date.now();
    try {
      const cursor = await this.getCursor(collection);
      const records = await APIClient.shared.fetchRecords(collection, cursor);
      if (this.serverMirrorMode) {
        const seen = new Set<string>();
        for (const r of records) {
          if (collection === 'milestones' && SyncEngine.isRemotePresetPlaceholder(r)) continue;
          const localId = SyncEngine.recordLocalId(r);
          if (localId !== undefined) seen.add(localId);
        }
        this.serverSeen.set(collection, seen);
      }
      let fullyMerged = true;
      for (const r of records) {
        const merged = await merge(r);
        if (merged === false) fullyMerged = false;
      }
      if (!fullyMerged) {
        hilog.warn(DOMAIN, 'Bubu', `拉取 ${collection} 有记录暂未合并，游标保留等待下轮补拉`);
        return;
      }
      // 游标回退 60s 容忍时钟偏差（对照 iOS setCursor 的 -cursorOverlap）。
      await this.setCursor(collection, APIClient.syncTimestampString(new Date(startedMs - SyncEngine.cursorOverlapMs)));
    } catch (e) {
      if (SyncEngine.isMissingOptionalCollectionError(e, collection)) {
        hilog.warn(DOMAIN, 'Bubu', `服务器暂缺可选集合 ${collection}，已走兼容同步`);
        return;
      }
      if (this.strictPullFailures) {
        throw new Error(SyncEngine.errorText(e));
      }
      // 瞬时拉取失败不报红：游标不推进，下轮自动补拉（对照 iOS pull 的 catch 软失败）。
      hilog.warn(DOMAIN, 'Bubu', `拉取 ${collection} 失败，下轮补拉: ${JSON.stringify(e)}`);
    }
  }

  private async isPendingDeletion(collection: string, remoteId?: string): Promise<boolean> {
    if (remoteId === undefined || remoteId.length === 0) return false;
    const pendings = await AppDatabase.shared.fetchPendingDeletions();
    return pendings.some((d: PendingDeletion): boolean => d.collection === collection && d.remoteId === remoteId);
  }

  private async pruneLocalToServerMirror(): Promise<void> {
    await this.pruneEntriesToMirror();
    await this.pruneMediaToMirror();
    await this.pruneMilestonesToMirror();
    await this.pruneHealthToMirror();
    await this.pruneGrowthToMirror();
    await this.pruneVaccinesToMirror();
    await this.pruneFirstTimesToMirror();
    await this.pruneMembersToMirror();
    await this.pruneCapsulesToMirror();
  }

  private seen(collection: string): Set<string> | undefined {
    return this.serverSeen.get(collection);
  }

  private shouldPrune(collection: string, localId: string): boolean {
    const seen = this.seen(collection);
    return seen !== undefined && !seen.has(localId);
  }

  private shouldPruneFromAny(collections: string[], localId: string): boolean {
    let hasMirrorCollection = false;
    for (const collection of collections) {
      const seen = this.seen(collection);
      if (seen === undefined) continue;
      hasMirrorCollection = true;
      if (seen.has(localId)) return false;
    }
    return hasMirrorCollection;
  }

  private async pruneEntriesToMirror(): Promise<void> {
    if (this.seen('entries') === undefined) return;
    const entries = await AppDatabase.shared.fetchEntries(true);
    for (const entry of entries) {
      if (this.shouldPrune('entries', entry.id)) await AppDatabase.shared.deleteEntryHard(entry.id);
    }
  }

  private async pruneMediaToMirror(): Promise<void> {
    if (this.seen('media') === undefined) return;
    const media = await AppDatabase.shared.fetchAllMedia();
    for (const item of media) {
      if (this.shouldPrune('media', item.id)) await AppDatabase.shared.deleteMedia(item.id);
    }
  }

  private async pruneMilestonesToMirror(): Promise<void> {
    if (this.seen('milestones') === undefined) return;
    const milestones = await AppDatabase.shared.fetchMilestones();
    for (const item of milestones) {
      if (this.shouldPrune('milestones', item.id)) await AppDatabase.shared.deleteMilestone(item.id);
    }
  }

  private async pruneHealthToMirror(): Promise<void> {
    if (this.seen('healthrecords') === undefined) return;
    const records = await AppDatabase.shared.fetchHealth();
    for (const item of records) {
      if (this.shouldPrune('healthrecords', item.id)) await AppDatabase.shared.deleteHealth(item.id);
    }
  }

  private async pruneGrowthToMirror(): Promise<void> {
    const collections = ['growthmeasurements', 'healthrecords'];
    if (!this.hasAnySeen(collections)) return;
    const records = await AppDatabase.shared.fetchGrowth();
    for (const item of records) {
      if (this.shouldPruneFromAny(collections, item.id)) await AppDatabase.shared.deleteGrowth(item.id);
    }
  }

  private async pruneVaccinesToMirror(): Promise<void> {
    const collections = ['vaccinerecords', 'healthrecords'];
    if (!this.hasAnySeen(collections)) return;
    const records = await AppDatabase.shared.fetchVaccines();
    for (const item of records) {
      if (this.shouldPruneFromAny(collections, item.id)) await AppDatabase.shared.deleteVaccine(item.id);
    }
  }

  private async pruneFirstTimesToMirror(): Promise<void> {
    if (this.seen('firsttimes') === undefined) return;
    const records = await AppDatabase.shared.fetchFirstTimes();
    for (const item of records) {
      if (this.shouldPrune('firsttimes', item.id)) await AppDatabase.shared.deleteFirstTime(item.id);
    }
  }

  private async pruneMembersToMirror(): Promise<void> {
    if (this.seen('members') === undefined) return;
    const records = await AppDatabase.shared.fetchMembers();
    for (const item of records) {
      if (this.shouldPrune('members', item.id)) await AppDatabase.shared.deleteMember(item.id);
    }
  }

  private async pruneCapsulesToMirror(): Promise<void> {
    if (this.seen('timecapsules') === undefined) return;
    const records = await AppDatabase.shared.fetchCapsules();
    for (const item of records) {
      if (this.shouldPrune('timecapsules', item.id)) await AppDatabase.shared.deleteCapsule(item.id);
    }
  }

  private hasAnySeen(collections: string[]): boolean {
    return collections.some((collection: string): boolean => this.seen(collection) !== undefined);
  }

  private static isMissingOptionalCollectionError(e: Object, collection: string): boolean {
    if (collection !== 'vaccinerecords' && collection !== 'growthmeasurements') return false;
    const text = SyncEngine.errorText(e);
    return text.indexOf('404') >= 0 || text.indexOf('not found') >= 0 || text.indexOf('Not Found') >= 0;
  }

  private static rStr(r: Record<string, Object>, key: string): string | undefined {
    const v = r[key];
    return (typeof v === 'string' && (v as string).length > 0) ? (v as string) : undefined;
  }

  private static rFileName(r: Record<string, Object>, key: string): string | undefined {
    const direct = SyncEngine.rStr(r, key);
    if (direct !== undefined) return direct;
    const v = r[key];
    if (Array.isArray(v) && v.length > 0) {
      const first = `${v[0]}`;
      return first.length > 0 ? first : undefined;
    }
    return undefined;
  }

  private static remoteFileURL(r: Record<string, Object>, collection: string, fileField: string,
                               remoteField: string = 'remoteURL'): string | undefined {
    const remote = SyncEngine.rStr(r, remoteField);
    if (remote !== undefined) return remote;
    const recordId = SyncEngine.rStr(r, 'id');
    const fileName = SyncEngine.rFileName(r, fileField);
    if (recordId === undefined || fileName === undefined) return undefined;
    return APIClient.shared.fileURL(collection, recordId, fileName);
  }

  private static rNum(r: Record<string, Object>, key: string): number | undefined {
    const v = r[key];
    return (typeof v === 'number') ? (v as number) : undefined;
  }

  private static rBool(r: Record<string, Object>, key: string): boolean {
    const v = r[key];
    return v === true || v === 1 || v === '1';
  }

  // ISO 字符串 → epoch ms（对照 iOS ISO8601 解码）。空/非法回退 0 或 fallback。
  private static rDate(r: Record<string, Object>, key: string, fallback: number = 0): number {
    const s = SyncEngine.rStr(r, key);
    if (s === undefined) return fallback;
    const t = Date.parse(s);
    return isNaN(t) ? fallback : t;
  }

  private static rStrArray(r: Record<string, Object>, key: string): string[] {
    const v = r[key];
    if (Array.isArray(v)) return (v as Object[]).map((x) => `${x}`);
    return [];
  }

  private static rNumArray(r: Record<string, Object>, key: string): number[] {
    const v = r[key];
    if (Array.isArray(v)) {
      const out: number[] = [];
      for (const x of (v as Object[])) { if (typeof x === 'number') out.push(x as number); }
      return out;
    }
    return [];
  }

  private static recordLocalId(r: Record<string, Object>): string | undefined {
    return SyncEngine.rStr(r, 'localId') ?? SyncEngine.rStr(r, 'id');
  }

  // —— Entry 合并（对照 iOS mergeRemoteEntry：synced 才覆盖，避免踩本地草稿）——
  private async pullEntries(): Promise<void> {
    await this.pullCollection('entries', async (r: Record<string, Object>): Promise<boolean | void> => {
      const localId = SyncEngine.recordLocalId(r);
      if (localId === undefined) return;
      if (await this.isPendingDeletion('entries', SyncEngine.rStr(r, 'id'))) return true;
      const existing = await this.findEntry(localId);
      if (existing) {
        if (existing.syncState !== SyncState.synced && !this.serverMirrorMode) return false; // 本地有未推改动，远端不覆盖
        SyncEngine.applyEntry(r, existing);
        existing.remoteId = SyncEngine.rStr(r, 'id');
        await AppDatabase.shared.updateEntryFields(existing.id, SyncEngine.entryToFields(existing));
      } else {
        const e: Entry = {
          id: localId,
          happenedAt: SyncEngine.rDate(r, 'happenedAt', Date.now()),
          authorRole: SyncEngine.rStr(r, 'authorRole') ?? '',
          syncState: SyncState.synced,
          isArchived: SyncEngine.rBool(r, 'isArchived'),
          createdAt: SyncEngine.rDate(r, 'createdAt', Date.now())
        };
        SyncEngine.applyEntry(r, e);
        e.remoteId = SyncEngine.rStr(r, 'id');
        await AppDatabase.shared.insertEntry(e);
      }
    });
  }

  private static applyEntry(r: Record<string, Object>, e: Entry): void {
    e.title = SyncEngine.rStr(r, 'title');
    e.note = SyncEngine.rStr(r, 'note');
    e.firstPersonNote = SyncEngine.rStr(r, 'firstPersonNote');
    e.happenedAt = SyncEngine.rDate(r, 'happenedAt', e.happenedAt);
    e.locationName = SyncEngine.rStr(r, 'locationName');
    e.latitude = SyncEngine.rNum(r, 'latitude');
    e.longitude = SyncEngine.rNum(r, 'longitude');
    e.authorRole = SyncEngine.rStr(r, 'authorRole') ?? e.authorRole;
    e.moodRaw = SyncEngine.rStr(r, 'mood');
    e.isArchived = SyncEngine.rBool(r, 'isArchived');
    const edited = SyncEngine.rStr(r, 'editedAt');
    e.editedAt = edited !== undefined ? Date.parse(edited) : undefined;
  }

  private static entryToFields(e: Entry): relationalStore.ValuesBucket {
    const f: relationalStore.ValuesBucket = {
      happenedAt: e.happenedAt, authorRole: e.authorRole,
      isArchived: e.isArchived ? 1 : 0, syncState: e.syncState
    };
    f['title'] = e.title ?? '';
    f['note'] = e.note ?? '';
    f['firstPersonNote'] = e.firstPersonNote ?? '';
    f['locationName'] = e.locationName ?? '';
    f['moodRaw'] = e.moodRaw ?? '';
    if (e.remoteId !== undefined) f['remoteId'] = e.remoteId;
    if (e.latitude !== undefined) f['latitude'] = e.latitude;
    if (e.longitude !== undefined) f['longitude'] = e.longitude;
    if (e.editedAt !== undefined) f['editedAt'] = e.editedAt;
    return f;
  }

  private async findEntry(localId: string): Promise<Entry | null> {
    const all = await AppDatabase.shared.fetchEntries(true);
    for (const e of all) { if (e.id === localId) return e; }
    return null;
  }

  // —— Media 合并（对照 iOS mergeRemoteMedia：需对应 Entry 存在）——
  private async pullMedia(): Promise<void> {
    await this.pullCollection('media', async (r: Record<string, Object>): Promise<boolean | void> => {
      const mediaId = SyncEngine.recordLocalId(r);
      const entryLocalId = SyncEngine.rStr(r, 'entryLocalId');
      if (mediaId === undefined || entryLocalId === undefined) return;
      if (await this.isPendingDeletion('media', SyncEngine.rStr(r, 'id'))) return true;
      const existingList = await AppDatabase.shared.fetchMediaForEntry(entryLocalId);
      for (const ex of existingList) {
        if (ex.id === mediaId) {
          if (ex.syncState === SyncState.synced || this.serverMirrorMode) {
            SyncEngine.applyMedia(r, ex);
            await this.updateMediaFields(ex.id, SyncEngine.mediaToFields(ex));
          } else {
            return false;
          }
          return;
        }
      }
      const entry = await this.findEntry(entryLocalId);
      if (!entry) return false;
      const m: Media = {
        id: mediaId,
        entryId: entryLocalId,
        typeRaw: SyncEngine.rStr(r, 'mediaType') ?? MediaType.photo,
        uploadProgress: 0,
        syncState: SyncState.synced,
        aiTags: SyncEngine.rStrArray(r, 'aiTags'),
        createdAt: SyncEngine.rDate(r, 'createdAt', Date.now())
      };
      SyncEngine.applyMedia(r, m);
      await AppDatabase.shared.insertMedia(m);
    });
  }

  private static applyMedia(r: Record<string, Object>, m: Media): void {
    m.remoteId = SyncEngine.rStr(r, 'id');
    m.typeRaw = SyncEngine.rStr(r, 'mediaType') ?? m.typeRaw;
    m.remoteURL = SyncEngine.remoteFileURL(r, 'media', 'file');
    m.durationSeconds = SyncEngine.rNum(r, 'durationSeconds');
    m.width = SyncEngine.rNum(r, 'width');
    m.height = SyncEngine.rNum(r, 'height');
    m.aiTags = SyncEngine.rStrArray(r, 'aiTags');
  }

  private static mediaToFields(m: Media): relationalStore.ValuesBucket {
    const f: relationalStore.ValuesBucket = { typeRaw: m.typeRaw, aiTags: JSON.stringify(m.aiTags) };
    if (m.remoteId !== undefined) f['remoteId'] = m.remoteId;
    if (m.remoteURL !== undefined) f['remoteURL'] = m.remoteURL;
    if (m.durationSeconds !== undefined) f['durationSeconds'] = m.durationSeconds;
    if (m.width !== undefined) f['width'] = m.width;
    if (m.height !== undefined) f['height'] = m.height;
    return f;
  }

  // —— Milestone 合并 ——
  private async pullMilestones(): Promise<void> {
    await this.pullCollection('milestones', async (r: Record<string, Object>): Promise<boolean | void> => {
      const localId = SyncEngine.recordLocalId(r);
      if (localId === undefined) return;
      if (SyncEngine.isRemotePresetPlaceholder(r)) return;
      if (await this.isPendingDeletion('milestones', SyncEngine.rStr(r, 'id'))) return true;
      const title = (SyncEngine.rStr(r, 'title') ?? '').trim();
      if (title.length === 0) return;
      const list = await AppDatabase.shared.fetchMilestones();
      const ex = list.find((x) => x.id === localId);
      if (ex) {
        if (ex.syncState !== SyncState.synced && !this.serverMirrorMode) return false;
        SyncEngine.applyMilestone(r, ex); ex.remoteId = SyncEngine.rStr(r, 'id');
        await AppDatabase.shared.upsertMilestone(ex);
      } else {
        const byTitle = list.find((x: Milestone): boolean => x.title.trim() === title);
        if (byTitle !== undefined && (byTitle.syncState === SyncState.synced || this.serverMirrorMode)) {
          SyncEngine.applyMilestone(r, byTitle);
          byTitle.remoteId = SyncEngine.rStr(r, 'id');
          await AppDatabase.shared.upsertMilestone(byTitle);
        } else if (byTitle !== undefined) {
          return false;
        } else {
          const m: Milestone = {
            id: localId,
            title: title,
            category: SyncEngine.rStr(r, 'category') ?? '',
            emoji: SyncEngine.rStr(r, 'emoji') ?? '',
            isCustom: SyncEngine.rBool(r, 'isCustom'),
            ceremonyPlayed: false,
            syncState: SyncState.synced,
            createdAt: SyncEngine.rDate(r, 'createdAt', Date.now())
          };
          SyncEngine.applyMilestone(r, m);
          m.remoteId = SyncEngine.rStr(r, 'id');
          await AppDatabase.shared.upsertMilestone(m);
        }
      }
    });
    await AppDatabase.shared.normalizeMilestonesByTitle();
  }

  private static applyMilestone(r: Record<string, Object>, m: Milestone): void {
    m.title = SyncEngine.rStr(r, 'title') ?? m.title;
    m.category = SyncEngine.rStr(r, 'category') ?? m.category;
    m.emoji = SyncEngine.rStr(r, 'emoji') ?? m.emoji;
    m.detail = SyncEngine.rStr(r, 'detail');
    const hp = SyncEngine.rStr(r, 'happenedAt');
    m.happenedAt = hp !== undefined ? Date.parse(hp) : undefined;
    m.ageDescription = SyncEngine.rStr(r, 'ageDescription');
    m.isCustom = SyncEngine.rBool(r, 'isCustom');
  }

  private static isPresetTitle(title: string): boolean {
    return MILESTONE_PRESETS.some((tpl): boolean => tpl.title === title);
  }

  private static isLocalPresetPlaceholder(m: Milestone): boolean {
    return SyncEngine.isPresetTitle(m.title)
      && !m.isCustom
      && (m.happenedAt === undefined || m.happenedAt === null)
      && (m.detail === undefined || m.detail.trim().length === 0);
  }

  private static isRemotePresetPlaceholder(r: Record<string, Object>): boolean {
    const title = SyncEngine.rStr(r, 'title') ?? '';
    return SyncEngine.isPresetTitle(title)
      && !SyncEngine.rBool(r, 'isCustom')
      && SyncEngine.rStr(r, 'happenedAt') === undefined
      && SyncEngine.rStr(r, 'detail') === undefined;
  }

  // —— FirstTime 合并 ——
  private async pullFirstTimes(): Promise<void> {
    await this.pullCollection('firsttimes', async (r: Record<string, Object>): Promise<boolean | void> => {
      const localId = SyncEngine.recordLocalId(r);
      if (localId === undefined) return;
      if (await this.isPendingDeletion('firsttimes', SyncEngine.rStr(r, 'id'))) return true;
      const list = await AppDatabase.shared.fetchFirstTimes();
      const ex = list.find((x) => x.id === localId);
      if (ex) {
        if (ex.syncState !== SyncState.synced && !this.serverMirrorMode) return false;
        SyncEngine.applyFirstTime(r, ex); ex.remoteId = SyncEngine.rStr(r, 'id');
        await AppDatabase.shared.insertFirstTime(ex);
      } else {
        const f: FirstTime = {
          id: localId,
          what: SyncEngine.rStr(r, 'what') ?? '',
          detectedByAI: SyncEngine.rBool(r, 'detectedByAI'),
          confirmedByParent: SyncEngine.rBool(r, 'confirmedByParent'),
          ceremonyPlayed: false,
          happenedAt: SyncEngine.rDate(r, 'happenedAt', Date.now()),
          entryId: SyncEngine.rStr(r, 'entryLocalId'),
          syncState: SyncState.synced,
          createdAt: SyncEngine.rDate(r, 'createdAt', Date.now())
        };
        await AppDatabase.shared.insertFirstTime(f);
      }
    });
  }

  private static applyFirstTime(r: Record<string, Object>, f: FirstTime): void {
    f.what = SyncEngine.rStr(r, 'what') ?? f.what;
    f.happenedAt = SyncEngine.rDate(r, 'happenedAt', f.happenedAt);
    f.detectedByAI = SyncEngine.rBool(r, 'detectedByAI');
    f.confirmedByParent = SyncEngine.rBool(r, 'confirmedByParent');
  }

  // —— FamilyMember 合并 ——
  private async pullFamilyMembers(): Promise<void> {
    await this.pullCollection('members', async (r: Record<string, Object>): Promise<boolean | void> => {
      const localId = SyncEngine.recordLocalId(r);
      if (localId === undefined) return;
      if (await this.isPendingDeletion('members', SyncEngine.rStr(r, 'id'))) return true;
      const list = await AppDatabase.shared.fetchMembers();
      const ex = list.find((x) => x.id === localId);
      if (ex) {
        if (ex.syncState !== SyncState.synced && !this.serverMirrorMode) return false;
        SyncEngine.applyMember(r, ex); ex.remoteId = SyncEngine.rStr(r, 'id');
        await AppDatabase.shared.upsertMember(ex);
      } else {
        const m: FamilyMember = {
          id: localId,
          name: SyncEngine.rStr(r, 'name') ?? '',
          relation: SyncEngine.rStr(r, 'relation') ?? '',
          avatarEmoji: SyncEngine.rStr(r, 'avatarEmoji') ?? '',
          themeColorHex: SyncEngine.rStr(r, 'themeColorHex') ?? '',
          isPrimary: SyncEngine.rBool(r, 'isPrimary'),
          syncState: SyncState.synced,
          createdAt: SyncEngine.rDate(r, 'createdAt', Date.now())
        };
        m.remoteId = SyncEngine.rStr(r, 'id');
        await AppDatabase.shared.upsertMember(m);
      }
    });
  }

  private static applyMember(r: Record<string, Object>, m: FamilyMember): void {
    m.name = SyncEngine.rStr(r, 'name') ?? m.name;
    m.relation = SyncEngine.rStr(r, 'relation') ?? m.relation;
    m.avatarEmoji = SyncEngine.rStr(r, 'avatarEmoji') ?? m.avatarEmoji;
    m.themeColorHex = SyncEngine.rStr(r, 'themeColorHex') ?? m.themeColorHex;
    m.isPrimary = SyncEngine.rBool(r, 'isPrimary');
  }

  // —— ChildProfile 合并（远端头像变更：更新 URL 并清本地名，下轮 downloadMissingFiles 重新落地）——
  private async pullChildProfile(): Promise<void> {
    await this.pullCollection('childprofile', async (r: Record<string, Object>): Promise<boolean | void> => {
      const localId = SyncEngine.recordLocalId(r);
      if (localId === undefined) return;
      if (await this.isPendingDeletion('childprofile', SyncEngine.rStr(r, 'id'))) return true;
      const ex = await AppDatabase.shared.fetchChildProfile();
      if (ex && ex.id === localId) {
        if (ex.syncState !== SyncState.synced && !this.serverMirrorMode) return false;
        SyncEngine.applyChildProfile(r, ex); ex.remoteId = SyncEngine.rStr(r, 'id');
        await AppDatabase.shared.upsertChildProfile(ex);
      } else if (!ex) {
        const p: ChildProfile = {
          id: localId,
          name: SyncEngine.rStr(r, 'name') ?? '',
          birthday: SyncEngine.rDate(r, 'birthday', Date.now()),
          syncState: SyncState.synced,
          createdAt: SyncEngine.rDate(r, 'createdAt', Date.now())
        };
        SyncEngine.applyChildProfile(r, p); p.remoteId = SyncEngine.rStr(r, 'id');
        await AppDatabase.shared.upsertChildProfile(p);
      }
    });
  }

  private static applyChildProfile(r: Record<string, Object>, p: ChildProfile): void {
    p.name = SyncEngine.rStr(r, 'name') ?? p.name;
    p.birthday = SyncEngine.rDate(r, 'birthday', p.birthday);
    p.gender = SyncEngine.rStr(r, 'gender');
    p.bloodType = SyncEngine.rStr(r, 'bloodType');
    p.birthPlace = SyncEngine.rStr(r, 'birthPlace');
    const remote = SyncEngine.remoteFileURL(r, 'childprofile', 'avatar', 'avatarRemoteURL');
    if (remote !== undefined && remote !== p.avatarRemoteURL) {
      p.avatarRemoteURL = remote;
      p.avatarMediaFileName = undefined; // 触发下轮重新下载落地
    }
  }

  // —— HealthRecord 合并 ——
  private async pullHealthRecords(): Promise<void> {
    await this.pullCollection('healthrecords', async (r: Record<string, Object>): Promise<boolean | void> => {
      const localId = SyncEngine.recordLocalId(r);
      if (localId === undefined) return;
      if (await this.isPendingDeletion('healthrecords', SyncEngine.rStr(r, 'id'))) return true;
      const list = await AppDatabase.shared.fetchHealth();
      const ex = list.find((x) => x.id === localId);
      if (ex) {
        if (ex.syncState !== SyncState.synced && !this.serverMirrorMode) return false;
        SyncEngine.applyHealth(r, ex); ex.remoteId = SyncEngine.rStr(r, 'id');
        await this.replaceHealth(ex);
        await this.backfillGrowthFromHealth(ex);
        await this.backfillVaccineFromHealth(ex);
      } else {
        const h: HealthRecord = {
          id: localId,
          kind: SyncEngine.rStr(r, 'kind') ?? 'meal',
          title: SyncEngine.rStr(r, 'title') ?? '',
          recordedAt: SyncEngine.rDate(r, 'recordedAt', Date.now()),
          tags: SyncEngine.rStrArray(r, 'tags'),
          syncState: SyncState.synced,
          createdAt: SyncEngine.rDate(r, 'createdAt', Date.now())
        };
        SyncEngine.applyHealth(r, h); h.remoteId = SyncEngine.rStr(r, 'id');
        await AppDatabase.shared.insertHealth(h);
        await this.backfillGrowthFromHealth(h);
        await this.backfillVaccineFromHealth(h);
      }
    });
  }

  private static applyHealth(r: Record<string, Object>, h: HealthRecord): void {
    h.kind = SyncEngine.rStr(r, 'kind') ?? h.kind;
    h.title = SyncEngine.rStr(r, 'title') ?? h.title;
    h.detail = SyncEngine.rStr(r, 'detail');
    h.recordedAt = SyncEngine.rDate(r, 'recordedAt', h.recordedAt);
    h.amountText = SyncEngine.rStr(r, 'amountText');
    h.reaction = SyncEngine.rStr(r, 'reaction');
    h.amountValue = SyncEngine.rNum(r, 'amountValue');
    h.amountUnit = SyncEngine.rStr(r, 'amountUnit');
    const sa = SyncEngine.rStr(r, 'startAt'); h.startAt = sa !== undefined ? Date.parse(sa) : undefined;
    const ea = SyncEngine.rStr(r, 'endAt'); h.endAt = ea !== undefined ? Date.parse(ea) : undefined;
    h.severity = SyncEngine.rStr(r, 'severity');
    h.temperatureCelsius = SyncEngine.rNum(r, 'temperatureCelsius');
    h.tags = SyncEngine.rStrArray(r, 'tags');
  }

  private async replaceHealth(h: HealthRecord): Promise<void> {
    await AppDatabase.shared.deleteHealth(h.id);
    await AppDatabase.shared.insertHealth(h);
  }

  private static vaccineHealthFallbackBody(v: VaccineRecord): Record<string, Object> {
    const parts: string[] = [];
    if (v.doseLabel !== undefined && v.doseLabel.trim().length > 0) parts.push(v.doseLabel.trim());
    if (v.hospital !== undefined && v.hospital.trim().length > 0) parts.push(`医院：${v.hospital.trim()}`);
    if (v.injectionSite !== undefined && v.injectionSite.trim().length > 0) parts.push(`部位：${v.injectionSite.trim()}`);
    if (v.reaction !== undefined && v.reaction.trim().length > 0) parts.push(`反应：${v.reaction.trim()}`);
    if (v.note !== undefined && v.note.trim().length > 0) parts.push(v.note.trim());
    const body: Record<string, Object> = {
      'kind': 'checkup',
      'title': `疫苗：${v.vaccineName}`,
      'recordedAt': new Date(v.injectedAt).toISOString(),
      'tags': ['疫苗', v.vaccineName],
      'createdAt': new Date(v.createdAt).toISOString()
    };
    if (parts.length > 0) body['detail'] = parts.join(' · ');
    if (v.doseLabel !== undefined) body['amountText'] = v.doseLabel;
    if (v.reaction !== undefined) body['reaction'] = v.reaction;
    return body;
  }

  private static growthHealthFallbackBody(g: GrowthMeasurement): Record<string, Object> {
    const parts: string[] = [];
    if (g.heightCm !== undefined) parts.push(`身高 ${SyncEngine.metricText(g.heightCm)}cm`);
    if (g.weightKg !== undefined) parts.push(`体重 ${SyncEngine.metricText(g.weightKg)}kg`);
    if (g.headCircumferenceCm !== undefined) parts.push(`头围 ${SyncEngine.metricText(g.headCircumferenceCm)}cm`);
    const body: Record<string, Object> = {
      'kind': 'checkup',
      'title': '身高体重',
      'recordedAt': new Date(g.measuredAt).toISOString(),
      'amountText': parts.length > 0 ? parts.join(' · ') : '身高体重',
      'tags': ['身高体重', '成长数据'],
      'createdAt': new Date(g.createdAt).toISOString()
    };
    if (g.note !== undefined) body['detail'] = g.note;
    return body;
  }

  private static metricText(value: number): string {
    const rounded = Math.round(value * 10) / 10;
    return Math.round(rounded) === rounded ? `${Math.round(rounded)}` : `${rounded}`;
  }

  private async backfillGrowthFromHealth(h: HealthRecord): Promise<void> {
    const values = SyncEngine.growthValuesFromHealth(h);
    if (values.heightCm === undefined && values.weightKg === undefined && values.headCircumferenceCm === undefined) return;
    const existing = await AppDatabase.shared.fetchGrowth();
    if (existing.some((g: GrowthMeasurement): boolean => g.id === h.id)) return;
    if (SyncEngine.growthCovered(values, h.recordedAt, existing)) return;
    const noteParts: string[] = [];
    if (h.title.trim().length > 0) noteParts.push(h.title.trim());
    if (h.detail !== undefined && h.detail.trim().length > 0) noteParts.push(h.detail.trim());
    const g: GrowthMeasurement = {
      id: h.id,
      measuredAt: h.recordedAt,
      heightCm: values.heightCm,
      weightKg: values.weightKg,
      headCircumferenceCm: values.headCircumferenceCm,
      note: noteParts.length > 0 ? noteParts.join(' · ') : undefined,
      source: 'health-fallback',
      syncState: SyncState.synced,
      createdAt: h.createdAt,
      updatedAt: Date.now()
    };
    await AppDatabase.shared.insertGrowth(g);
  }

  private async backfillVaccineFromHealth(h: HealthRecord): Promise<void> {
    const isVaccine = h.title.indexOf('疫苗') >= 0 || h.tags.indexOf('疫苗') >= 0;
    if (!isVaccine) return;
    const existing = await AppDatabase.shared.fetchVaccines();
    if (existing.some((v: VaccineRecord): boolean => v.id === h.id)) return;
    const vaccine: VaccineRecord = {
      id: h.id,
      vaccineName: SyncEngine.vaccineNameFromHealth(h),
      doseLabel: h.amountText,
      injectedAt: h.recordedAt,
      reaction: h.reaction,
      note: h.detail,
      source: 'health-fallback',
      syncState: SyncState.synced,
      createdAt: h.createdAt,
      updatedAt: Date.now()
    };
    await AppDatabase.shared.insertVaccine(vaccine);
  }

  private static vaccineNameFromHealth(h: HealthRecord): string {
    const cleaned = h.title.replace(/^疫苗[：:\s]*/, '').trim();
    if (cleaned.length > 0 && cleaned !== '疫苗') return cleaned;
    const tag = h.tags.find((item: string): boolean => item !== '疫苗');
    return tag ?? '疫苗记录';
  }

  private static growthValuesFromHealth(h: HealthRecord): GrowthMetricValues {
    const text = `${h.title} ${h.amountText ?? ''} ${h.detail ?? ''} ${h.tags.join(' ')}`;
    let height = SyncEngine.extractMetric(text, ['身高', '身长'], ['cm', 'CM', '厘米', '公分'], 30, 150);
    let weight = SyncEngine.extractMetric(text, ['体重'], ['kg', 'KG', '公斤', '千克'], 1, 60);
    if (weight === undefined) {
      const jin = SyncEngine.extractMetric(text, ['体重'], ['斤'], 2, 120);
      if (jin !== undefined) weight = jin / 2;
    }
    let head = SyncEngine.extractMetric(text, ['头围'], ['cm', 'CM', '厘米', '公分'], 20, 70);
    if (h.kind === 'checkup') {
      if (height === undefined) height = SyncEngine.extractUnitValue(text, ['cm', 'CM', '厘米', '公分'], 30, 150);
      if (weight === undefined) weight = SyncEngine.extractUnitValue(text, ['kg', 'KG', '公斤', '千克'], 1, 60);
      if (head === undefined && text.indexOf('头围') >= 0) head = SyncEngine.extractUnitValue(text, ['cm', 'CM', '厘米', '公分'], 20, 70);
    }
    return { heightCm: height, weightKg: weight, headCircumferenceCm: head };
  }

  private static extractMetric(text: string, keywords: string[], units: string[], min: number, max: number): number | undefined {
    const keywordPattern = keywords.join('|');
    const unitPattern = units.join('|');
    const patterns: RegExp[] = [
      new RegExp(`(?:${keywordPattern})\\s*(?:约|大约)?\\s*[:：=]?\\s*(\\d+(?:\\.\\d+)?)\\s*(?:${unitPattern})?`, 'i'),
      new RegExp(`(\\d+(?:\\.\\d+)?)\\s*(?:${unitPattern})\\s*(?:${keywordPattern})`, 'i')
    ];
    for (const pattern of patterns) {
      const match = pattern.exec(text);
      if (!match || match.length < 2) continue;
      const value = Number(match[1]);
      if (!Number.isNaN(value) && value >= min && value <= max) return value;
    }
    return undefined;
  }

  private static extractUnitValue(text: string, units: string[], min: number, max: number): number | undefined {
    const pattern = new RegExp(`(\\d+(?:\\.\\d+)?)\\s*(?:${units.join('|')})`, 'i');
    const match = pattern.exec(text);
    if (!match || match.length < 2) return undefined;
    const value = Number(match[1]);
    return !Number.isNaN(value) && value >= min && value <= max ? value : undefined;
  }

  private static growthCovered(values: GrowthMetricValues, measuredAt: number, list: GrowthMeasurement[]): boolean {
    for (const g of list) {
      if (!SyncEngine.sameDay(g.measuredAt, measuredAt)) continue;
      if (values.heightCm !== undefined && !SyncEngine.closeMetric(g.heightCm, values.heightCm)) continue;
      if (values.weightKg !== undefined && !SyncEngine.closeMetric(g.weightKg, values.weightKg)) continue;
      if (values.headCircumferenceCm !== undefined && !SyncEngine.closeMetric(g.headCircumferenceCm, values.headCircumferenceCm)) continue;
      return true;
    }
    return false;
  }

  private static closeMetric(actual: number | undefined, expected: number): boolean {
    return actual !== undefined && Math.abs(actual - expected) < 0.05;
  }

  private static sameDay(a: number, b: number): boolean {
    const da = new Date(a);
    const db = new Date(b);
    return da.getFullYear() === db.getFullYear()
      && da.getMonth() === db.getMonth()
      && da.getDate() === db.getDate();
  }

  // —— VaccineRecord 合并（防复活：在删除队列内的 remoteId 不重新合并，对照 iOS mergeRemoteVaccine）——
  private async pullVaccineRecords(): Promise<void> {
    await this.pullCollection('vaccinerecords', async (r: Record<string, Object>): Promise<boolean | void> => {
      const localId = SyncEngine.recordLocalId(r);
      if (localId === undefined) return;
      const remoteId = SyncEngine.rStr(r, 'id');
      if (await this.isPendingDeletion('vaccinerecords', remoteId)) return true; // 防复活
      const list = await AppDatabase.shared.fetchVaccines();
      const ex = list.find((x) => x.id === localId);
      if (ex) {
        if (ex.syncState !== SyncState.synced && !this.serverMirrorMode) return false;
        SyncEngine.applyVaccine(r, ex); ex.remoteId = remoteId;
        await AppDatabase.shared.insertVaccine(ex);
      } else {
        const v: VaccineRecord = {
          id: localId,
          vaccineName: SyncEngine.rStr(r, 'vaccineName') ?? '',
          injectedAt: SyncEngine.rDate(r, 'injectedAt', Date.now()),
          source: SyncEngine.rStr(r, 'sourceRaw') ?? SyncEngine.rStr(r, 'source') ?? 'manual',
          syncState: SyncState.synced,
          createdAt: SyncEngine.rDate(r, 'createdAt', Date.now()),
          updatedAt: Date.now()
        };
        SyncEngine.applyVaccine(r, v); v.remoteId = remoteId;
        await AppDatabase.shared.insertVaccine(v);
      }
    });
  }

  private static applyVaccine(r: Record<string, Object>, v: VaccineRecord): void {
    v.doseId = SyncEngine.rStr(r, 'doseId');
    v.vaccineName = SyncEngine.rStr(r, 'vaccineName') ?? v.vaccineName;
    v.doseLabel = SyncEngine.rStr(r, 'doseLabel');
    v.injectedAt = SyncEngine.rDate(r, 'injectedAt', v.injectedAt);
    v.hospital = SyncEngine.rStr(r, 'hospital');
    v.injectionSite = SyncEngine.rStr(r, 'injectionSite');
    v.reaction = SyncEngine.rStr(r, 'reaction');
    v.note = SyncEngine.rStr(r, 'note');
    v.source = SyncEngine.rStr(r, 'sourceRaw') ?? SyncEngine.rStr(r, 'source') ?? v.source;
    v.updatedAt = Date.now();
  }

  // —— GrowthMeasurement 合并 ——
  private async pullGrowthMeasurements(): Promise<void> {
    await this.pullCollection('growthmeasurements', async (r: Record<string, Object>): Promise<boolean | void> => {
      const localId = SyncEngine.recordLocalId(r);
      if (localId === undefined) return;
      if (await this.isPendingDeletion('growthmeasurements', SyncEngine.rStr(r, 'id'))) return true;
      const list = await AppDatabase.shared.fetchGrowth();
      const ex = list.find((x) => x.id === localId);
      if (ex) {
        if (ex.syncState !== SyncState.synced && !this.serverMirrorMode) return false;
        SyncEngine.applyGrowth(r, ex); ex.remoteId = SyncEngine.rStr(r, 'id');
        await AppDatabase.shared.insertGrowth(ex);
      } else {
        const g: GrowthMeasurement = {
          id: localId,
          measuredAt: SyncEngine.rDate(r, 'measuredAt', Date.now()),
          source: SyncEngine.rStr(r, 'sourceRaw') ?? SyncEngine.rStr(r, 'source') ?? 'manual',
          syncState: SyncState.synced,
          createdAt: SyncEngine.rDate(r, 'createdAt', Date.now()),
          updatedAt: Date.now()
        };
        SyncEngine.applyGrowth(r, g); g.remoteId = SyncEngine.rStr(r, 'id');
        await AppDatabase.shared.insertGrowth(g);
      }
    });
  }

  private static applyGrowth(r: Record<string, Object>, g: GrowthMeasurement): void {
    g.measuredAt = SyncEngine.rDate(r, 'measuredAt', g.measuredAt);
    g.heightCm = SyncEngine.rNum(r, 'heightCm');
    g.weightKg = SyncEngine.rNum(r, 'weightKg');
    g.headCircumferenceCm = SyncEngine.rNum(r, 'headCircumferenceCm');
    g.note = SyncEngine.rStr(r, 'note');
    g.source = SyncEngine.rStr(r, 'sourceRaw') ?? SyncEngine.rStr(r, 'source') ?? g.source;
    g.updatedAt = Date.now();
  }

  // —— Comment 合并（需对应 Entry 存在）——
  private async pullComments(): Promise<void> {
    await this.pullCollection('comments', async (r: Record<string, Object>): Promise<boolean | void> => {
      const localId = SyncEngine.recordLocalId(r);
      const entryLocalId = SyncEngine.rStr(r, 'entryLocalId');
      if (localId === undefined || entryLocalId === undefined) return;
      if (await this.isPendingDeletion('comments', SyncEngine.rStr(r, 'id'))) return true;
      const list = await AppDatabase.shared.fetchCommentsForEntry(entryLocalId);
      const ex = list.find((x) => x.id === localId);
      if (ex) {
        if (ex.syncState !== SyncState.synced && !this.serverMirrorMode) return false;
        SyncEngine.applyComment(r, ex); ex.remoteId = SyncEngine.rStr(r, 'id');
        await this.replaceComment(ex);
      } else {
        const entry = await this.findEntry(entryLocalId);
        if (!entry) return false;
        const c: Comment = {
          id: localId,
          entryId: entryLocalId,
          authorRole: SyncEngine.rStr(r, 'authorRole') ?? '',
          voiceDuration: SyncEngine.rNum(r, 'voiceDuration') ?? 0,
          voiceWaveform: SyncEngine.rNumArray(r, 'voiceWaveform'),
          syncState: SyncState.synced,
          createdAt: SyncEngine.rDate(r, 'createdAt', Date.now())
        };
        SyncEngine.applyComment(r, c); c.remoteId = SyncEngine.rStr(r, 'id');
        await AppDatabase.shared.insertComment(c);
      }
    });
  }

  private static applyComment(r: Record<string, Object>, c: Comment): void {
    c.authorRole = SyncEngine.rStr(r, 'authorRole') ?? c.authorRole;
    c.text = SyncEngine.rStr(r, 'text');
    c.remoteURL = SyncEngine.remoteFileURL(r, 'comments', 'voiceFile');
    c.voiceDuration = SyncEngine.rNum(r, 'voiceDuration') ?? c.voiceDuration;
    c.voiceWaveform = SyncEngine.rNumArray(r, 'voiceWaveform');
  }

  private async replaceComment(c: Comment): Promise<void> {
    const store = AppDatabase.shared.raw;
    if (store) { try { await store.executeSql(`DELETE FROM comment WHERE id = '${c.id}'`); } catch (e) {} }
    await AppDatabase.shared.insertComment(c);
  }

  // —— VoiceNote 合并（需对应 Entry 存在）——
  private async pullVoiceNotes(): Promise<void> {
    await this.pullCollection('voicenotes', async (r: Record<string, Object>): Promise<boolean | void> => {
      const localId = SyncEngine.recordLocalId(r);
      const entryLocalId = SyncEngine.rStr(r, 'entryLocalId');
      if (localId === undefined || entryLocalId === undefined) return;
      if (await this.isPendingDeletion('voicenotes', SyncEngine.rStr(r, 'id'))) return true;
      const list = await AppDatabase.shared.fetchVoiceForEntry(entryLocalId);
      const ex = list.find((x) => x.id === localId);
      if (ex) {
        if (ex.syncState !== SyncState.synced && !this.serverMirrorMode) return false;
        SyncEngine.applyVoiceNote(r, ex); ex.remoteId = SyncEngine.rStr(r, 'id');
        await this.replaceVoiceNote(ex);
      } else {
        const entry = await this.findEntry(entryLocalId);
        if (!entry) return false;
        const n: VoiceNote = {
          id: localId,
          entryId: entryLocalId,
          durationSeconds: SyncEngine.rNum(r, 'durationSeconds') ?? 0,
          authorRole: SyncEngine.rStr(r, 'authorRole') ?? '',
          waveformSamples: SyncEngine.rNumArray(r, 'waveform'),
          syncState: SyncState.synced,
          createdAt: SyncEngine.rDate(r, 'createdAt', Date.now())
        };
        SyncEngine.applyVoiceNote(r, n); n.remoteId = SyncEngine.rStr(r, 'id');
        await AppDatabase.shared.insertVoiceNote(n);
      }
    });
  }

  private static applyVoiceNote(r: Record<string, Object>, n: VoiceNote): void {
    n.authorRole = SyncEngine.rStr(r, 'authorRole') ?? n.authorRole;
    n.remoteURL = SyncEngine.remoteFileURL(r, 'voicenotes', 'file');
    n.durationSeconds = SyncEngine.rNum(r, 'durationSeconds') ?? n.durationSeconds;
    n.transcript = SyncEngine.rStr(r, 'transcript');
    n.waveformSamples = SyncEngine.rNumArray(r, 'waveform');
  }

  // —— TimeCapsule 合并（拉回后确保本地有加密 blob，对照 iOS ensureLocalCapsuleBlob）——
  private async pullTimeCapsules(): Promise<void> {
    await this.pullCollection('timecapsules', async (r: Record<string, Object>): Promise<boolean | void> => {
      const localId = SyncEngine.recordLocalId(r);
      if (localId === undefined) return;
      if (await this.isPendingDeletion('timecapsules', SyncEngine.rStr(r, 'id'))) return true;
      const list = await AppDatabase.shared.fetchCapsules();
      const ex = list.find((x) => x.id === localId);
      if (ex) {
        if (ex.syncState !== SyncState.synced && !this.serverMirrorMode) return false;
        SyncEngine.applyCapsule(r, ex); ex.remoteId = SyncEngine.rStr(r, 'id');
        await this.replaceCapsule(ex);
        await this.ensureLocalCapsuleBlob(ex, r);
      } else {
        const c: TimeCapsule = {
          id: localId,
          title: SyncEngine.rStr(r, 'title') ?? '',
          fromRole: SyncEngine.rStr(r, 'fromRole') ?? '',
          unlockAt: SyncEngine.rDate(r, 'unlockAt', Date.now()),
          isLocked: SyncEngine.rBool(r, 'isLocked'),
          syncState: SyncState.synced,
          createdAt: SyncEngine.rDate(r, 'createdAt', Date.now())
        };
        SyncEngine.applyCapsule(r, c); c.remoteId = SyncEngine.rStr(r, 'id');
        await AppDatabase.shared.insertCapsule(c);
        await this.ensureLocalCapsuleBlob(c, r);
      }
    });
  }

  // 不覆盖 unlockAt：封存后不可变，密钥派生依赖它（对照 iOS apply(TimeCapsuleDTO)）。
  private static applyCapsule(r: Record<string, Object>, c: TimeCapsule): void {
    c.title = SyncEngine.rStr(r, 'title') ?? c.title;
    c.fromRole = SyncEngine.rStr(r, 'fromRole') ?? c.fromRole;
    c.isLocked = SyncEngine.rBool(r, 'isLocked');
    c.coverEmoji = SyncEngine.rStr(r, 'coverEmoji');
    c.createdAt = SyncEngine.rDate(r, 'createdAt', c.createdAt);
  }

  private async ensureLocalCapsuleBlob(c: TimeCapsule, r: Record<string, Object>): Promise<void> {
    if (c.encryptedBlobFileName !== undefined && MediaStore.shared.exists(c.encryptedBlobFileName)) return;
    const remoteURL = SyncEngine.remoteFileURL(r, 'timecapsules', 'encryptedBlob', 'encryptedBlobRemoteURL');
    if (remoteURL === undefined) return;
    try {
      const fileName = `${c.id}.capsule`;
      const destPath = MediaStore.shared.fullPath(fileName);
      await APIClient.shared.downloadFile(remoteURL, destPath);
      c.encryptedBlobFileName = fileName;
      await this.replaceCapsule(c);
    } catch (e) {
      hilog.warn(DOMAIN, 'Bubu', '下载时间胶囊载荷失败，下轮重试');
    }
  }

  // MARK: - 下载：把远端媒体/语音落到本地（对照 iOS downloadMissingFiles）
  // 每轮最多下载若干个缺失文件，避免长时间占用；下一轮继续。

  private async downloadMissingFiles(downloadAll: boolean = false): Promise<void> {
    // Media：缺本地文件但有 remoteURL。自动同步小批量；手动全量拉取时补完整机文件。
    const allMedia = await AppDatabase.shared.fetchAllMedia();
    let mediaCount = 0;
    let mediaDone = 0;
    let mediaFailed = 0;
    const mediaLimit = downloadAll ? 1000000 : 8;
    for (const m of allMedia) {
      if (mediaCount >= mediaLimit) break;
      const existingName = m.localFileName;
      if (existingName !== undefined && existingName.length > 0 && MediaStore.shared.exists(existingName)) continue;
      if (m.remoteURL === undefined) continue;
      mediaCount += 1;
      try {
        const ext = SyncEngine.extFromURL(m.remoteURL) ?? (m.typeRaw === MediaType.video ? 'mp4' : 'jpg');
        const fileName = (existingName !== undefined && existingName.length > 0) ? existingName : `${m.id}.${ext}`;
        const destPath = MediaStore.shared.fullPath(fileName);
        await APIClient.shared.downloadFile(m.remoteURL, destPath);
        await this.updateMediaFields(m.id, { localFileName: fileName });
        mediaDone += 1;
      } catch (e) {
        // 缺失文件下载失败属瞬时可自愈，下轮继续补拉（对照 iOS softFailure）。
        mediaFailed += 1;
        hilog.warn(DOMAIN, 'Bubu', `下载媒体失败 ${m.id}: ${SyncEngine.errorText(e)}`);
      }
    }

    // VoiceNote：缺本地文件但有 remoteURL，每轮最多 10 个（遍历各 Entry 下的语音）。
    const entries = await AppDatabase.shared.fetchEntries(true);
    let voiceCount = 0;
    let voiceDone = 0;
    let voiceFailed = 0;
    const voiceLimit = downloadAll ? 1000000 : 10;
    for (const e of entries) {
      if (voiceCount >= voiceLimit) break;
      const notes = await AppDatabase.shared.fetchVoiceForEntry(e.id);
      for (const n of notes) {
        if (voiceCount >= voiceLimit) break;
        const existingName = n.localFileName;
        if (existingName !== undefined && existingName.length > 0 && MediaStore.shared.exists(existingName)) continue;
        if (n.remoteURL === undefined) continue;
        voiceCount += 1;
        try {
          const fileName = (existingName !== undefined && existingName.length > 0) ? existingName : `voice_${n.id}.m4a`;
          const destPath = MediaStore.shared.fullPath(fileName);
          await APIClient.shared.downloadFile(n.remoteURL, destPath);
          n.localFileName = fileName;
          await this.replaceVoiceNote(n);
          voiceDone += 1;
        } catch (err) {
          voiceFailed += 1;
          hilog.warn(DOMAIN, 'Bubu', `下载记录语音失败 ${n.id}: ${SyncEngine.errorText(err)}`);
        }
      }
    }

    // Comment 语音补充：缺本地文件但有 remoteURL。
    let commentVoiceCount = 0;
    let commentVoiceDone = 0;
    let commentVoiceFailed = 0;
    const commentVoiceLimit = downloadAll ? 1000000 : 10;
    for (const e of entries) {
      if (commentVoiceCount >= commentVoiceLimit) break;
      const comments = await AppDatabase.shared.fetchCommentsForEntry(e.id);
      for (const c of comments) {
        if (commentVoiceCount >= commentVoiceLimit) break;
        const existingName = c.voiceFileName;
        if (existingName !== undefined && existingName.length > 0 && MediaStore.shared.exists(existingName)) continue;
        if (c.remoteURL === undefined) continue;
        commentVoiceCount += 1;
        try {
          const fileName = (existingName !== undefined && existingName.length > 0) ? existingName : `comment_${c.id}.m4a`;
          const destPath = MediaStore.shared.fullPath(fileName);
          await APIClient.shared.downloadFile(c.remoteURL, destPath);
          c.voiceFileName = fileName;
          await this.replaceComment(c);
          commentVoiceDone += 1;
        } catch (err) {
          commentVoiceFailed += 1;
          hilog.warn(DOMAIN, 'Bubu', `下载评论语音失败 ${c.id}: ${SyncEngine.errorText(err)}`);
        }
      }
    }

    // ChildProfile 头像：缺本地文件但有 avatarRemoteURL。
    const profile = await AppDatabase.shared.fetchChildProfile();
    if (profile && profile.avatarRemoteURL !== undefined) {
      const existingAvatar = profile.avatarMediaFileName;
      const hasLocalAvatar = existingAvatar !== undefined
        && existingAvatar.length > 0
        && MediaStore.shared.exists(existingAvatar);
      if (hasLocalAvatar) return;
      try {
        const ext = SyncEngine.extFromURL(profile.avatarRemoteURL) ?? 'jpg';
        const fileName = (existingAvatar !== undefined && existingAvatar.length > 0) ? existingAvatar : `avatar_${profile.id}.${ext}`;
        const destPath = MediaStore.shared.fullPath(fileName);
        await APIClient.shared.downloadFile(profile.avatarRemoteURL, destPath);
        profile.avatarMediaFileName = fileName;
        await AppDatabase.shared.upsertChildProfile(profile);
      } catch (e) {
        hilog.warn(DOMAIN, 'Bubu', `下载头像失败 ${profile.id}: ${SyncEngine.errorText(e)}`);
      }
    }
    hilog.info(DOMAIN, 'Bubu',
      `补下载统计 media=${mediaDone}/${mediaCount} failed=${mediaFailed}, voice=${voiceDone}/${voiceCount} failed=${voiceFailed}, commentVoice=${commentVoiceDone}/${commentVoiceCount} failed=${commentVoiceFailed}`);
  }

  private static extFromURL(url: string): string | undefined {
    const q = url.split('?')[0];
    const seg = q.split('/').pop() ?? '';
    const dot = seg.lastIndexOf('.');
    if (dot < 0 || dot === seg.length - 1) return undefined;
    return seg.substring(dot + 1);
  }

  // MARK: - 游标存取（Preferences，对照 iOS UserDefaults cursor）

  private async getCursor(collection: string): Promise<string | undefined> {
    await this.ensureCursorStore();
    if (!this.cursorStore) return undefined;
    const v = await this.cursorStore.get(`cursor_${collection}`, '') as string;
    return v.length > 0 ? v : undefined;
  }

  private async setCursor(collection: string, iso: string): Promise<void> {
    await this.ensureCursorStore();
    if (!this.cursorStore) return;
    await this.cursorStore.put(`cursor_${collection}`, iso);
    await this.cursorStore.flush();
  }

  private async resetCursors(): Promise<void> {
    await this.ensureCursorStore();
    if (!this.cursorStore) return;
    const collections: string[] = [
      'entries', 'media', 'milestones', 'firsttimes', 'members', 'childprofile',
      'healthrecords', 'vaccinerecords', 'growthmeasurements', 'comments',
      'voicenotes', 'timecapsules'
    ];
    for (const c of collections) {
      await this.cursorStore.put(`cursor_${c}`, '');
    }
    await this.cursorStore.flush();
  }

  private async ensureCursorStore(): Promise<void> {
    if (!this.cursorStore && this.appContext) {
      this.cursorStore = await preferences.getPreferences(this.appContext, 'bubu_sync_cursor');
    }
  }

  private async isServerBaselineReady(): Promise<boolean> {
    await this.ensureCursorStore();
    if (!this.cursorStore) return false;
    const saved = await this.cursorStore.get('server_baseline_identity_v4', '') as string;
    return saved === this.serverBaselineIdentity();
  }

  private async markServerBaselineReady(): Promise<void> {
    await this.ensureCursorStore();
    if (!this.cursorStore) return;
    await this.cursorStore.put('server_baseline_identity_v4', this.serverBaselineIdentity());
    await this.cursorStore.flush();
  }

  private async shouldProtectIosBaselineFromServerPull(): Promise<boolean> {
    await this.ensureCursorStore();
    if (!this.cursorStore) return false;
    const protect = await this.cursorStore.get('ios_baseline_protect_from_server_pull', false) as boolean;
    if (!protect) return false;

    const entries = await AppDatabase.shared.fetchEntries(false);
    const milestones = await AppDatabase.shared.fetchMilestones();
    const growth = await AppDatabase.shared.fetchGrowth();
    const achieved = milestones.filter((item: Milestone): boolean => item.happenedAt !== undefined).length;
    const hasGrowth = growth.some((item: GrowthMeasurement): boolean => {
      return item.heightCm !== undefined && item.weightKg !== undefined;
    });

    return entries.length >= 2
      && milestones.length >= 118
      && milestones.length <= 160
      && achieved >= 18
      && hasGrowth;
  }

  private serverBaselineIdentity(): string {
    const cfg = ServerConfig.shared;
    const base = cfg.baseURLString.trim().replace(/\/+$/, '');
    const account = cfg.accountEmail.trim().toLowerCase();
    return `${base}|${account}`;
  }
}
