// MARK: - DTO（对照 iOS Services/Networking/DTOs.swift）
// 字段名与服务端 PocketBase collection 一致，保证跨端同步兼容。
// 日期统一用 ISO8601 字符串与服务端交换。
// UI 永不直接依赖这些类型；它们只在 Service 层与服务器之间流转。

export interface EntryDTO {
  id?: string;            // remoteId
  localId: string;        // 客户端 UUID，幂等去重用
  familyId?: string;
  authorUserId?: string;
  title?: string;
  note?: string;
  firstPersonNote?: string;
  happenedAt: string;       // ISO8601
  locationName?: string;
  latitude?: number;
  longitude?: number;
  authorRole: string;
  mood?: string;
  isArchived: boolean;
  editedAt?: string;
  createdAt: string;
}

export interface MediaDTO {
  id?: string;
  localId: string;
  entryLocalId: string;
  mediaType: string;        // 对齐服务端字段名 mediaType
  remoteURL?: string;
  durationSeconds?: number;
  width?: number;
  height?: number;
  aiTags: string[];
  createdAt: string;
}

export interface MilestoneDTO {
  id?: string;
  localId: string;
  title: string;
  category: string;
  emoji: string;
  detail?: string;
  happenedAt?: string;
  ageDescription?: string;
  isCustom: boolean;
  createdAt: string;
}

export interface FirstTimeDTO {
  id?: string;
  localId: string;
  what: string;
  happenedAt: string;
  detectedByAI: boolean;
  confirmedByParent: boolean;
  entryLocalId?: string;
  createdAt: string;
}

export interface FamilyMemberDTO {
  id?: string;
  localId: string;
  name: string;
  relation: string;
  avatarEmoji: string;
  themeColorHex: string;
  isPrimary: boolean;
  createdAt: string;
}

export interface ChildProfileDTO {
  id?: string;
  localId: string;
  name: string;
  birthday: string;
  gender?: string;
  bloodType?: string;       // 与 iOS 对齐（含血型同步）
  birthPlace?: string;
  avatarRemoteURL?: string; // 由服务端 avatar file 字段派生，身份卡跨设备显示头像
  createdAt: string;
}

export interface HealthRecordDTO {
  id?: string;
  localId: string;
  kind: string;
  title: string;
  detail?: string;
  recordedAt: string;
  amountText?: string;
  reaction?: string;
  amountValue?: number;
  amountUnit?: string;
  startAt?: string;
  endAt?: string;
  severity?: string;
  temperatureCelsius?: number;
  tags: string[];
  createdAt: string;
}

export interface VaccineRecordDTO {
  id?: string;
  localId: string;
  doseId?: string;
  vaccineName: string;
  doseLabel?: string;
  injectedAt: string;
  hospital?: string;
  injectionSite?: string;
  reaction?: string;
  note?: string;
  source: string;
  createdAt: string;
}

export interface GrowthMeasurementDTO {
  id?: string;
  localId: string;
  measuredAt: string;
  heightCm?: number;
  weightKg?: number;
  headCircumferenceCm?: number;
  note?: string;
  source: string;
  createdAt: string;
}

export interface CommentDTO {
  id?: string;
  localId: string;
  entryLocalId: string;
  authorRole: string;
  text?: string;
  remoteURL?: string;
  voiceDuration: number;
  voiceWaveform: number[];
  createdAt: string;
}

export interface VoiceNoteDTO {
  id?: string;
  localId: string;
  entryLocalId: string;
  authorRole: string;
  remoteURL?: string;
  durationSeconds: number;
  transcript?: string;
  waveform: number[];
  createdAt: string;
}

export interface VoiceMemoDTO {
  id?: string;
  localId: string;
  kind: string;
  remoteURL?: string;
  transcript?: string;
  ageYears?: number;
  recordedAt: string;
  durationSeconds?: number;
  createdAt: string;
}

export interface TimeCapsuleDTO {
  id?: string;
  localId: string;
  title: string;
  fromRole: string;
  unlockAt: string;
  isLocked: boolean;
  encryptedBlobRemoteURL?: string;
  coverEmoji?: string;
  createdAt: string;
}

// 鉴权（PocketBase password auth）
export interface AuthToken {
  token: string;
  role: string;
  expiresAt?: string;
}

export interface AuthResponse {
  token: string;
  record: AuthRecord;
}

export interface AuthRecord {
  id: string;
  email: string;
}

// MARK: - 媒体上传请求（对照 iOS MediaUploadRequest）
export interface MediaUploadRequest {
  mediaId: string;          // UUID 字符串
  entryLocalId: string;
  fileURL: string;          // 本地文件路径（sandbox 内）
  type: string;             // MediaType 原始值
  fileName: string;
}

// MARK: - 上传过程事件（对照 iOS UploadEvent）
// kind = 'progress'：fraction 为 0...1；kind = 'completed'：携带 remoteId/url。
export interface UploadEvent {
  kind: string;             // 'progress' | 'completed'
  fraction?: number;        // 0...1
  remoteId?: string;
  url?: string;
}

// MARK: - 上传结果（对照 iOS UploadedFileResult）
// PocketBase 会清洗并追加随机后缀改写文件名，远端 URL 必须用响应里的真实文件名拼。
export interface UploadedFileResult {
  recordId: string;
  storedFileName: string;
}

// MARK: - Realtime 远端变更事件（对照 iOS RealtimeEvent）
export interface RealtimeEvent {
  kind: string;             // 'connected' | 'disconnected' | 'entryChanged' | 'entryDeleted'
  entry?: EntryDTO;
  remoteId?: string;
}

// MARK: - AI 结果类型（对照 iOS DTOs.swift 末段）

// AI 对一条 Entry 的归类结果：时间/地点/事件聚类。
export interface AIClassification {
  suggestedTitle?: string;
  eventCluster?: string;    // 用于时光轴按"事件"重排
  placeName?: string;
  visualTags: string[];
}

// "这是第一次吗"识别建议。
export interface FirstTimeSuggestion {
  what: string;             // "第一次吃西瓜"
  confidence: number;       // 0...1
}

// 年度成长电影生成任务句柄。
export interface GrowthMovieJob {
  jobId: string;
  year: number;
  status: string;           // pending / generating / ready / failed
}
