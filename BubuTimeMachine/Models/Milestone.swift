import SwiftData
import Foundation

// MARK: - Milestone（里程碑：会走路、第一次叫妈妈…强仪式感）
/// 可从预设模板库选，也可完全自定义。已达成/待达成都在成就墙呈现。
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
    var createdAt: Date
    var entry: Entry?

    /// 是否已达成。
    var isAchieved: Bool { happenedAt != nil }

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

// MARK: - 里程碑预设库
/// 出厂内置的成长里程碑，按发展领域分类。用户可一键添加并标记达成。
struct MilestoneTemplate: Identifiable, Hashable, Sendable {
    let id = UUID()
    let title: String
    let category: String
    let emoji: String

    static let categories = ["大运动", "精细动作", "语言", "社交情感", "认知", "生活自理"]

    static let presets: [MilestoneTemplate] = [
        // 大运动
        .init(title: "第一次抬头", category: "大运动", emoji: "🐣"),
        .init(title: "第一次翻身", category: "大运动", emoji: "🔄"),
        .init(title: "第一次独坐", category: "大运动", emoji: "🪑"),
        .init(title: "第一次爬行", category: "大运动", emoji: "🐛"),
        .init(title: "第一次站立", category: "大运动", emoji: "🧍"),
        .init(title: "第一次独立行走", category: "大运动", emoji: "👣"),
        .init(title: "第一次奔跑", category: "大运动", emoji: "🏃"),
        // 精细动作
        .init(title: "第一次抓握", category: "精细动作", emoji: "✋"),
        .init(title: "第一次自己拿勺", category: "精细动作", emoji: "🥄"),
        .init(title: "第一次涂鸦", category: "精细动作", emoji: "🖍️"),
        // 语言
        .init(title: "第一次叫妈妈", category: "语言", emoji: "🗣️"),
        .init(title: "第一次叫爸爸", category: "语言", emoji: "🗣️"),
        .init(title: "第一次说完整句子", category: "语言", emoji: "💬"),
        .init(title: "第一次唱歌", category: "语言", emoji: "🎵"),
        // 社交情感
        .init(title: "第一次微笑", category: "社交情感", emoji: "😊"),
        .init(title: "第一次大笑", category: "社交情感", emoji: "😆"),
        .init(title: "第一次认生", category: "社交情感", emoji: "🫣"),
        .init(title: "第一次和小朋友玩", category: "社交情感", emoji: "🧒"),
        // 认知
        .init(title: "第一次认出镜子里的自己", category: "认知", emoji: "🪞"),
        .init(title: "第一次数数", category: "认知", emoji: "🔢"),
        .init(title: "第一次认颜色", category: "认知", emoji: "🌈"),
        // 生活自理
        .init(title: "第一次自己吃饭", category: "生活自理", emoji: "🍚"),
        .init(title: "第一次自己穿鞋", category: "生活自理", emoji: "👟"),
        .init(title: "第一次戒纸尿裤", category: "生活自理", emoji: "🚽"),
        .init(title: "第一次自己刷牙", category: "生活自理", emoji: "🪥"),
    ]
}
