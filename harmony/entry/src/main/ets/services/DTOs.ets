// MARK: - DTO（对照 iOS Services/Networking/DTOs.swift）
// 字段名与服务端 PocketBase collection 一致，保证跨端同步兼容。
// 日期统一用 ISO8601 字符串与服务端交换。

export interface EntryDTO {
  id?: string;
  localId: string;
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
  avatarRemoteURL?: string;
  createdAt: string;
}

export interface MediaDTO {
  id?: string;
  localId: string;
  entryLocalId: string;
  type: string;
  remoteURL?: string;
  aiTags: string[];
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

export interface MilestoneDTO {
  id?: string;
  localId: string;
  title: string;
  category: string;
  emoji: string;
  detail?: string;
  happenedAt?: string;
  isCustom: boolean;
  createdAt: string;
}

export interface TimeCapsuleDTO {
  id?: string;
  localId: string;
  title: string;
  fromRole: string;
  unlockAt: string;
  isLocked: boolean;
  coverEmoji?: string;
  createdAt: string;
}

// 鉴权（PocketBase password auth）
export interface AuthResponse {
  token: string;
  record: AuthRecord;
}

export interface AuthRecord {
  id: string;
  email: string;
}
