import Foundation
import SwiftData

// 2.13.0 历史模型快照。只供迁移读取，禁止随活动模型变更。
// 关系目标也全部是 V1 内部类型，避免历史 schema 跟随当前业务类漂移。
extension BubuSchemaV1 {
    @Model
    final class Comment {
        @Attribute(.unique) var id: UUID
        var remoteId: String?
        var authorRole: String
        var text: String?
        var voiceFileName: String?        // 也可语音补充（姥姥场景）
        var remoteURL: String?            // 语音补充远端 URL
        var voiceDuration: Double = 0
        var voiceWaveform: [Float] = []
        var syncStateRaw: String = SyncState.local.rawValue
        var createdAt: Date
        var entry: Entry?

        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        init(authorRole: String, text: String? = nil) {
            self.id = UUID()
            self.authorRole = authorRole
            self.text = text
            self.createdAt = .now
        }
    }

    @Model
    final class Entry {
        // 全仓此前零索引。fetchLimit 只限制**返回**多少行——没有索引，SQLite 必须扫完
        // 整张表再排序，才知道哪 200 条排最前。今天几千行无感，十年后是每次进时光页都付一遍。
        // 复合索引 (isArchived, happenedAt) 直接对上时光轴那条最热的查询：
        // predicate 过滤未归档 + 按发生时间倒序。
        #Index<Entry>([\.happenedAt], [\.createdAt], [\.isArchived, \.happenedAt])

        @Attribute(.unique) var id: UUID
        var remoteId: String?
        var title: String?
        var note: String?                 // 父母视角原文
        var firstPersonNote: String?      // AI 改写的布布第一人称版本
        var happenedAt: Date              // 事件真实发生时间（非创建时间）
        var locationName: String?
        var latitude: Double?
        var longitude: Double?
        var authorRole: String            // "爸爸"/"妈妈"/"姥姥"
        var moodRaw: String?              // 心情标签（开心/平静/调皮/委屈…）
        var syncStateRaw: String = SyncState.local.rawValue
        var isArchived: Bool = false      // 软删除：永不物理丢失
        var inStorybook: Bool = false     // 用户主动收进「成长绘本」的记录（由你在时光轴/详情勾选）
        var editedAt: Date?               // 最后编辑时间（已上传内容可改可补充）
        var createdAt: Date

        // 关系
        @Relationship(deleteRule: .cascade, inverse: \Media.entry)
        var media: [Media] = []
        @Relationship(deleteRule: .cascade, inverse: \Comment.entry)
        var comments: [Comment] = []      // 家人合奏：多视角补充
        @Relationship(deleteRule: .cascade, inverse: \VoiceNote.entry)
        var voiceNotes: [VoiceNote] = []  // 语音记录（不止文字）
        @Relationship(inverse: \Milestone.entry)
        var milestone: Milestone?
        @Relationship(inverse: \FirstTime.entry)
        var firstTime: FirstTime?

        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        var mood: Mood? {
            get { moodRaw.flatMap(Mood.init(rawValue:)) }
            set { moodRaw = newValue?.rawValue }
        }

        /// media 是 SwiftData 无序关系；按 createdAt 升序稳定排序。
        /// 取封面/首图一律走排序结果，避免 .first 每次启动/同步随机漂移。
        var sortedMedia: [Media] {
            media.filter(\.isDisplayResource).sorted { $0.createdAt < $1.createdAt }
        }

        /// 封面：稳定排序后的第一张（含视频，与既有 .media.first 语义一致，只是不再漂移）。
        var coverMedia: Media? { sortedMedia.first }

        init(happenedAt: Date = .now, authorRole: String, note: String? = nil) {
            self.id = UUID()
            self.happenedAt = happenedAt
            self.authorRole = authorRole
            self.note = note
            self.createdAt = .now
        }
    }

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

    @Model
    final class FeedEvent {
        // 家庭动态永远按时间倒序取最近的一段。
        #Index<FeedEvent>([\.createdAt])

        @Attribute(.unique) var id: UUID
        var kindRaw: String
        var actorRole: String
        var targetLocalId: String?
        var summary: String
        var happenedAt: Date
        var syncStateRaw: String = SyncState.local.rawValue
        var createdAt: Date

