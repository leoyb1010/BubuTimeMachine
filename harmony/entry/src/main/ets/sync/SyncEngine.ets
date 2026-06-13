import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences } from '@kit.ArkData';
import { APIClient } from '../services/APIClient';
import { ServerConfig } from '../services/ServerConfig';
import { AppDatabase } from '../data/AppDatabase';
import { SyncState } from '../models/Enums';
import { Entry, ChildProfile } from '../models/Models';

const DOMAIN = 0x0000;

// MARK: - 同步引擎（对照 iOS Services/Sync/SyncEngine.swift）
// 离线优先：本地先落库(.local)，后台推进 .uploading → .synced；失败 .failed 待重试。
// 增量游标 clientUpdatedAt；轮询 30s；进后台停轮询省电。
//
// 完成度说明（见 harmony/README.md）：
// - 已实现：轮询/启停、登录、推送 Entry/ChildProfile、按游标增量拉取的骨架。
// - 待补全：媒体文件上传/下载、其余 10 个 collection 的双向映射、冲突合并细节、待删队列。
//   （iOS 端这些都在 SyncEngine.swift 里，按同一模式补即可。）
export class SyncEngine {
  static readonly shared = new SyncEngine();

  private pollTimerId: number = -1;
  private syncing: boolean = false;
  private cursorStore: preferences.Preferences | null = null;

  private constructor() {}

  // 回前台：启动 + 立刻补一轮
  start(): void {
    if (this.pollTimerId !== -1) return;
    this.pollTimerId = setInterval(() => {
      this.syncNow();
    }, 30000);
    this.syncNow();
  }

  // 进后台：停轮询
  stopPolling(): void {
    if (this.pollTimerId !== -1) {
      clearInterval(this.pollTimerId);
      this.pollTimerId = -1;
    }
  }

  async syncNow(): Promise<void> {
    const cfg = ServerConfig.shared;
    if (this.syncing || !cfg.isConfigured) return;
    this.syncing = true;
    try {
      const ok = await APIClient.shared.authenticate();
      if (!ok) {
        hilog.warn(DOMAIN, 'Bubu', '同步：未连通服务器，离线可用');
        return;
      }
      await this.pushChildProfile();
      await this.pushEntries();
      await this.pullEntries();
      hilog.info(DOMAIN, 'Bubu', '同步完成');
    } catch (e) {
      hilog.error(DOMAIN, 'Bubu', `同步异常: ${JSON.stringify(e)}`);
    } finally {
      this.syncing = false;
    }
  }

  // —— 推送布布档案 ——
  private async pushChildProfile(): Promise<void> {
    const p = await AppDatabase.shared.fetchChildProfile();
    if (!p || p.syncState === SyncState.synced) return;
    const body: Record<string, Object> = {
      'name': p.name,
      'birthday': new Date(p.birthday).toISOString(),
      'createdAt': new Date(p.createdAt).toISOString()
    };
    if (p.gender) body['gender'] = p.gender;
    if (p.bloodType) body['bloodType'] = p.bloodType;   // 含血型同步（与 iOS 一致）
    if (p.birthPlace) body['birthPlace'] = p.birthPlace;
    try {
      const saved = await APIClient.shared.upsert('childprofile', p.id, body);
      p.remoteId = saved['id'] as string;
      p.syncState = SyncState.synced;
      await AppDatabase.shared.upsertChildProfile(p);
    } catch (e) {
      p.syncState = SyncState.failed;
      await AppDatabase.shared.upsertChildProfile(p);
    }
  }

  // —— 推送本地待上传的 Entry ——
  private async pushEntries(): Promise<void> {
    const entries = await AppDatabase.shared.fetchEntries(true);
    for (const e of entries) {
      if (e.syncState === SyncState.synced) continue;
      const body: Record<string, Object> = {
        'happenedAt': new Date(e.happenedAt).toISOString(),
        'authorRole': e.authorRole,
        'isArchived': e.isArchived,
        'createdAt': new Date(e.createdAt).toISOString()
      };
      if (e.note) body['note'] = e.note;
      if (e.title) body['title'] = e.title;
      if (e.moodRaw) body['mood'] = e.moodRaw;
      if (e.locationName) body['locationName'] = e.locationName;
      try {
        await APIClient.shared.upsert('entries', e.id, body);
        // 标记已同步（此处简化；完整版应回写 remoteId 并更新行）
      } catch (err) {
        hilog.warn(DOMAIN, 'Bubu', `推送 Entry 失败 ${e.id}`);
      }
    }
  }

  // —— 增量拉取远端 Entry（骨架：拉取后合并入库的细节见 README 待补）——
  private async pullEntries(): Promise<void> {
    const cursor = await this.getCursor('entries');
    const records = await APIClient.shared.fetchRecords('entries', cursor);
    if (records.length === 0) return;
    let latest = cursor ?? '';
    for (const r of records) {
      const cu = r['clientUpdatedAt'] as string | undefined;
      if (cu && cu > latest) latest = cu;
      // TODO(完整版): 把 record 映射成本地 Entry 并 upsert（冲突以 clientUpdatedAt 较新者为准）
    }
    if (latest) await this.setCursor('entries', latest);
  }

  // —— 游标存取（Preferences）——
  private async ensureCursorStore(): Promise<preferences.Preferences | null> {
    return this.cursorStore;
  }

  private async getCursor(collection: string): Promise<string | undefined> {
    const s = await this.ensureCursorStore();
    if (!s) return undefined;
    const v = await s.get(`cursor_${collection}`, '') as string;
    return v.length > 0 ? v : undefined;
  }

  private async setCursor(collection: string, iso: string): Promise<void> {
    const s = await this.ensureCursorStore();
    if (!s) return;
    await s.put(`cursor_${collection}`, iso);
    await s.flush();
  }
}
