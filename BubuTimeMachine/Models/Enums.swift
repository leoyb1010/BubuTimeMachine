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
