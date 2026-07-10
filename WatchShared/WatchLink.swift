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

    public init(childName: String, birthday: Date?, roleRaw: String,
                achievedMilestones: Int, totalMilestones: Int,
                recent: [WatchRecent], avatarData: Data? = nil, updatedAt: Date) {
        self.childName = childName
        self.birthday = birthday
        self.roleRaw = roleRaw
        self.achievedMilestones = achievedMilestones
        self.totalMilestones = totalMilestones
        self.recent = recent
        self.avatarData = avatarData
        self.updatedAt = updatedAt
    }
}

/// 最近一条时光（手表列表用，日期在手机侧格式化好）。
public nonisolated struct WatchRecent: Codable, Sendable, Identifiable {
    public var id: String
    public var dateText: String
    public var note: String
    public var moodEmoji: String?

    public init(id: String, dateText: String, note: String, moodEmoji: String?) {
        self.id = id
        self.dateText = dateText
        self.note = note
        self.moodEmoji = moodEmoji
    }
}

/// Watch → iPhone：一次记录意图的类型。
public nonisolated enum WatchRecordType: String, Codable, Sendable {
    case text     // 文字（口述/预置）
    case mood     // 心情快记
    case health   // 喝奶/睡觉等健康打卡
    case voice    // 语音（文件另经 transferFile 送达）
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
