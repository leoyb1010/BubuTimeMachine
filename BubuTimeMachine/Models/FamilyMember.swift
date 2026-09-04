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
    /// 紧急联系电话（可选）。只用于「一页纸给老师」，**不进 DTO、不上服务器**——
    /// 家人的手机号没有任何同步价值，多存一处就多一处泄漏面。
    var contactPhone: String?
    /// 幼儿园登记的可接送人。同样只在本机，用于生成给老师的那一页。
    var canPickUpFromSchool: Bool = false
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
    /// 小名/乳名（可选）。身份卡背面与问候语可展示，additive 字段走自动轻量迁移。
    var nickname: String?
    /// 过敏源（可选，自由文本）。入园必填项之一，也是老师最需要知道的一条。
    /// 与 schoolStartDate 一样是纯 additive 可选字段。
    var allergies: String?
    /// 需要老师知道的用药或健康备注（可选，自由文本）。
    var medicalNotes: String?
    /// 上幼儿园的第一天（可选）。填了之后全 App 多一条与「来到世界第 N 天」并列的
    /// 「上学第 N 天」，开学前则是倒计时。
    ///
    /// 为什么是 optional：BubuSchemaV1 目前引用的是活模型类而非冻结快照，破坏性变更
    /// 没有可用的迁移路径（见 App/BubuSchema.swift 与 2026-09-04 审计 §1.1）。
    /// 纯 additive 的可选字段走自动轻量迁移是安全的——Media 追加 remoteThumbURL /
    /// contentHash 时已经验证过。在 schema 真修复之前，新能力只能用这种形状。
    var schoolStartDate: Date?
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
