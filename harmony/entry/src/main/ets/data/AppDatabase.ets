import { relationalStore } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Entry, ChildProfile, Media, Milestone, TimeCapsule, HealthRecord, VoiceNote, FamilyMember, GrowthMeasurement, VaccineRecord, Comment, VoiceMemo, FirstTime, GrowthMovie, PendingDeletion, FeedEvent } from '../models/Models';
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
    // Media（对照 iOS Media：含时长/尺寸/上传进度/syncState）
    await s.executeSql(`CREATE TABLE IF NOT EXISTS media (
      id TEXT PRIMARY KEY, remoteId TEXT, entryId TEXT NOT NULL, typeRaw TEXT NOT NULL,
      localFileName TEXT, remoteURL TEXT, thumbnailFileName TEXT,
      durationSeconds REAL, width INTEGER, height INTEGER, uploadProgress REAL NOT NULL DEFAULT 0,
      syncState TEXT NOT NULL DEFAULT 'local', aiTags TEXT, createdAt INTEGER NOT NULL)`);
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
      id TEXT PRIMARY KEY, remoteId TEXT, title TEXT NOT NULL, letterText TEXT, fromRole TEXT NOT NULL,
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
    // VoiceNote（对照 iOS VoiceNote：含 transcript / syncState）
    await s.executeSql(`CREATE TABLE IF NOT EXISTS voice_note (
      id TEXT PRIMARY KEY, remoteId TEXT, entryId TEXT NOT NULL, localFileName TEXT, remoteURL TEXT,
      durationSeconds INTEGER NOT NULL, transcript TEXT, authorRole TEXT NOT NULL,
      waveformSamples TEXT, syncState TEXT NOT NULL DEFAULT 'local', createdAt INTEGER NOT NULL)`);
    // FamilyMember
    await s.executeSql(`CREATE TABLE IF NOT EXISTS family_member (
      id TEXT PRIMARY KEY, remoteId TEXT, name TEXT NOT NULL, relation TEXT NOT NULL,
      avatarEmoji TEXT NOT NULL, themeColorHex TEXT NOT NULL, isPrimary INTEGER NOT NULL DEFAULT 0,
      syncState TEXT NOT NULL, createdAt INTEGER NOT NULL)`);
    // GrowthMeasurement（对照 iOS：含 note/source/updatedAt）
    await s.executeSql(`CREATE TABLE IF NOT EXISTS growth_measurement (
      id TEXT PRIMARY KEY, remoteId TEXT, measuredAt INTEGER NOT NULL, heightCm REAL, weightKg REAL,
      headCircumferenceCm REAL, note TEXT, source TEXT NOT NULL DEFAULT 'manual',
      syncState TEXT NOT NULL, createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL DEFAULT 0)`);
    // VaccineRecord（对照 iOS：vaccineName/doseId/injectedAt/hospital/injectionSite/source/updatedAt）
    await s.executeSql(`CREATE TABLE IF NOT EXISTS vaccine_record (
      id TEXT PRIMARY KEY, remoteId TEXT, doseId TEXT, vaccineName TEXT NOT NULL, doseLabel TEXT,
      injectedAt INTEGER NOT NULL DEFAULT 0, hospital TEXT, injectionSite TEXT, reaction TEXT, note TEXT,
      source TEXT NOT NULL DEFAULT 'manual', syncState TEXT NOT NULL, createdAt INTEGER NOT NULL,
      updatedAt INTEGER NOT NULL DEFAULT 0)`);
    // Comment（家人合奏：文字 / 语音补充）
    await s.executeSql(`CREATE TABLE IF NOT EXISTS comment (
      id TEXT PRIMARY KEY, remoteId TEXT, entryId TEXT NOT NULL, authorRole TEXT NOT NULL,
      text TEXT, voiceFileName TEXT, remoteURL TEXT, voiceDuration REAL NOT NULL DEFAULT 0,
      voiceWaveform TEXT, syncState TEXT NOT NULL DEFAULT 'local', createdAt INTEGER NOT NULL)`);
    // VoiceMemo（成长之声：按岁横切归档）
    await s.executeSql(`CREATE TABLE IF NOT EXISTS voice_memo (
      id TEXT PRIMARY KEY, remoteId TEXT, kindRaw TEXT NOT NULL, localFileName TEXT, remoteURL TEXT,
      transcript TEXT, ageYears INTEGER, recordedAt INTEGER NOT NULL, durationSeconds REAL,
      syncState TEXT NOT NULL DEFAULT 'local', createdAt INTEGER NOT NULL)`);
    // FirstTime（人生第一次）
    await s.executeSql(`CREATE TABLE IF NOT EXISTS first_time (
      id TEXT PRIMARY KEY, remoteId TEXT, what TEXT NOT NULL, detectedByAI INTEGER NOT NULL DEFAULT 0,
      confirmedByParent INTEGER NOT NULL DEFAULT 0, ceremonyPlayed INTEGER NOT NULL DEFAULT 0,
      happenedAt INTEGER NOT NULL, entryId TEXT, syncState TEXT NOT NULL DEFAULT 'local',
      createdAt INTEGER NOT NULL)`);
    // GrowthMovie（年度成长电影）
    await s.executeSql(`CREATE TABLE IF NOT EXISTS growth_movie (
      id TEXT PRIMARY KEY, remoteId TEXT, year INTEGER NOT NULL, remoteURL TEXT,
      status TEXT NOT NULL DEFAULT 'pending', narrationScript TEXT, createdAt INTEGER NOT NULL)`);
    // PendingDeletion（待同步删除队列）
    await s.executeSql(`CREATE TABLE IF NOT EXISTS pending_deletion (
      id TEXT PRIMARY KEY, collection TEXT NOT NULL, remoteId TEXT NOT NULL, createdAt INTEGER NOT NULL)`);
    await this.addColumnIfMissing('time_capsule', 'letterText', 'TEXT');
  }

  private async addColumnIfMissing(table: string, column: string, type: string): Promise<void> {
    try {
      await this.store!.executeSql(`ALTER TABLE ${table} ADD COLUMN ${column} ${type}`);
    } catch (e) {
      // Column already exists on fresh installs or after a previous migration.
    }
  }

  // —— GrowthMeasurement ——
  async insertGrowth(g: GrowthMeasurement): Promise<void> {
    const v: relationalStore.ValuesBucket = {
      id: g.id, remoteId: g.remoteId ?? null, measuredAt: g.measuredAt,
      heightCm: g.heightCm ?? null, weightKg: g.weightKg ?? null,
      headCircumferenceCm: g.headCircumferenceCm ?? null, note: g.note ?? null, source: g.source,
      syncState: g.syncState, createdAt: g.createdAt, updatedAt: g.updatedAt
    };
    await this.store!.insert('growth_measurement', v, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async fetchGrowth(): Promise<GrowthMeasurement[]> {
    const pred = new relationalStore.RdbPredicates('growth_measurement');
    pred.orderByAsc('measuredAt');
    const rs = await this.store!.query(pred);
    const out: GrowthMeasurement[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        remoteId: AppDatabase.optStr(rs, 'remoteId'),
        measuredAt: rs.getLong(rs.getColumnIndex('measuredAt')),
        heightCm: AppDatabase.optNum(rs, 'heightCm'),
        weightKg: AppDatabase.optNum(rs, 'weightKg'),
        headCircumferenceCm: AppDatabase.optNum(rs, 'headCircumferenceCm'),
        note: AppDatabase.optStr(rs, 'note'),
        source: rs.getString(rs.getColumnIndex('source')),
        syncState: rs.getString(rs.getColumnIndex('syncState')) as SyncState,
        createdAt: rs.getLong(rs.getColumnIndex('createdAt')),
        updatedAt: rs.getLong(rs.getColumnIndex('updatedAt'))
      });
    }
    rs.close();
    return out;
  }

  // —— VaccineRecord ——
  async insertVaccine(v: VaccineRecord): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      id: v.id, remoteId: v.remoteId ?? null, doseId: v.doseId ?? null, vaccineName: v.vaccineName,
      doseLabel: v.doseLabel ?? null, injectedAt: v.injectedAt, hospital: v.hospital ?? null,
      injectionSite: v.injectionSite ?? null, reaction: v.reaction ?? null, note: v.note ?? null,
      source: v.source, syncState: v.syncState, createdAt: v.createdAt, updatedAt: v.updatedAt
    };
    await this.store!.insert('vaccine_record', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async fetchVaccines(): Promise<VaccineRecord[]> {
    const pred = new relationalStore.RdbPredicates('vaccine_record');
    pred.orderByAsc('injectedAt');
    const rs = await this.store!.query(pred);
    const out: VaccineRecord[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        remoteId: AppDatabase.optStr(rs, 'remoteId'),
        doseId: AppDatabase.optStr(rs, 'doseId'),
        vaccineName: rs.getString(rs.getColumnIndex('vaccineName')),
        doseLabel: AppDatabase.optStr(rs, 'doseLabel'),
        injectedAt: rs.getLong(rs.getColumnIndex('injectedAt')),
        hospital: AppDatabase.optStr(rs, 'hospital'),
        injectionSite: AppDatabase.optStr(rs, 'injectionSite'),
        reaction: AppDatabase.optStr(rs, 'reaction'),
        note: AppDatabase.optStr(rs, 'note'),
        source: rs.getString(rs.getColumnIndex('source')),
        syncState: rs.getString(rs.getColumnIndex('syncState')) as SyncState,
        createdAt: rs.getLong(rs.getColumnIndex('createdAt')),
        updatedAt: rs.getLong(rs.getColumnIndex('updatedAt'))
      });
    }
    rs.close();
    return out;
  }

  async deleteVaccine(id: string): Promise<void> {
    const pred = new relationalStore.RdbPredicates('vaccine_record');
    pred.equalTo('id', id);
    await this.store!.delete(pred);
  }

  // —— VoiceNote ——
  async insertVoiceNote(v: VoiceNote): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      id: v.id, remoteId: v.remoteId ?? null, entryId: v.entryId, localFileName: v.localFileName ?? null,
      remoteURL: v.remoteURL ?? null, durationSeconds: v.durationSeconds, transcript: v.transcript ?? null,
      authorRole: v.authorRole, waveformSamples: JSON.stringify(v.waveformSamples),
      syncState: v.syncState, createdAt: v.createdAt
    };
    await this.store!.insert('voice_note', bucket);
  }

  async fetchVoiceForEntry(entryId: string): Promise<VoiceNote[]> {
    const pred = new relationalStore.RdbPredicates('voice_note');
    pred.equalTo('entryId', entryId);
    const rs = await this.store!.query(pred);
    const out: VoiceNote[] = [];
    while (rs.goToNextRow()) {
      const wf = AppDatabase.optStr(rs, 'waveformSamples');
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        remoteId: AppDatabase.optStr(rs, 'remoteId'),
        entryId: rs.getString(rs.getColumnIndex('entryId')),
        localFileName: AppDatabase.optStr(rs, 'localFileName'),
        remoteURL: AppDatabase.optStr(rs, 'remoteURL'),
        durationSeconds: rs.getLong(rs.getColumnIndex('durationSeconds')),
        transcript: AppDatabase.optStr(rs, 'transcript'),
        authorRole: rs.getString(rs.getColumnIndex('authorRole')),
        waveformSamples: wf ? JSON.parse(wf) as number[] : [],
        syncState: rs.getString(rs.getColumnIndex('syncState')) as SyncState,
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      });
    }
    rs.close();
    return out;
  }

  // —— FamilyMember ——
  async upsertMember(m: FamilyMember): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      id: m.id, remoteId: m.remoteId ?? null, name: m.name, relation: m.relation,
      avatarEmoji: m.avatarEmoji, themeColorHex: m.themeColorHex, isPrimary: m.isPrimary ? 1 : 0,
      syncState: m.syncState, createdAt: m.createdAt
    };
    await this.store!.insert('family_member', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async fetchMembers(): Promise<FamilyMember[]> {
    const pred = new relationalStore.RdbPredicates('family_member');
    pred.orderByAsc('createdAt');
    const rs = await this.store!.query(pred);
    const out: FamilyMember[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        remoteId: AppDatabase.optStr(rs, 'remoteId'),
        name: rs.getString(rs.getColumnIndex('name')),
        relation: rs.getString(rs.getColumnIndex('relation')),
        avatarEmoji: rs.getString(rs.getColumnIndex('avatarEmoji')),
        themeColorHex: rs.getString(rs.getColumnIndex('themeColorHex')),
        isPrimary: rs.getLong(rs.getColumnIndex('isPrimary')) === 1,
        syncState: rs.getString(rs.getColumnIndex('syncState')) as SyncState,
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      });
    }
    rs.close();
    return out;
  }

  async deleteMember(id: string): Promise<void> {
    const pred = new relationalStore.RdbPredicates('family_member');
    pred.equalTo('id', id);
    await this.store!.delete(pred);
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

  // —— Media ——
  async insertMedia(m: Media): Promise<void> {
    const v: relationalStore.ValuesBucket = {
      id: m.id, remoteId: m.remoteId ?? null, entryId: m.entryId, typeRaw: m.typeRaw,
      localFileName: m.localFileName ?? null, remoteURL: m.remoteURL ?? null,
      thumbnailFileName: m.thumbnailFileName ?? null, durationSeconds: m.durationSeconds ?? null,
      width: m.width ?? null, height: m.height ?? null, uploadProgress: m.uploadProgress,
      syncState: m.syncState, aiTags: JSON.stringify(m.aiTags), createdAt: m.createdAt
    };
    await this.store!.insert('media', v);
  }

  private static rowToMedia(rs: relationalStore.ResultSet): Media {
    const tagsStr = AppDatabase.optStr(rs, 'aiTags');
    return {
      id: rs.getString(rs.getColumnIndex('id')),
      remoteId: AppDatabase.optStr(rs, 'remoteId'),
      entryId: rs.getString(rs.getColumnIndex('entryId')),
      typeRaw: rs.getString(rs.getColumnIndex('typeRaw')),
      localFileName: AppDatabase.optStr(rs, 'localFileName'),
      remoteURL: AppDatabase.optStr(rs, 'remoteURL'),
      thumbnailFileName: AppDatabase.optStr(rs, 'thumbnailFileName'),
      durationSeconds: AppDatabase.optNum(rs, 'durationSeconds'),
      width: AppDatabase.optNum(rs, 'width'),
      height: AppDatabase.optNum(rs, 'height'),
      uploadProgress: AppDatabase.optNum(rs, 'uploadProgress') ?? 0,
      syncState: (AppDatabase.optStr(rs, 'syncState') ?? SyncState.local) as SyncState,
      aiTags: tagsStr ? JSON.parse(tagsStr) as string[] : [],
      createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
    };
  }

  async fetchMediaForEntry(entryId: string): Promise<Media[]> {
    const pred = new relationalStore.RdbPredicates('media');
    pred.equalTo('entryId', entryId);
    const rs = await this.store!.query(pred);
    const out: Media[] = [];
    while (rs.goToNextRow()) out.push(AppDatabase.rowToMedia(rs));
    rs.close();
    return out;
  }

  // 取所有照片（相册用）
  async fetchAllPhotos(): Promise<Media[]> {
    const pred = new relationalStore.RdbPredicates('media');
    pred.equalTo('typeRaw', 'photo');
    pred.orderByDesc('createdAt');
    const rs = await this.store!.query(pred);
    const out: Media[] = [];
    while (rs.goToNextRow()) out.push(AppDatabase.rowToMedia(rs));
    rs.close();
    return out;
  }

  async fetchAllMedia(): Promise<Media[]> {
    const pred = new relationalStore.RdbPredicates('media');
    pred.orderByDesc('createdAt');
    const rs = await this.store!.query(pred);
    const out: Media[] = [];
    while (rs.goToNextRow()) out.push(AppDatabase.rowToMedia(rs));
    rs.close();
    return out;
  }

  // 软删除（归档）一条记录
  async archiveEntry(id: string): Promise<void> {
    const pred = new relationalStore.RdbPredicates('entry');
    pred.equalTo('id', id);
    await this.store!.update({ isArchived: 1, syncState: SyncState.local }, pred);
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

  // —— HealthRecord ——
  async insertHealth(h: HealthRecord): Promise<void> {
    const v: relationalStore.ValuesBucket = {
      id: h.id, remoteId: h.remoteId ?? null, kind: h.kind, title: h.title, detail: h.detail ?? null,
      recordedAt: h.recordedAt, amountText: h.amountText ?? null, reaction: h.reaction ?? null,
      amountValue: h.amountValue ?? null, amountUnit: h.amountUnit ?? null,
      startAt: h.startAt ?? null, endAt: h.endAt ?? null, severity: h.severity ?? null,
      temperatureCelsius: h.temperatureCelsius ?? null, tags: JSON.stringify(h.tags),
      syncState: h.syncState, createdAt: h.createdAt
    };
    await this.store!.insert('health_record', v);
  }

  async fetchHealth(): Promise<HealthRecord[]> {
    const pred = new relationalStore.RdbPredicates('health_record');
    pred.orderByDesc('recordedAt');
    const rs = await this.store!.query(pred);
    const out: HealthRecord[] = [];
    while (rs.goToNextRow()) {
      const tagsStr = AppDatabase.optStr(rs, 'tags');
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        remoteId: AppDatabase.optStr(rs, 'remoteId'),
        kind: rs.getString(rs.getColumnIndex('kind')),
        title: rs.getString(rs.getColumnIndex('title')),
        detail: AppDatabase.optStr(rs, 'detail'),
        recordedAt: rs.getLong(rs.getColumnIndex('recordedAt')),
        amountText: AppDatabase.optStr(rs, 'amountText'),
        reaction: AppDatabase.optStr(rs, 'reaction'),
        amountValue: AppDatabase.optNum(rs, 'amountValue'),
        amountUnit: AppDatabase.optStr(rs, 'amountUnit'),
        startAt: AppDatabase.optNum(rs, 'startAt'),
        endAt: AppDatabase.optNum(rs, 'endAt'),
        severity: AppDatabase.optStr(rs, 'severity'),
        temperatureCelsius: AppDatabase.optNum(rs, 'temperatureCelsius'),
        tags: tagsStr ? JSON.parse(tagsStr) as string[] : [],
        syncState: rs.getString(rs.getColumnIndex('syncState')) as SyncState,
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      });
    }
    rs.close();
    return out;
  }

  // —— Milestone ——
  async upsertMilestone(m: Milestone): Promise<void> {
    const v: relationalStore.ValuesBucket = {
      id: m.id, remoteId: m.remoteId ?? null, title: m.title, category: m.category, emoji: m.emoji,
      detail: m.detail ?? null, happenedAt: m.happenedAt ?? null, ageDescription: m.ageDescription ?? null,
      isCustom: m.isCustom ? 1 : 0, ceremonyPlayed: m.ceremonyPlayed ? 1 : 0,
      syncState: m.syncState, createdAt: m.createdAt, entryId: m.entryId ?? null
    };
    await this.store!.insert('milestone', v, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async fetchMilestones(): Promise<Milestone[]> {
    const pred = new relationalStore.RdbPredicates('milestone');
    pred.orderByDesc('createdAt');
    const rs = await this.store!.query(pred);
    const out: Milestone[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        remoteId: AppDatabase.optStr(rs, 'remoteId'),
        title: rs.getString(rs.getColumnIndex('title')),
        category: rs.getString(rs.getColumnIndex('category')),
        emoji: rs.getString(rs.getColumnIndex('emoji')),
        detail: AppDatabase.optStr(rs, 'detail'),
        happenedAt: AppDatabase.optNum(rs, 'happenedAt'),
        ageDescription: AppDatabase.optStr(rs, 'ageDescription'),
        isCustom: rs.getLong(rs.getColumnIndex('isCustom')) === 1,
        ceremonyPlayed: rs.getLong(rs.getColumnIndex('ceremonyPlayed')) === 1,
        syncState: rs.getString(rs.getColumnIndex('syncState')) as SyncState,
        createdAt: rs.getLong(rs.getColumnIndex('createdAt')),
        entryId: AppDatabase.optStr(rs, 'entryId')
      });
    }
    rs.close();
    return out;
  }

  // —— TimeCapsule ——
  async insertCapsule(c: TimeCapsule): Promise<void> {
    const v: relationalStore.ValuesBucket = {
      id: c.id, remoteId: c.remoteId ?? null, title: c.title, letterText: c.letterText ?? null, fromRole: c.fromRole,
      unlockAt: c.unlockAt, isLocked: c.isLocked ? 1 : 0, encryptedBlobFileName: c.encryptedBlobFileName ?? null,
      coverEmoji: c.coverEmoji ?? null, syncState: c.syncState, createdAt: c.createdAt
    };
    await this.store!.insert('time_capsule', v);
  }

  async fetchCapsules(): Promise<TimeCapsule[]> {
    const pred = new relationalStore.RdbPredicates('time_capsule');
    pred.orderByAsc('unlockAt');
    const rs = await this.store!.query(pred);
    const out: TimeCapsule[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        remoteId: AppDatabase.optStr(rs, 'remoteId'),
        title: rs.getString(rs.getColumnIndex('title')),
        letterText: AppDatabase.optStr(rs, 'letterText'),
        fromRole: rs.getString(rs.getColumnIndex('fromRole')),
        unlockAt: rs.getLong(rs.getColumnIndex('unlockAt')),
        isLocked: rs.getLong(rs.getColumnIndex('isLocked')) === 1,
        encryptedBlobFileName: AppDatabase.optStr(rs, 'encryptedBlobFileName'),
        coverEmoji: AppDatabase.optStr(rs, 'coverEmoji'),
        syncState: rs.getString(rs.getColumnIndex('syncState')) as SyncState,
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      });
    }
    rs.close();
    return out;
  }

  // —— Comment（家人合奏）——
  async insertComment(c: Comment): Promise<void> {
    const v: relationalStore.ValuesBucket = {
      id: c.id, remoteId: c.remoteId ?? null, entryId: c.entryId, authorRole: c.authorRole,
      text: c.text ?? null, voiceFileName: c.voiceFileName ?? null, remoteURL: c.remoteURL ?? null,
      voiceDuration: c.voiceDuration, voiceWaveform: JSON.stringify(c.voiceWaveform),
      syncState: c.syncState, createdAt: c.createdAt
    };
    await this.store!.insert('comment', v);
  }

  async fetchCommentsForEntry(entryId: string): Promise<Comment[]> {
    const pred = new relationalStore.RdbPredicates('comment');
    pred.equalTo('entryId', entryId);
    pred.orderByAsc('createdAt');
    const rs = await this.store!.query(pred);
    const out: Comment[] = [];
    while (rs.goToNextRow()) {
      const wf = AppDatabase.optStr(rs, 'voiceWaveform');
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        remoteId: AppDatabase.optStr(rs, 'remoteId'),
        entryId: rs.getString(rs.getColumnIndex('entryId')),
        authorRole: rs.getString(rs.getColumnIndex('authorRole')),
        text: AppDatabase.optStr(rs, 'text'),
        voiceFileName: AppDatabase.optStr(rs, 'voiceFileName'),
        remoteURL: AppDatabase.optStr(rs, 'remoteURL'),
        voiceDuration: AppDatabase.optNum(rs, 'voiceDuration') ?? 0,
        voiceWaveform: wf ? JSON.parse(wf) as number[] : [],
        syncState: rs.getString(rs.getColumnIndex('syncState')) as SyncState,
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      });
    }
    rs.close();
    return out;
  }

  // —— VoiceMemo（成长之声）——
  async insertVoiceMemo(m: VoiceMemo): Promise<void> {
    const v: relationalStore.ValuesBucket = {
      id: m.id, remoteId: m.remoteId ?? null, kindRaw: m.kindRaw, localFileName: m.localFileName ?? null,
      remoteURL: m.remoteURL ?? null, transcript: m.transcript ?? null, ageYears: m.ageYears ?? null,
      recordedAt: m.recordedAt, durationSeconds: m.durationSeconds ?? null,
      syncState: m.syncState, createdAt: m.createdAt
    };
    await this.store!.insert('voice_memo', v);
  }

  async fetchVoiceMemos(): Promise<VoiceMemo[]> {
    const pred = new relationalStore.RdbPredicates('voice_memo');
    pred.orderByDesc('recordedAt');
    const rs = await this.store!.query(pred);
    const out: VoiceMemo[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        remoteId: AppDatabase.optStr(rs, 'remoteId'),
        kindRaw: rs.getString(rs.getColumnIndex('kindRaw')),
        localFileName: AppDatabase.optStr(rs, 'localFileName'),
        remoteURL: AppDatabase.optStr(rs, 'remoteURL'),
        transcript: AppDatabase.optStr(rs, 'transcript'),
        ageYears: AppDatabase.optNum(rs, 'ageYears'),
        recordedAt: rs.getLong(rs.getColumnIndex('recordedAt')),
        durationSeconds: AppDatabase.optNum(rs, 'durationSeconds'),
        syncState: rs.getString(rs.getColumnIndex('syncState')) as SyncState,
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      });
    }
    rs.close();
    return out;
  }

  // —— FirstTime（人生第一次）——
  async insertFirstTime(f: FirstTime): Promise<void> {
    const v: relationalStore.ValuesBucket = {
      id: f.id, remoteId: f.remoteId ?? null, what: f.what, detectedByAI: f.detectedByAI ? 1 : 0,
      confirmedByParent: f.confirmedByParent ? 1 : 0, ceremonyPlayed: f.ceremonyPlayed ? 1 : 0,
      happenedAt: f.happenedAt, entryId: f.entryId ?? null, syncState: f.syncState, createdAt: f.createdAt
    };
    await this.store!.insert('first_time', v, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async fetchFirstTimes(): Promise<FirstTime[]> {
    const pred = new relationalStore.RdbPredicates('first_time');
    pred.orderByDesc('happenedAt');
    const rs = await this.store!.query(pred);
    const out: FirstTime[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        remoteId: AppDatabase.optStr(rs, 'remoteId'),
        what: rs.getString(rs.getColumnIndex('what')),
        detectedByAI: rs.getLong(rs.getColumnIndex('detectedByAI')) === 1,
        confirmedByParent: rs.getLong(rs.getColumnIndex('confirmedByParent')) === 1,
        ceremonyPlayed: rs.getLong(rs.getColumnIndex('ceremonyPlayed')) === 1,
        happenedAt: rs.getLong(rs.getColumnIndex('happenedAt')),
        entryId: AppDatabase.optStr(rs, 'entryId'),
        syncState: rs.getString(rs.getColumnIndex('syncState')) as SyncState,
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      });
    }
    rs.close();
    return out;
  }

  // —— GrowthMovie（年度成长电影）——
  async upsertGrowthMovie(g: GrowthMovie): Promise<void> {
    const v: relationalStore.ValuesBucket = {
      id: g.id, remoteId: g.remoteId ?? null, year: g.year, remoteURL: g.remoteURL ?? null,
      status: g.status, narrationScript: g.narrationScript ?? null, createdAt: g.createdAt
    };
    await this.store!.insert('growth_movie', v, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async fetchGrowthMovies(): Promise<GrowthMovie[]> {
    const pred = new relationalStore.RdbPredicates('growth_movie');
    pred.orderByDesc('year');
    const rs = await this.store!.query(pred);
    const out: GrowthMovie[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        remoteId: AppDatabase.optStr(rs, 'remoteId'),
        year: rs.getLong(rs.getColumnIndex('year')),
        remoteURL: AppDatabase.optStr(rs, 'remoteURL'),
        status: rs.getString(rs.getColumnIndex('status')),
        narrationScript: AppDatabase.optStr(rs, 'narrationScript'),
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      });
    }
    rs.close();
    return out;
  }

  // —— PendingDeletion（待同步删除队列）——
  async enqueueDeletion(d: PendingDeletion): Promise<void> {
    const v: relationalStore.ValuesBucket = {
      id: d.id, collection: d.collection, remoteId: d.remoteId, createdAt: d.createdAt
    };
    await this.store!.insert('pending_deletion', v);
  }

  async fetchPendingDeletions(): Promise<PendingDeletion[]> {
    const pred = new relationalStore.RdbPredicates('pending_deletion');
    pred.orderByAsc('createdAt');
    const rs = await this.store!.query(pred);
    const out: PendingDeletion[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        collection: rs.getString(rs.getColumnIndex('collection')),
        remoteId: rs.getString(rs.getColumnIndex('remoteId')),
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      });
    }
    rs.close();
    return out;
  }

  async dequeueDeletion(id: string): Promise<void> {
    const pred = new relationalStore.RdbPredicates('pending_deletion');
    pred.equalTo('id', id);
    await this.store!.delete(pred);
  }

  // —— FeedEvent（家庭动态）——
  async insertFeedEvent(f: FeedEvent): Promise<void> {
    const v: relationalStore.ValuesBucket = {
      id: f.id, kind: f.kind, actorRole: f.actorRole, summary: f.summary,
      targetLocalId: f.targetLocalId ?? null, happenedAt: f.happenedAt
    };
    await this.store!.insert('feed_event', v);
  }

  async fetchFeedEvents(limit: number = 100): Promise<FeedEvent[]> {
    const pred = new relationalStore.RdbPredicates('feed_event');
    pred.orderByDesc('happenedAt');
    pred.limitAs(limit);
    const rs = await this.store!.query(pred);
    const out: FeedEvent[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        kind: rs.getString(rs.getColumnIndex('kind')),
        actorRole: rs.getString(rs.getColumnIndex('actorRole')),
        summary: rs.getString(rs.getColumnIndex('summary')),
        targetLocalId: AppDatabase.optStr(rs, 'targetLocalId'),
        happenedAt: rs.getLong(rs.getColumnIndex('happenedAt')),
        syncState: SyncState.synced,
        createdAt: rs.getLong(rs.getColumnIndex('happenedAt'))
      });
    }
    rs.close();
    return out;
  }

  // —— 通用：更新 Entry 任意字段 / 删除 ——
  async updateEntryFields(id: string, fields: relationalStore.ValuesBucket): Promise<void> {
    const pred = new relationalStore.RdbPredicates('entry');
    pred.equalTo('id', id);
    await this.store!.update(fields, pred);
  }

  async deleteEntryHard(id: string): Promise<void> {
    const pred = new relationalStore.RdbPredicates('entry');
    pred.equalTo('id', id);
    await this.store!.delete(pred);
  }

  async updateMilestoneFields(id: string, fields: relationalStore.ValuesBucket): Promise<void> {
    const pred = new relationalStore.RdbPredicates('milestone');
    pred.equalTo('id', id);
    await this.store!.update(fields, pred);
  }

  async deleteCapsule(id: string): Promise<void> {
    const pred = new relationalStore.RdbPredicates('time_capsule');
    pred.equalTo('id', id);
    await this.store!.delete(pred);
  }

  async deleteHealth(id: string): Promise<void> {
    const pred = new relationalStore.RdbPredicates('health_record');
    pred.equalTo('id', id);
    await this.store!.delete(pred);
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
