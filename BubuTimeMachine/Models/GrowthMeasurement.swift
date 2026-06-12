import Foundation
import SwiftData

// MARK: - 成长测量（结构化）
/// 身高/体重/头围不再塞 HealthRecord 文本：成长曲线直接读数值，可同步、可导出。
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
