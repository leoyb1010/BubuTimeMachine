import Foundation

// MARK: - 手表 ↔ 手机 通信契约（两端共同编译）
/// Watch 是瘦客户端：不跑 SwiftData / 同步，只把「记录意图」发给 iPhone，并显示 iPhone 推来的快照。
/// 所有跨端类型集中在此文件，保证序列化一致。用 WatchConnectivity 传输（dictionary / userInfo / file）。

/// iPhone → Watch：概览快照（抬腕即见）。
public nonisolated struct WatchSnapshot: Codable, Sendable {
    public var childName: String
    public var birthday: Date?
    /// 当前署名身份（手表记录时沿用）。
    public var roleRaw: String
    public var achievedMilestones: Int
    public var totalMilestones: Int
    public var recent: [WatchRecent]
    /// 布布头像小缩略图（<30KB，抬腕看到她的脸）。可空。
    public var avatarData: Data?
    public var updatedAt: Date

    // MARK: v2 追加字段
    // 全部可选：旧版 iPhone 推来的 v1 快照解码后这些是 nil，手表侧降级成纯文字，不崩不空白。
    // 反之新版 iPhone 配旧版手表，多出来的键被 JSONDecoder 忽略。两个方向都不需要版本号协商。

    /// 表冠时光机的回忆序列（约 20 段）。照片不在这里，只带文件名，图走 transferFile。
    public var memories: [WatchMemory]?
    /// 今天各类打卡次数，key = HealthRecordKind.rawValue 或 "diaper"。打卡按钮角标用。
    public var todayStats: [String: Int]?
    /// 哄睡进行中的起始时刻。非 nil 时打卡页「睡觉」进入呼吸态并显示已睡时长。
    public var sleepingSince: Date?

    public init(childName: String, birthday: Date?, roleRaw: String,
                achievedMilestones: Int, totalMilestones: Int,
                recent: [WatchRecent], avatarData: Data? = nil, updatedAt: Date,
                memories: [WatchMemory]? = nil, todayStats: [String: Int]? = nil,
                sleepingSince: Date? = nil) {
        self.childName = childName
        self.birthday = birthday
        self.roleRaw = roleRaw
        self.achievedMilestones = achievedMilestones
        self.totalMilestones = totalMilestones
        self.recent = recent
        self.avatarData = avatarData
        self.updatedAt = updatedAt
        self.memories = memories
        self.todayStats = todayStats
        self.sleepingSince = sleepingSince
    }
}

// MARK: - 一段回忆（表冠时光机的一格）
/// 照片不塞在这里：元数据小而频（走 applicationContext），照片大而稀（走 transferFile），
/// 两个通道解耦。手表侧按 photoFileName 去本地缓存取图，取不到就只显示文字。
public nonisolated struct WatchMemory: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    /// 手机侧格式化好的日期，如「7月28日」。手表不做本地化计算。
    public var dateText: String
    /// 一句话摘要。
    public var note: String
    /// 布布在**那一天**多大，如「1岁10个月」。时光机的重点是对比当时与现在。
    public var ageText: String
    /// 是否「那年今日」——同月同日的旧记录。手表侧打金徽章 + 双震。
    public var isOnThisDay: Bool
    /// 心情 emoji。
    public var moodEmoji: String?
    /// 照片在手表本地缓存里的文件名。nil = 这段回忆没有照片。
    public var photoFileName: String?

    public init(id: String, dateText: String, note: String, ageText: String,
                isOnThisDay: Bool = false, moodEmoji: String? = nil, photoFileName: String? = nil) {
        self.id = id
        self.dateText = dateText
        self.note = note
        self.ageText = ageText
        self.isOnThisDay = isOnThisDay
        self.moodEmoji = moodEmoji
        self.photoFileName = photoFileName
    }
}

/// 最近一条时光（手表列表用，日期在手机侧格式化好）。
public nonisolated struct WatchRecent: Codable, Sendable, Identifiable {
    public var id: String
    public var dateText: String
    public var note: String
    public var moodEmoji: String?
    /// v2：这条动态对应的照片（手表缓存 key）。可选，v1 兼容。
    public var photoFileName: String?

    public init(id: String, dateText: String, note: String, moodEmoji: String?,
                photoFileName: String? = nil) {
        self.id = id
        self.dateText = dateText
        self.note = note
        self.moodEmoji = moodEmoji
        self.photoFileName = photoFileName
    }
}

/// Watch → iPhone：一次记录意图的类型。
public nonisolated enum WatchRecordType: String, Codable, Sendable {
    case text     // 文字（口述/预置）
    case mood     // 心情快记
    case health   // 喝奶/睡觉等健康打卡
    case voice    // 语音（文件另经 transferFile 送达）
    /// 撤销刚才那一条（带原 localId）。打卡卡片翻面期间再点一次即撤销，防手滑。
    case undo
    /// 哄睡开始/结束：与 iPhone 健康页的哄睡计时同一套状态（SharedDefaults.sleepStartedAt），
    /// 手表和手机谁先点都行，另一端看到的是同一场睡眠。
    case sleepStart
    case sleepEnd
    /// 在时光机里重温某条 → 给它点一个「亲亲」（note 承载目标 Entry 的 UUID 字符串）。
    /// 落到 App 已有的 Reaction 机制上，不产生新的时光轴记录。
    case reaction
}

/// Watch → iPhone：一次记录意图。localId 幂等，重发不重复。
public nonisolated struct WatchRecordRequest: Codable, Sendable {
    public var type: WatchRecordType
    public var localId: String
    public var roleRaw: String
    public var note: String?
    public var moodRaw: String?
    public var healthKindRaw: String?
    public var healthTitle: String?
    public var voiceFileName: String?
    public var voiceDuration: Double?
    public var happenedAt: Date

    public init(type: WatchRecordType, localId: String = UUID().uuidString,
                roleRaw: String, note: String? = nil, moodRaw: String? = nil,
                healthKindRaw: String? = nil, healthTitle: String? = nil,
                voiceFileName: String? = nil, voiceDuration: Double? = nil,
                happenedAt: Date = Date()) {
        self.type = type
        self.localId = localId
        self.roleRaw = roleRaw
        self.note = note
        self.moodRaw = moodRaw
        self.healthKindRaw = healthKindRaw
        self.healthTitle = healthTitle
        self.voiceFileName = voiceFileName
        self.voiceDuration = voiceDuration
        self.happenedAt = happenedAt
    }
}

// MARK: - WatchConnectivity 传输键 / 编解码
public nonisolated enum WatchLink {
    /// applicationContext / message 里承载快照或记录的键。
    public static let snapshotKey = "bubu.watch.snapshot"
    public static let recordKey = "bubu.watch.record"
    /// transferFile 的 metadata 里承载语音记录意图（JSON 字符串）。
    public static let fileMetaKey = "bubu.watch.record.json"
    /// transferFile 的 metadata 标记「这是回忆照片包」，值为包内文件名集合的指纹。
    public static let photoBundleKey = "bubu.watch.photobundle"
    /// 手表 → 手机：「我的照片缓存缺图，请重发照片包」。手表重装/缓存被清后，
    /// 手机侧的指纹去重会以为已经发过——这条消息是打破僵局的唯一通道。
    public static let photoBundleRequestKey = "bubu.watch.photobundle.request"

    public static func encode<T: Encodable>(_ value: T) -> Data? {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return try? enc.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(type, from: data)
    }
}
