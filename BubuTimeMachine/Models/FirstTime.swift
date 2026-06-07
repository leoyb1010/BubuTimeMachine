import SwiftData
import Foundation

// MARK: - FirstTime（人生第一次：上传时 AI 主动询问"这是第一次吗"）
@Model
final class FirstTime {
    @Attribute(.unique) var id: UUID
    var remoteId: String?
    var what: String                  // "第一次吃西瓜"
    var happenedAt: Date
    var detectedByAI: Bool = false    // 是否由 AI 主动识别
    var confirmedByParent: Bool = false
    var ceremonyPlayed: Bool = false
    var createdAt: Date
    var entry: Entry?

    init(what: String, happenedAt: Date = .now) {
        self.id = UUID()
        self.what = what
        self.happenedAt = happenedAt
        self.createdAt = .now
    }
}