        var kind: FeedEventKind {
            get { FeedEventKind(rawValue: kindRaw) ?? .entryCreated }
            set { kindRaw = newValue.rawValue }
        }

        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        init(kind: FeedEventKind, actorRole: String, summary: String, targetLocalId: String? = nil, happenedAt: Date = .now) {
            self.id = UUID()
            self.kindRaw = kind.rawValue
            self.actorRole = actorRole
            self.summary = summary
            self.targetLocalId = targetLocalId
            self.happenedAt = happenedAt
            self.createdAt = .now
        }
    }

    @Model
    final class FirstTime {
        @Attribute(.unique) var id: UUID
        var remoteId: String?
        var what: String                  // "第一次吃西瓜"
        var happenedAt: Date
        var detectedByAI: Bool = false    // 是否由 AI 主动识别
        var confirmedByParent: Bool = false
        var ceremonyPlayed: Bool = false
        var syncStateRaw: String = SyncState.local.rawValue
        var createdAt: Date
        var entry: Entry?

        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        init(what: String, happenedAt: Date = .now) {
            self.id = UUID()
            self.what = what
            self.happenedAt = happenedAt
            self.createdAt = .now
        }
    }

    @Model
    final class GrowthMeasurement {
        @Attribute(.unique) var id: UUID
        var remoteId: String?
        var measuredAt: Date
        var heightCm: Double?
        var weightKg: Double?
        var headCircumferenceCm: Double?
        var note: String?
        /// 来源：manual / ai / checkup
        var sourceRaw: String
        var syncStateRaw: String
        var createdAt: Date
        var updatedAt: Date

        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        init(measuredAt: Date = .now, source: String = "manual") {
            self.id = UUID()
            self.measuredAt = measuredAt
            self.sourceRaw = source
            self.syncStateRaw = SyncState.local.rawValue
            self.createdAt = .now
            self.updatedAt = .now
        }
    }

    @Model
    final class GrowthMovie {
        @Attribute(.unique) var id: UUID
        var remoteId: String?
        var year: Int                     // 对应哪一岁
        var remoteURL: String?            // 服务端生成的成片
        var status: String                // pending / generating / ready / failed
        var narrationScript: String?      // AI 旁白稿
        var createdAt: Date

        init(year: Int) {
            self.id = UUID()
            self.year = year
            self.status = "pending"
            self.createdAt = .now
        }
    }

    @Model
    final class HealthRecord {
        // 喂养/睡眠/喝水是日打卡，三年就是上万行，而健康页按 recordedAt 排序取全表。
        #Index<HealthRecord>([\.recordedAt], [\.kindRaw, \.recordedAt])

        @Attribute(.unique) var id: UUID
        var remoteId: String?
        var kindRaw: String
        var title: String
        var detail: String?
        var recordedAt: Date
        var amountText: String?
        var reaction: String?
        var amountValue: Double?
        var amountUnit: String?
        var startAt: Date?
        var endAt: Date?
        var severityRaw: String?
        var temperatureCelsius: Double?
        var tags: [String] = []
        /// 本机稳定关联到这次体检生成的成长测量。旧数据为 nil 时会按同日体检记录回填。
        /// 这是纯 additive 可选字段，不改变既有数据，也不要求破坏性迁移。
        var growthMeasurementId: UUID?
        var syncStateRaw: String = SyncState.local.rawValue
        var createdAt: Date

        var kind: HealthRecordKind {
            get { HealthRecordKind(rawValue: kindRaw) ?? .meal }
            set { kindRaw = newValue.rawValue }
        }

        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        init(kind: HealthRecordKind, title: String, recordedAt: Date = .now) {
            self.id = UUID()
            self.kindRaw = kind.rawValue
            self.title = title
            self.recordedAt = recordedAt
            self.createdAt = .now
        }
    }

