import SwiftData
import Foundation

// MARK: - Milestone（里程碑：会走路、第一次叫妈妈…强仪式感）
@Model
final class Milestone {
    @Attribute(.unique) var id: UUID
    var remoteId: String?
    var title: String                 // "第一次独立行走"
    var category: String              // 大运动/语言/社交/认知…
    var happenedAt: Date
    var ageDescription: String?       // "1岁11个月" 自动计算展示
    var ceremonyPlayed: Bool = false  // 是否已播放仪式动画
    var createdAt: Date
    var entry: Entry?

    init(title: String, category: String, happenedAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.category = category
        self.happenedAt = happenedAt
        self.createdAt = .now
    }
}
