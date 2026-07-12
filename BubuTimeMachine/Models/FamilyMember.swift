import SwiftData
import Foundation

// MARK: - FamilyMember（家庭成员：轻量身份账号）
/// 适老化 + 自托管家庭场景：不设密码，"选择你是谁"即可。
/// 每位成员有头像 emoji、专属主题色、与布布的关系称谓。
@Model
final class FamilyMember {
    @Attribute(.unique) var id: UUID
    var remoteId: String?
    var name: String                  // 显示名，如"妈妈""姥姥""王芳"
    var relation: String              // 与布布的关系：爸爸/妈妈/姥姥/姥爷/爷爷/奶奶/其他
    var avatarEmoji: String           // 头像（emoji，适老、零素材依赖）
    var themeColorHex: String         // 专属主题色
    var isPrimary: Bool = false       // 是否主账号（首个创建者）
    var syncStateRaw: String = SyncState.local.rawValue
    var createdAt: Date

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }

    init(name: String, relation: String, avatarEmoji: String = "🙂",
         themeColorHex: String = "#F28C9E") {
        self.id = UUID()
        self.name = name
        self.relation = relation
        self.avatarEmoji = avatarEmoji
        self.themeColorHex = themeColorHex
        self.createdAt = .now
    }
}

// MARK: - ChildProfile（布布档案：全局年龄计算的真相源）
/// 唯一的孩子档案。生日驱动整个 App 的"X岁X月X天""来到世界第N天""那年今日"。
@Model
final class ChildProfile {
    @Attribute(.unique) var id: UUID
    var remoteId: String?
    var name: String                  // "布布"
    var birthday: Date
    var gender: String?               // 可选
    var avatarMediaFileName: String?  // 布布头像（沙盒文件名）
    var avatarRemoteURL: String?      // 头像远端 URL（PocketBase childprofile.avatar；跨设备同步用）
    var heroBackgroundFileName: String? // 首页背景（布布的照片）
    var bloodType: String?
    var birthPlace: String?
    var syncStateRaw: String = SyncState.local.rawValue
    var createdAt: Date

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }

    init(name: String = "布布", birthday: Date) {
        self.id = UUID()
        self.name = name
        // 生日归一化到当天 0 点：DatePicker(.date) 的初值会带当前时分秒，
        // 若原样入库会让全 App 年龄口径出现"当天忽早忽晚"的偏差（C-P1-5）。
        self.birthday = Calendar.current.startOfDay(for: birthday)
        self.createdAt = .now
    }
}
