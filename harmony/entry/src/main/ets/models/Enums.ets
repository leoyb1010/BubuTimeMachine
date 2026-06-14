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

// 心情标签（与 iOS Mood 一致，20 种；emoji 对照见 moodEmoji）
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
  focused = '认真',
  shy = '害羞',
  love = '被爱'
}

export const ALL_MOODS: Mood[] = [
  Mood.happy, Mood.calm, Mood.naughty, Mood.proud, Mood.curious, Mood.sleepy,
  Mood.grievance, Mood.milestone, Mood.eating, Mood.laughing, Mood.crying, Mood.angry,
  Mood.surprised, Mood.brave, Mood.cuddly, Mood.sick, Mood.playful, Mood.focused,
  Mood.shy, Mood.love
];

export function moodEmoji(m: Mood | undefined): string {
  switch (m) {
    case Mood.happy: return '😄';
    case Mood.calm: return '😌';
    case Mood.naughty: return '😜';
    case Mood.proud: return '🥹';
    case Mood.curious: return '🤔';
    case Mood.sleepy: return '😴';
    case Mood.grievance: return '🥺';
    case Mood.milestone: return '🌟';
    case Mood.eating: return '😋';
    case Mood.laughing: return '🤣';
    case Mood.crying: return '😭';
    case Mood.angry: return '😤';
    case Mood.surprised: return '😮';
    case Mood.brave: return '💪';
    case Mood.cuddly: return '🤗';
    case Mood.sick: return '🤒';
    case Mood.playful: return '🧸';
    case Mood.focused: return '👀';
    case Mood.shy: return '🫣';
    case Mood.love: return '💗';
    default: return '📝';
  }
}

// 关系称谓（成员系统，对照 iOS Relation）
export enum Relation {
  papa = '爸爸',
  mama = '妈妈',
  grandma = '姥姥',
  grandpa = '姥爷',
  yeye = '爷爷',
  nainai = '奶奶',
  other = '家人'
}

export const ALL_RELATIONS: Relation[] = [
  Relation.papa, Relation.mama, Relation.grandma, Relation.grandpa,
  Relation.yeye, Relation.nainai, Relation.other
];

export function relationDefaultEmoji(r: Relation): string {
  switch (r) {
    case Relation.papa: return '👨';
    case Relation.mama: return '👩';
    case Relation.grandma: return '👵';
    case Relation.grandpa: return '👴';
    case Relation.yeye: return '👴';
    case Relation.nainai: return '👵';
    case Relation.other: return '🙂';
    default: return '🙂';
  }
}

export function relationDefaultColorHex(r: Relation): string {
  switch (r) {
    case Relation.papa: return '#5B8DEF';
    case Relation.mama: return '#F28C9E';
    case Relation.grandma: return '#F2B705';
    case Relation.grandpa: return '#7BB662';
    case Relation.yeye: return '#8E7CC3';
    case Relation.nainai: return '#E08D79';
    case Relation.other: return '#9AA0A6';
    default: return '#9AA0A6';
  }
}

// 家庭动态类型（对照 iOS FeedEventKind）
export enum FeedEventKind {
  entryCreated = 'entryCreated',
  entryArchived = 'entryArchived',
  commentAdded = 'commentAdded',
  voiceAdded = 'voiceAdded',
  milestoneLit = 'milestoneLit',
  healthRecorded = 'healthRecorded',
  firstTimeConfirmed = 'firstTimeConfirmed'
}

export function feedEventTitle(k: FeedEventKind): string {
  switch (k) {
    case FeedEventKind.entryCreated: return '瞬间';
    case FeedEventKind.entryArchived: return '删除';
    case FeedEventKind.commentAdded: return '评论';
    case FeedEventKind.voiceAdded: return '语音';
    case FeedEventKind.milestoneLit: return '里程碑';
    case FeedEventKind.healthRecorded: return '健康';
    case FeedEventKind.firstTimeConfirmed: return '第一次';
    default: return '动态';
  }
}

export function feedEventEmoji(k: FeedEventKind): string {
  switch (k) {
    case FeedEventKind.entryCreated: return '💖';
    case FeedEventKind.entryArchived: return '🗑️';
    case FeedEventKind.commentAdded: return '💬';
    case FeedEventKind.voiceAdded: return '🎙️';
    case FeedEventKind.milestoneLit: return '⭐';
    case FeedEventKind.healthRecorded: return '🩺';
    case FeedEventKind.firstTimeConfirmed: return '✨';
    default: return '💖';
  }
}

// 健康记录类型（对照 iOS HealthRecordKind）
export enum HealthRecordKind {
  meal = 'meal',
  snack = 'snack',
  supplement = 'supplement',
  water = 'water',
  sleep = 'sleep',
  symptom = 'symptom',
  checkup = 'checkup'
}

export const ALL_HEALTH_KINDS: HealthRecordKind[] = [
  HealthRecordKind.meal, HealthRecordKind.snack, HealthRecordKind.supplement,
  HealthRecordKind.water, HealthRecordKind.sleep, HealthRecordKind.symptom, HealthRecordKind.checkup
];

export interface HealthKindMeta {
  title: string;
  emoji: string;
  placeholder: string;
  heroSubtitle: string;
}

export function healthKindMeta(k: HealthRecordKind): HealthKindMeta {
  switch (k) {
    case HealthRecordKind.meal:
      return { title: '餐食', emoji: '🍚', placeholder: '如：早餐小米粥 + 鸡蛋羹', heroSubtitle: '记录正餐、主食、蛋白质和吃完反应。' };
    case HealthRecordKind.snack:
      return { title: '零食', emoji: '🍓', placeholder: '如：苹果块、酸奶', heroSubtitle: '记录水果、酸奶、磨牙棒和尝新反应。' };
    case HealthRecordKind.supplement:
      return { title: '营养补充', emoji: '💊', placeholder: '如：维D、钙、益生菌', heroSubtitle: '维 D、钙、益生菌等，适合连续记录。' };
    case HealthRecordKind.water:
      return { title: '喝水', emoji: '💧', placeholder: '如：温水', heroSubtitle: '快速点一下，记录今天喝了多少水。' };
    case HealthRecordKind.sleep:
      return { title: '睡眠', emoji: '🌙', placeholder: '如：午睡', heroSubtitle: '记录入睡、醒来、午睡和夜醒。' };
    case HealthRecordKind.symptom:
      return { title: '不舒服', emoji: '🌡️', placeholder: '如：流鼻涕、咳嗽、肚子不舒服', heroSubtitle: '记录症状、体温、严重程度。' };
    case HealthRecordKind.checkup:
      return { title: '体检护理', emoji: '🩺', placeholder: '如：身高体重、疫苗、牙齿护理', heroSubtitle: '记录身高、体重、疫苗、牙齿和医生建议。' };
    default:
      return { title: '记录', emoji: '📝', placeholder: '', heroSubtitle: '' };
  }
}
