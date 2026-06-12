import Foundation
import SwiftData

// MARK: - 疫苗接种记录（结构化）
/// 取代旧 @AppStorage("bubu.vaccine.done") 打卡：可记录日期/医院/反应，可家庭同步，可被 AI 自动归档。
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
