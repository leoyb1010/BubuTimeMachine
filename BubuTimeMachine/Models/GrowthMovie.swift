import SwiftData
import Foundation

// MARK: - GrowthMovie（年度成长电影：每年生日自动生成）
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