    @Model
    final class Media {
        @Attribute(.unique) var id: UUID
        var remoteId: String?
        var typeRaw: String               // photo / video / audio
        var localFileName: String?        // 沙盒相对路径
        var remoteURL: String?            // PocketBase file url
        var thumbnailFileName: String?
        /// 服务端缩略图 URL（media.thumbnail file 字段）。V2 新增：
        /// 视频的预览图靠它——接收端不用下完整个视频就能出预览。
        var remoteThumbURL: String?
        /// 文件内容 SHA256（十六进制）。V2 新增：导入时计算，拦截同一文件被重复收录。
        var contentHash: String?
        /// PhotoKit 资源版本：display / original / live-paired。可选字段，老数据默认展示。
        var resourceRoleRaw: String?
        /// 同一系统相册资产的稳定分组 ID（当前图、原图、Live Photo 动态资源共用）。
        var assetGroupID: String?
        var durationSeconds: Double?      // 视频/音频时长
        var width: Int?
        var height: Int?
        var uploadProgress: Double = 0    // 0...1，UI 进度条
        var syncStateRaw: String = SyncState.local.rawValue
        var aiTags: [String] = []         // AI 视觉打标
        var createdAt: Date

        var entry: Entry?

        var type: MediaType { MediaType(rawValue: typeRaw) ?? .photo }
        /// 老记录没有角色，仍按普通素材展示；系统后台额外保存的原图/Live 动态资源
        /// 只用于传家宝保真与导出，不在时光流里重复出现。
        var isDisplayResource: Bool {
            guard let role = resourceRoleRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !role.isEmpty else { return true }
            return role == "display"
        }
        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        init(type: MediaType, localFileName: String?) {
            self.id = UUID()
            self.typeRaw = type.rawValue
            self.localFileName = localFileName
            self.createdAt = .now
        }
    }

    @Model
    final class Milestone {
        @Attribute(.unique) var id: UUID
        var remoteId: String?
        var title: String                 // "第一次独立行走"
        var category: String              // 大运动/语言/社交/认知…
        var emoji: String = "🌟"          // 成就墙图标
        var detail: String?               // 描述/当时的故事
        var happenedAt: Date?             // nil = 尚未达成（待解锁）
        var ageDescription: String?       // "1岁11个月" 自动计算展示
        var isCustom: Bool = false        // 是否用户自定义（非预设）
        var ceremonyPlayed: Bool = false  // 是否已播放仪式动画
        var syncStateRaw: String = SyncState.local.rawValue
        var createdAt: Date
        var entry: Entry?

