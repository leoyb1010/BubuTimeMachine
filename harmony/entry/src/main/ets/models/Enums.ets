// MARK: - 枚举（对照 iOS Models/Enums.swift，值完全一致以保证与服务端兼容）

// 同步状态：离线优先生命周期
export enum SyncState {
  local = 'local',         // 仅本地，待上传
  uploading = 'uploading', // 上传中
  synced = 'synced',       // 已同步
  failed = 'failed'        // 失败待重试
}

export function syncStateFriendlyText(s: SyncState): string {
  switch (s) {
    case SyncState.local: return '已经存在手机里啦';
    case SyncState.uploading: return '正在保存…';
    case SyncState.synced: return '已经收好啦';
    case SyncState.failed: return '等会儿再试，已经存在手机里啦';
    default: return '已经存在手机里啦';
  }
}

// 媒体类型
export enum MediaType {
  photo = 'photo',
  video = 'video',
  audio = 'audio'
}

// 家庭角色（中文值，与 iOS 一致，用于署名/同步）
export enum FamilyRole {
  papa = '爸爸',
  mama = '妈妈',
  grandma = '姥姥'
}

export const ALL_FAMILY_ROLES: FamilyRole[] = [FamilyRole.papa, FamilyRole.mama, FamilyRole.grandma];

// 心情标签（与 iOS Mood 一致；emoji 对照见 moodEmoji）
export enum Mood {
  happy = '开心',
  calm = '平静',
  naughty = '调皮',
  proud = '骄傲',
  curious = '好奇',
  sleepy = '困困',
  grievance = '委屈',
  milestone = '高光',
  eating = '香香',
  laughing = '咯咯笑',
  crying = '哭哭',
  angry = '生气',
  surprised = '惊喜',
  brave = '勇敢',
  cuddly = '黏人',
  sick = '不舒服',
  playful = '爱玩',
  focused = '认真'
}

export function moodEmoji(m: Mood | undefined): string {
  switch (m) {
    case Mood.happy: return '😄';
    case Mood.calm: return '😌';
    case Mood.naughty: return '😜';
    case Mood.proud: return '😎';
    case Mood.curious: return '🤔';
    case Mood.sleepy: return '😴';
    case Mood.grievance: return '🥺';
    case Mood.milestone: return '🌟';
    case Mood.eating: return '😋';
    case Mood.laughing: return '🤣';
    case Mood.crying: return '😭';
    case Mood.angry: return '😣';
    case Mood.surprised: return '😲';
    case Mood.brave: return '💪';
    case Mood.cuddly: return '🤗';
    case Mood.sick: return '🤒';
    case Mood.playful: return '🤸';
    case Mood.focused: return '🧐';
    default: return '📝';
  }
}
