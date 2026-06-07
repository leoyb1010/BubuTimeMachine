import Foundation

// MARK: - 同步状态
/// 描述一条本地记录与自托管服务器之间的同步生命周期。
/// 离线优先：所有内容先以 `.local` 落本地 SwiftData，再由后台同步层推进状态。
enum SyncState: String, Codable, Sendable {
    case local      // 仅本地，待上传
    case uploading  // 上传中
    case synced     // 已同步
    case failed     // 失败待重试

    /// 适老化口语文案：错误永不报代码，永不吓人。
    var friendlyText: String {
        switch self {
        case .local:     return "已经存在手机里啦"
        case .uploading: return "正在保存…"
        case .synced:    return "已经收好啦"
        case .failed:    return "等会儿再试，已经存在手机里啦"
        }
    }
}

// MARK: - 媒体类型
enum MediaType: String, Codable, Sendable {
    case photo
    case video
    case audio
}

// MARK: - 家庭角色
/// 三人家庭场景：记录者身份。用于署名、家人合奏多视角、当前身份切换。
enum FamilyRole: String, Codable, CaseIterable, Sendable {
    case papa = "爸爸"
    case mama = "妈妈"
    case grandma = "姥姥"

    var displayName: String { rawValue }
}

// MARK: - 心情标签
/// 给每一个此刻一种心情，时光轴可按心情回看。
enum Mood: String, Codable, CaseIterable, Sendable {
    case happy = "开心"
    case calm = "平静"
    case naughty = "调皮"
    case proud = "骄傲"
    case curious = "好奇"
    case sleepy = "困困"
    case grievance = "委屈"
    case milestone = "高光"

    var emoji: String {
        switch self {
        case .happy:      return "😄"
        case .calm:       return "😌"
        case .naughty:    return "😜"
        case .proud:      return "🥹"
        case .curious:    return "🤔"
        case .sleepy:     return "😴"
        case .grievance:  return "🥺"
        case .milestone:  return "🌟"
        }
    }
}

// MARK: - 关系称谓（成员系统）
enum Relation: String, CaseIterable, Sendable {
    case papa = "爸爸"
    case mama = "妈妈"
    case grandma = "姥姥"
    case grandpa = "姥爷"
    case yeye = "爷爷"
    case nainai = "奶奶"
    case other = "家人"

    var defaultEmoji: String {
        switch self {
        case .papa:    return "👨"
        case .mama:    return "👩"
        case .grandma: return "👵"
        case .grandpa: return "👴"
        case .yeye:    return "👴"
        case .nainai:  return "👵"
        case .other:   return "🙂"
        }
    }

    var defaultColorHex: String {
        switch self {
        case .papa:    return "#5B8DEF"
        case .mama:    return "#F28C9E"
        case .grandma: return "#F2B705"
        case .grandpa: return "#7BB662"
        case .yeye:    return "#8E7CC3"
        case .nainai:  return "#E08D79"
        case .other:   return "#9AA0A6"
        }
    }
}