        /// 是否已达成。
        var isAchieved: Bool { happenedAt != nil }
        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        /// 同标题去重时的保留优先级。**必须是确定性的**：
        /// 旧实现里混了一项 `min(19, 距创建天数)`，两条近乎相同的里程碑在第 19 天之后同时封顶，
        /// 胜负改由无排序 fetch 的行序决定——而输的那条是被物理删除的，不可逆。
        /// 现在只用记录自身的稳定属性打分，平局再按「先创建的赢」这个稳定次序裁决。
        var dedupeRank: Int {
            (isAchieved ? 1_000 : 0)
            + ((detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 200 : 0)
            + (isCustom ? 100 : 0)
            + (remoteId == nil ? 0 : 20)
        }

        /// `lhs` 是否应当被保留（`rhs` 被删）。全序、与时间无关、与 fetch 顺序无关。
        static func prefersKeeping(_ lhs: Milestone, over rhs: Milestone) -> Bool {
            if lhs.dedupeRank != rhs.dedupeRank { return lhs.dedupeRank > rhs.dedupeRank }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        init(title: String, category: String, emoji: String = "🌟",
             happenedAt: Date? = nil, isCustom: Bool = false) {
            self.id = UUID()
            self.title = title
            self.category = category
            self.emoji = emoji
            self.happenedAt = happenedAt
            self.isCustom = isCustom
            self.createdAt = .now
        }
    }

    @Model
    final class PendingDeletion {
        @Attribute(.unique) var id: UUID
        /// PocketBase collection 名，如 "vaccinerecords"。
        var collection: String
        var remoteId: String
        var createdAt: Date

        init(collection: String, remoteId: String) {
            self.id = UUID()
            self.collection = collection
            self.remoteId = remoteId
            self.createdAt = .now
        }

        static func enqueue(collection: String, remoteId: String?, in context: ModelContext) {
            guard let remoteId, !remoteId.isEmpty else { return }
            let existing = (try? context.fetch(FetchDescriptor<PendingDeletion>())) ?? []
            guard !existing.contains(where: { $0.collection == collection && $0.remoteId == remoteId }) else { return }
            context.insert(PendingDeletion(collection: collection, remoteId: remoteId))
        }
    }

    @Model
    final class TimeCapsule {
        @Attribute(.unique) var id: UUID
        var remoteId: String?
        var title: String
        var fromRole: String              // 谁写的
        var unlockAt: Date                // 解锁时间，如 18 岁生日
        var isLocked: Bool = true
        var encryptedBlobFileName: String? // 本地加密文件（信件文本+音视频）
        var coverEmoji: String?
        /// 这封信封存时用的加密版本（3 = BTC3 真 E2E）。可选：老数据为 nil，
        /// 首次成功解开时按实际 blob 头回填。
        ///
        /// 为什么必须有：`unseal` 完全按 blob 头部魔数分派版本，而 v2 的密钥只由
        /// `unlockAt` 与 `salt`(=胶囊 id) 派生——两个都是随记录同步到服务器的**明文字段**。
        /// 拿到数据库或备份的人可以自己派生 v2 密钥、封一段自己写的正文、加 BTC2 前缀替换上去，
        /// 换机后同步拉回本地，解封认魔数就成功了：密钥公开时 AES-GCM 的完整性校验形同虚设。
        /// 布布 18 岁打开的会是别人写的信，而界面上没有任何异常。
        /// 记住版本之后，v3 的信就不再接受任何降级的 blob。
        var cryptoVersion: Int?
        var syncStateRaw: String = SyncState.local.rawValue
        var createdAt: Date

        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        init(title: String, fromRole: String, unlockAt: Date) {
            self.id = UUID()
            self.title = title
            self.fromRole = fromRole
            self.unlockAt = unlockAt
            self.createdAt = .now
        }
    }

    @Model
    final class VaccineRecord {
        @Attribute(.unique) var id: UUID
        var remoteId: String?
        /// 对应 VaccineDose.schedule 的剂次 id（如 "HepB-1"）；自由疫苗记录可为空。
        var doseId: String?
        var vaccineName: String
        var doseLabel: String?
        var injectedAt: Date
        var hospital: String?
        var injectionSite: String?
        var reaction: String?
        var note: String?
        /// 来源：manual（手动打卡）/ ai（自然语言归档）/ migration（旧打卡迁移）
        var sourceRaw: String
        var syncStateRaw: String
        var createdAt: Date
        var updatedAt: Date

        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        init(vaccineName: String, injectedAt: Date, source: String = "manual") {
            self.id = UUID()
            self.vaccineName = vaccineName
            self.injectedAt = injectedAt
            self.sourceRaw = source
            self.syncStateRaw = SyncState.local.rawValue
            self.createdAt = .now
            self.updatedAt = .now
        }
    }

    @Model
    final class VoiceMemo {
        @Attribute(.unique) var id: UUID
        var remoteId: String?
        var kindRaw: String               // childVoice（她的声音）/ familyVoice（对她说）
        var localFileName: String?
        var remoteURL: String?
        var transcript: String?           // Whisper 转写
        var ageYears: Int?                 // 录制时她的年龄，自动归档
        var recordedAt: Date
        var durationSeconds: Double?
        var syncStateRaw: String = SyncState.local.rawValue
        var createdAt: Date

        enum Kind: String, Codable, Sendable { case childVoice, familyVoice }
        var kind: Kind { Kind(rawValue: kindRaw) ?? .childVoice }
        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        init(kind: Kind, recordedAt: Date = .now) {
            self.id = UUID()
            self.kindRaw = kind.rawValue
            self.recordedAt = recordedAt
            self.createdAt = .now
        }
    }

    @Model
    final class VoiceNote {
        @Attribute(.unique) var id: UUID
        var remoteId: String?
        var localFileName: String?        // 沙盒相对路径（.m4a）
        var remoteURL: String?
        var durationSeconds: Double = 0
        var transcript: String?           // 预留：将来 Whisper 转写
        var authorRole: String            // 谁录的
        var waveformSamples: [Float] = []  // 波形可视化采样（0...1）
        var syncStateRaw: String = SyncState.local.rawValue
        var createdAt: Date

        var entry: Entry?

        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        init(localFileName: String?, durationSeconds: Double, authorRole: String,
             waveformSamples: [Float] = []) {
            self.id = UUID()
            self.localFileName = localFileName
            self.durationSeconds = durationSeconds
            self.authorRole = authorRole
            self.waveformSamples = waveformSamples
            self.createdAt = .now
        }
    }
}
