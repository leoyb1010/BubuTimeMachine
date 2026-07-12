import Foundation
import SwiftData

// MARK: - 旧版疫苗打卡迁移
/// @AppStorage("bubu.vaccine.done") JSON 数组 → 结构化 VaccineRecord，一次性执行。
/// 独立成类型以便单测（注入内存容器与独立 UserDefaults suite）。
/// 幂等：migrated 标记防重入；保留旧键以便回滚；接种日取排期 dueDate（不晚于今天），note 标注待确认。
enum VaccineLegacyMigrator {
    static let migratedKey = "bubu.vaccine.migrated"
    static let legacyKey = "bubu.vaccine.done"

    /// 独立入口（单测/回滚兼容）：自带 migratedKey 幂等保护。
    /// 修复点：只有 `context.save()` 成功后才置迁移标记——
    /// 旧代码用 `defer` 在 save 之前就注定落标记，save 失败也算已迁移 → 旧打卡永久丢失。
    @MainActor
    static func migrateIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        do {
            try perform(context: context, defaults: defaults)
            defaults.set(true, forKey: migratedKey)
        } catch {
            // save 失败：不置标记，下次重试，保住旧打卡数据。
        }
    }

    /// 迁移框架入口：执行迁移，save 失败抛出 → DataMigrationRunner 不落完成标记、下次重试。
    /// 幂等：按 doseId 去重，重复执行不会产生重复 VaccineRecord。
    @MainActor
    static func perform(context: ModelContext, defaults: UserDefaults = .standard) throws {
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
        try context.save()
    }
}
