import { relationalStore } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Entry, ChildProfile, Media, Milestone, TimeCapsule, HealthRecord } from '../models/Models';
import { SyncState } from '../models/Enums';

const DOMAIN = 0x0000;

// MARK: - 本地数据库（RelationalStore）
// 对应 iOS SwiftData ModelContainer：离线优先的唯一真相源。
// 单例；EntryAbility.onWindowStageCreate 调 initialize 完成建表。
export class AppDatabase {
  static readonly shared = new AppDatabase();
  private store: relationalStore.RdbStore | null = null;

  private constructor() {}

  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.store) return;
    const config: relationalStore.StoreConfig = {
      name: 'BubuTimeMachine.db',
      securityLevel: relationalStore.SecurityLevel.S2
    };
    this.store = await relationalStore.getRdbStore(context, config);
    await this.createTables();
    hilog.info(DOMAIN, 'Bubu', '数据库初始化完成');
  }

  private async createTables(): Promise<void> {
    const s = this.store!;
    // Entry
    await s.executeSql(`CREATE TABLE IF NOT EXISTS entry (
      id TEXT PRIMARY KEY, remoteId TEXT, title TEXT, note TEXT, firstPersonNote TEXT,
      happenedAt INTEGER NOT NULL, locationName TEXT, latitude REAL, longitude REAL,
      authorRole TEXT NOT NULL, moodRaw TEXT, syncState TEXT NOT NULL,
      isArchived INTEGER NOT NULL DEFAULT 0, editedAt INTEGER, createdAt INTEGER NOT NULL)`);
    // Media
    await s.executeSql(`CREATE TABLE IF NOT EXISTS media (
      id TEXT PRIMARY KEY, remoteId TEXT, entryId TEXT NOT NULL, typeRaw TEXT NOT NULL,
      localFileName TEXT, remoteURL TEXT, thumbnailFileName TEXT, aiTags TEXT, createdAt INTEGER NOT NULL)`);
    // ChildProfile
    await s.executeSql(`CREATE TABLE IF NOT EXISTS child_profile (
      id TEXT PRIMARY KEY, remoteId TEXT, name TEXT NOT NULL, birthday INTEGER NOT NULL,
      gender TEXT, bloodType TEXT, birthPlace TEXT, avatarMediaFileName TEXT,
      avatarRemoteURL TEXT, heroBackgroundFileName TEXT, syncState TEXT NOT NULL, createdAt INTEGER NOT NULL)`);
    // Milestone
    await s.executeSql(`CREATE TABLE IF NOT EXISTS milestone (
      id TEXT PRIMARY KEY, remoteId TEXT, title TEXT NOT NULL, category TEXT NOT NULL,
      emoji TEXT NOT NULL, detail TEXT, happenedAt INTEGER, ageDescription TEXT,
      isCustom INTEGER NOT NULL DEFAULT 0, ceremonyPlayed INTEGER NOT NULL DEFAULT 0,
      syncState TEXT NOT NULL, createdAt INTEGER NOT NULL, entryId TEXT)`);
    // TimeCapsule
    await s.executeSql(`CREATE TABLE IF NOT EXISTS time_capsule (
      id TEXT PRIMARY KEY, remoteId TEXT, title TEXT NOT NULL, fromRole TEXT NOT NULL,
      unlockAt INTEGER NOT NULL, isLocked INTEGER NOT NULL DEFAULT 1, encryptedBlobFileName TEXT,
      coverEmoji TEXT, syncState TEXT NOT NULL, createdAt INTEGER NOT NULL)`);
    // HealthRecord
    await s.executeSql(`CREATE TABLE IF NOT EXISTS health_record (
      id TEXT PRIMARY KEY, remoteId TEXT, kind TEXT NOT NULL, title TEXT NOT NULL, detail TEXT,
      recordedAt INTEGER NOT NULL, amountText TEXT, reaction TEXT, amountValue REAL, amountUnit TEXT,
      startAt INTEGER, endAt INTEGER, severity TEXT, temperatureCelsius REAL, tags TEXT,
      syncState TEXT NOT NULL, createdAt INTEGER NOT NULL)`);
    // FeedEvent
    await s.executeSql(`CREATE TABLE IF NOT EXISTS feed_event (
      id TEXT PRIMARY KEY, kind TEXT NOT NULL, actorRole TEXT NOT NULL, summary TEXT NOT NULL,
      targetLocalId TEXT, happenedAt INTEGER NOT NULL)`);
  }

  // —— Entry ——
  async insertEntry(e: Entry): Promise<void> {
    const v: relationalStore.ValuesBucket = {
      id: e.id, remoteId: e.remoteId ?? null, title: e.title ?? null, note: e.note ?? null,
      firstPersonNote: e.firstPersonNote ?? null, happenedAt: e.happenedAt,
      locationName: e.locationName ?? null, latitude: e.latitude ?? null, longitude: e.longitude ?? null,
      authorRole: e.authorRole, moodRaw: e.moodRaw ?? null, syncState: e.syncState,
      isArchived: e.isArchived ? 1 : 0, editedAt: e.editedAt ?? null, createdAt: e.createdAt
    };
    await this.store!.insert('entry', v);
  }

  async fetchEntries(includeArchived: boolean = false): Promise<Entry[]> {
    const pred = new relationalStore.RdbPredicates('entry');
    if (!includeArchived) pred.equalTo('isArchived', 0);
    pred.orderByDesc('happenedAt');
    const rs = await this.store!.query(pred);
    const out: Entry[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        remoteId: AppDatabase.optStr(rs, 'remoteId'),
        title: AppDatabase.optStr(rs, 'title'),
        note: AppDatabase.optStr(rs, 'note'),
        firstPersonNote: AppDatabase.optStr(rs, 'firstPersonNote'),
        happenedAt: rs.getLong(rs.getColumnIndex('happenedAt')),
        locationName: AppDatabase.optStr(rs, 'locationName'),
        latitude: AppDatabase.optNum(rs, 'latitude'),
        longitude: AppDatabase.optNum(rs, 'longitude'),
        authorRole: rs.getString(rs.getColumnIndex('authorRole')),
        moodRaw: AppDatabase.optStr(rs, 'moodRaw'),
        syncState: rs.getString(rs.getColumnIndex('syncState')) as SyncState,
        isArchived: rs.getLong(rs.getColumnIndex('isArchived')) === 1,
        editedAt: AppDatabase.optNum(rs, 'editedAt'),
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      });
    }
    rs.close();
    return out;
  }

  // —— ChildProfile ——
  async upsertChildProfile(p: ChildProfile): Promise<void> {
    const v: relationalStore.ValuesBucket = {
      id: p.id, remoteId: p.remoteId ?? null, name: p.name, birthday: p.birthday,
      gender: p.gender ?? null, bloodType: p.bloodType ?? null, birthPlace: p.birthPlace ?? null,
      avatarMediaFileName: p.avatarMediaFileName ?? null, avatarRemoteURL: p.avatarRemoteURL ?? null,
      heroBackgroundFileName: p.heroBackgroundFileName ?? null, syncState: p.syncState, createdAt: p.createdAt
    };
    await this.store!.insert('child_profile', v, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async fetchChildProfile(): Promise<ChildProfile | null> {
    const pred = new relationalStore.RdbPredicates('child_profile');
    const rs = await this.store!.query(pred);
    let p: ChildProfile | null = null;
    if (rs.goToNextRow()) {
      p = {
        id: rs.getString(rs.getColumnIndex('id')),
        remoteId: AppDatabase.optStr(rs, 'remoteId'),
        name: rs.getString(rs.getColumnIndex('name')),
        birthday: rs.getLong(rs.getColumnIndex('birthday')),
        gender: AppDatabase.optStr(rs, 'gender'),
        bloodType: AppDatabase.optStr(rs, 'bloodType'),
        birthPlace: AppDatabase.optStr(rs, 'birthPlace'),
        avatarMediaFileName: AppDatabase.optStr(rs, 'avatarMediaFileName'),
        avatarRemoteURL: AppDatabase.optStr(rs, 'avatarRemoteURL'),
        heroBackgroundFileName: AppDatabase.optStr(rs, 'heroBackgroundFileName'),
        syncState: rs.getString(rs.getColumnIndex('syncState')) as SyncState,
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      };
    }
    rs.close();
    return p;
  }

  get raw(): relationalStore.RdbStore | null {
    return this.store;
  }

  // —— 取可空列工具 ——
  private static optStr(rs: relationalStore.ResultSet, col: string): string | undefined {
    const i = rs.getColumnIndex(col);
    return rs.isColumnNull(i) ? undefined : rs.getString(i);
  }

  private static optNum(rs: relationalStore.ResultSet, col: string): number | undefined {
    const i = rs.getColumnIndex(col);
    return rs.isColumnNull(i) ? undefined : rs.getDouble(i);
  }
}
