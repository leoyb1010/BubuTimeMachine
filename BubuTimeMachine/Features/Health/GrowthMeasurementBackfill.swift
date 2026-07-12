import Foundation
import OSLog
import SwiftData

extension GrowthMeasurementExtractor.Metric {
    init(_ metric: WHOGrowthStandard.Metric) {
        switch metric {
        case .height: self = .height
        case .weight: self = .weight
        case .head: self = .head
        }
    }
}

extension GrowthMeasurementExtractor.Values {
    func value(for metric: WHOGrowthStandard.Metric) -> Double? {
        value(for: GrowthMeasurementExtractor.Metric(metric))
    }
}

extension GrowthMeasurementExtractor {
    static func value(_ metric: WHOGrowthStandard.Metric, from record: HealthRecord) -> Double? {
        value(Metric(metric), from: record)
    }
}

enum GrowthMeasurementBackfill {
    private static let log = Logger(subsystem: "com.bubu.timemachine", category: "GrowthMeasurementBackfill")

    /// 已处理过的 HealthRecord id 集合（持久化在 UserDefaults，不改 SwiftData schema）。
    /// 「回填只处理未处理过的记录」的核心：一条记录处理过后 id 入集，即使用户随后
    /// 删除/修正了自动生成的测量，也不会因为再次扫描而复活或重复插入。
    static let processedKey = "bubu.growthBackfill.processedRecordIds"

    /// 迁移框架入口：成功即返回，save 失败抛出 → DataMigrationRunner 不落完成标记、下次重试。
    @MainActor
    static func perform(context: ModelContext, defaults: UserDefaults = .standard) throws {
        try backfill(context: context, defaults: defaults)
    }

    /// 非抛出入口，供同步兜底（SyncEngine health-fallback）等 fire-and-forget 路径调用。
    /// 与 `perform` 共用同一套「已处理 id 集合」，因此不会重复插入、也不会复活已删测量。
    @MainActor
    static func run(
        context: ModelContext,
        insertedSyncState: SyncState = .local,
        source: String = "legacy-health",
        defaults: UserDefaults = .standard
    ) {
        do {
            try backfill(context: context, insertedSyncState: insertedSyncState, source: source, defaults: defaults)
        } catch {
            log.error("补齐旧成长数据失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private static func backfill(
        context: ModelContext,
        insertedSyncState: SyncState = .local,
        source: String = "legacy-health",
        defaults: UserDefaults
    ) throws {
        let records = (try? context.fetch(FetchDescriptor<HealthRecord>(
            sortBy: [SortDescriptor(\.recordedAt)]
        ))) ?? []
        guard !records.isEmpty else { return }

        var processed = Set(defaults.stringArray(forKey: processedKey) ?? [])
        let pending = records.filter { !processed.contains($0.id.uuidString) }
        guard !pending.isEmpty else { return }

        var measurements = (try? context.fetch(FetchDescriptor<GrowthMeasurement>(
            sortBy: [SortDescriptor(\.measuredAt)]
        ))) ?? []
        var inserted = 0
        let calendar = Calendar.current

        for record in pending {
            // 无论是否产出测量，都标记为已处理：空记录/已覆盖的记录下次不再重复扫描。
            processed.insert(record.id.uuidString)

            let values = GrowthMeasurementExtractor.values(from: record)
            guard !values.isEmpty else { continue }
            guard !isCovered(values, at: record.recordedAt, by: measurements, calendar: calendar) else { continue }

            let measurement = GrowthMeasurement(measuredAt: record.recordedAt, source: source)
            measurement.heightCm = values.heightCm
            measurement.weightKg = values.weightKg
            measurement.headCircumferenceCm = values.headCircumferenceCm
            measurement.note = [record.title, record.detail].compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }.joined(separator: " · ")
            measurement.syncState = insertedSyncState
            context.insert(measurement)
            measurements.append(measurement)
            inserted += 1
        }

        // 先落库、后记「已处理」：save 抛出时不更新已处理集合 → 本轮记录下次重试，绝不丢数据。
        if inserted > 0 {
            try context.save()
            log.notice("已补齐旧成长数据 \(inserted, privacy: .public) 条")
        }
        defaults.set(Array(processed), forKey: processedKey)
    }

    private static func isCovered(
        _ values: GrowthMeasurementExtractor.Values,
        at date: Date,
        by measurements: [GrowthMeasurement],
        calendar: Calendar
    ) -> Bool {
        measurements.contains { measurement in
            guard calendar.isDate(measurement.measuredAt, inSameDayAs: date) else { return false }
            if let height = values.heightCm,
               measurement.heightCm.map({ abs($0 - height) < 0.05 }) != true {
                return false
            }
            if let weight = values.weightKg,
               measurement.weightKg.map({ abs($0 - weight) < 0.05 }) != true {
                return false
            }
            if let head = values.headCircumferenceCm,
               measurement.headCircumferenceCm.map({ abs($0 - head) < 0.05 }) != true {
                return false
            }
            return true
        }
    }
}
