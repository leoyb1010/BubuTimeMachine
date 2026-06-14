// MARK: - 数据模型（对照 iOS Models/*.swift 的 @Model）
// ArkTS 用 interface 描述行结构；持久化由 AppDatabase(RelationalStore) 负责。
// 字段命名与 iOS / 服务端 DTO 对齐，保证同步兼容。

import { SyncState } from './Enums';

// Entry：核心聚合根（一次「记录此刻」= 一个 Entry）
export interface Entry {
  id: string;                 // UUID 字符串
  remoteId?: string;
  title?: string;
  note?: string;              // 父母视角原文
  firstPersonNote?: string;   // AI 改写的布布第一人称
  happenedAt: number;         // 事件发生时间（epoch ms）
  locationName?: string;
  latitude?: number;
  longitude?: number;
  authorRole: string;         // 爸爸/妈妈/姥姥
  moodRaw?: string;
  syncState: SyncState;
  isArchived: boolean;
  editedAt?: number;
  createdAt: number;
}

// Media：照片/视频/音频（对照 iOS Media，含时长/尺寸/上传进度）
export interface Media {
  id: string;
  remoteId?: string;
  entryId: string;            // 外键 → Entry.id
  typeRaw: string;            // MediaType
  localFileName?: string;
  remoteURL?: string;
  thumbnailFileName?: string;
  durationSeconds?: number;   // 视频/音频时长
  width?: number;
  height?: number;
  uploadProgress: number;     // 0...1
  syncState: SyncState;
  aiTags: string[];
  createdAt: number;
}

// ChildProfile：布布档案（全局年龄计算真相源）
export interface ChildProfile {
  id: string;
  remoteId?: string;
  name: string;
  birthday: number;           // epoch ms
  gender?: string;
  bloodType?: string;
  birthPlace?: string;
  avatarMediaFileName?: string;
  avatarRemoteURL?: string;
  heroBackgroundFileName?: string;
  syncState: SyncState;
  createdAt: number;
}

// FamilyMember：家庭成员
export interface FamilyMember {
  id: string;
  remoteId?: string;
  name: string;
  relation: string;
  avatarEmoji: string;
  themeColorHex: string;
  isPrimary: boolean;
  syncState: SyncState;
  createdAt: number;
}

// Milestone：里程碑
export interface Milestone {
  id: string;
  remoteId?: string;
  title: string;
  category: string;
  emoji: string;
  detail?: string;
  happenedAt?: number;        // null = 未达成
  ageDescription?: string;
  isCustom: boolean;
  ceremonyPlayed: boolean;
  syncState: SyncState;
  createdAt: number;
  entryId?: string;
}

// TimeCapsule：时间胶囊
export interface TimeCapsule {
  id: string;
  remoteId?: string;
  title: string;
  letterText?: string;
  fromRole: string;
  unlockAt: number;
  isLocked: boolean;
  encryptedBlobFileName?: string;
  coverEmoji?: string;
  syncState: SyncState;
  createdAt: number;
}

// HealthRecord：健康记录（餐食/睡眠/营养/不舒服）
export interface HealthRecord {
  id: string;
  remoteId?: string;
  kind: string;
  title: string;
  detail?: string;
  recordedAt: number;
  amountText?: string;
  reaction?: string;
  amountValue?: number;
  amountUnit?: string;
  startAt?: number;
  endAt?: number;
  severity?: string;
  temperatureCelsius?: number;
  tags: string[];
  syncState: SyncState;
  createdAt: number;
}

// VoiceNote：语音记录（附在 Entry 上）
export interface VoiceNote {
  id: string;
  remoteId?: string;
  entryId: string;
  localFileName?: string;
  remoteURL?: string;
  durationSeconds: number;
  transcript?: string;
  authorRole: string;
  waveformSamples: number[];
  syncState: SyncState;
  createdAt: number;
}

// VoiceMemo：成长之声（按年龄横切归档她的声音 / 家人对她说的话）
export interface VoiceMemo {
  id: string;
  remoteId?: string;
  kindRaw: string;            // childVoice / familyVoice
  localFileName?: string;
  remoteURL?: string;
  transcript?: string;
  ageYears?: number;
  recordedAt: number;
  durationSeconds?: number;
  syncState: SyncState;
  createdAt: number;
}

export enum VoiceMemoKind {
  childVoice = 'childVoice',
  familyVoice = 'familyVoice'
}

// Comment：家人合奏多视角补充（可文字可语音）
export interface Comment {
  id: string;
  remoteId?: string;
  entryId: string;
  authorRole: string;
  text?: string;
  voiceFileName?: string;
  remoteURL?: string;
  voiceDuration: number;
  voiceWaveform: number[];
  syncState: SyncState;
  createdAt: number;
}

// FeedEvent：家庭动态
export interface FeedEvent {
  id: string;
  kind: string;
  actorRole: string;
  summary: string;
  targetLocalId?: string;
  happenedAt: number;
  syncState: SyncState;
  createdAt: number;
}

// FirstTime：人生第一次
export interface FirstTime {
  id: string;
  remoteId?: string;
  what: string;
  detectedByAI: boolean;
  confirmedByParent: boolean;
  ceremonyPlayed: boolean;
  happenedAt: number;
  entryId?: string;
  syncState: SyncState;
  createdAt: number;
}

// GrowthMeasurement：成长测量（身高/体重/头围，结构化）
export interface GrowthMeasurement {
  id: string;
  remoteId?: string;
  measuredAt: number;
  heightCm?: number;
  weightKg?: number;
  headCircumferenceCm?: number;
  note?: string;
  source: string;             // manual / ai / checkup
  syncState: SyncState;
  createdAt: number;
  updatedAt: number;
}

// VaccineRecord：疫苗接种记录（结构化）
export interface VaccineRecord {
  id: string;
  remoteId?: string;
  doseId?: string;            // 对应 VaccineDose.schedule 的剂次 id
  vaccineName: string;
  doseLabel?: string;
  injectedAt: number;
  hospital?: string;
  injectionSite?: string;
  reaction?: string;
  note?: string;
  source: string;             // manual / ai / migration
  syncState: SyncState;
  createdAt: number;
  updatedAt: number;
}

// GrowthMovie：年度成长电影
export interface GrowthMovie {
  id: string;
  remoteId?: string;
  year: number;               // 对应哪一岁
  remoteURL?: string;
  status: string;             // pending / generating / ready / failed
  narrationScript?: string;
  createdAt: number;
}

// PendingDeletion：待同步删除队列
export interface PendingDeletion {
  id: string;
  collection: string;         // PocketBase collection 名
  remoteId: string;
  createdAt: number;
}

// MilestoneTemplate：里程碑预设模板
export interface MilestoneTemplate {
  title: string;
  category: string;
  emoji: string;
}
