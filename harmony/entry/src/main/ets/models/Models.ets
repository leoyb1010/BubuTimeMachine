// MARK: - 数据模型（对照 iOS Models/*.swift 的 @Model）
// ArkTS 用 interface 描述行结构；持久化由 AppDatabase(RelationalStore) 负责。
// 字段命名与 iOS / 服务端 DTO 对齐，保证同步兼容。

import { SyncState, MediaType } from './Enums';

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

// Media：照片/视频/音频
export interface Media {
  id: string;
  remoteId?: string;
  entryId: string;            // 外键 → Entry.id
  typeRaw: string;            // MediaType
  localFileName?: string;
  remoteURL?: string;
  thumbnailFileName?: string;
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

// VoiceNote：语音记录
export interface VoiceNote {
  id: string;
  remoteId?: string;
  entryId: string;
  localFileName?: string;
  remoteURL?: string;
  durationSeconds: number;
  authorRole: string;
  waveformSamples: number[];
  createdAt: number;
}

// Comment：家人合奏多视角补充
export interface Comment {
  id: string;
  remoteId?: string;
  entryId: string;
  authorRole: string;
  text: string;
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
}

// FirstTime：第一次
export interface FirstTime {
  id: string;
  remoteId?: string;
  what: string;
  detectedByAI: boolean;
  confirmedByParent: boolean;
  happenedAt: number;
  entryId?: string;
  createdAt: number;
}

// GrowthMeasurement：成长测量（身高/体重）
export interface GrowthMeasurement {
  id: string;
  remoteId?: string;
  measuredAt: number;
  heightCm?: number;
  weightKg?: number;
  headCircumferenceCm?: number;
  syncState: SyncState;
  createdAt: number;
}

// VaccineRecord：疫苗
export interface VaccineRecord {
  id: string;
  remoteId?: string;
  name: string;
  doseLabel?: string;
  scheduledAt?: number;
  administeredAt?: number;
  note?: string;
  syncState: SyncState;
  createdAt: number;
}
