import Foundation
import SwiftData

// MARK: - 旧版疫苗打卡迁移
/// @AppStorage("bubu.vaccine.done") JSON 数组 → 结构化 VaccineRecord，一次性执行。
/// 独立成类型以便单测（注入内存容器与独立 UserDefaults suite）。
/// 幂等：migrated 标记防重入；保留旧键以便回滚；接种日取排期 dueDate（不晚于今天），note 标注待确认。
enum VaccineLegacyMigrator {
    static let migratedKey = "bubu.vaccine.migrated"
    static let legacyKey = "bubu.vaccine.done"

    @MainActor
    static func migrateIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        defer { defaults.set(true, forKey: migratedKey) }

        guard let raw = defaults.string(forKey: legacyKey),
              let data = raw.data(using: .utf8),
              let doseIds = try? JSONDecoder().decode([String].self, from: data),
              !doseIds.isEmpty else { return }

        let existing = (try? context.fetch(FetchDescriptor<VaccineRecord>())) ?? []
        let existingDoseIds = Set(existing.compactMap(\.doseId))
        let birthday = ((try? context.fetch(FetchDescriptor<ChildProfile>())) ?? []).first?.birthday

        for doseId in doseIds where !existingDoseIds.contains(doseId) {
            guard let dose = VaccineDose.schedule.first(where: { $0.id == doseId }) else { continue }
            let due = birthday.map { dose.dueDate(birthday: $0) } ?? .now
            let record = VaccineRecord(vaccineName: dose.vaccine,
                                       injectedAt: min(due, .now),
                                       source: "migration")
            record.doseId = dose.id
            record.doseLabel = dose.doseLabel
            record.note = "从旧版打卡迁移，具体接种日期请家长确认"
            context.insert(record)
        }
        try? context.save()
    }
}
