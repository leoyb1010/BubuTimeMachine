import Foundation
import SwiftData

// MARK: - 健康记录
@Model
final class HealthRecord {
    @Attribute(.unique) var id: UUID
    var remoteId: String?
    var kindRaw: String
    var title: String
    var detail: String?
    var recordedAt: Date
    var amountText: String?
    var reaction: String?
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

enum HealthRecordKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case meal
    case snack
    case supplement
    case water
    case sleep
    case symptom
    case checkup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meal: return "餐食"
        case .snack: return "零食"
        case .supplement: return "营养补充"
        case .water: return "喝水"
        case .sleep: return "睡眠"
        case .symptom: return "不舒服"
        case .checkup: return "体检护理"
        }
    }

    var icon: String {
        switch self {
        case .meal: return "fork.knife"
        case .snack: return "takeoutbag.and.cup.and.straw"
        case .supplement: return "pills"
        case .water: return "drop.fill"
        case .sleep: return "moon.zzz.fill"
        case .symptom: return "cross.case.fill"
        case .checkup: return "stethoscope"
        }
    }

    var emoji: String {
        switch self {
        case .meal: return "🍚"
        case .snack: return "🍓"
        case .supplement: return "💊"
        case .water: return "💧"
        case .sleep: return "🌙"
        case .symptom: return "🌡️"
        case .checkup: return "🩺"
        }
    }

    var placeholder: String {
        switch self {
        case .meal: return "如：早餐小米粥 + 鸡蛋羹"
        case .snack: return "如：苹果块、酸奶"
        case .supplement: return "如：维D、钙、益生菌"
        case .water: return "如：温水"
        case .sleep: return "如：午睡"
        case .symptom: return "如：流鼻涕、咳嗽、肚子不舒服"
        case .checkup: return "如：身高体重、疫苗、牙齿护理"
        }
    }
}
