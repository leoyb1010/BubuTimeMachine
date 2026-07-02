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

    @MainActor
    static func run(
        context: ModelContext,
        insertedSyncState: SyncState = .local,
        source: String = "legacy-health"
    ) {
        let records = (try? context.fetch(FetchDescriptor<HealthRecord>(
            sortBy: [SortDescriptor(\.recordedAt)]
        ))) ?? []
        guard !records.isEmpty else { return }

        var measurements = (try? context.fetch(FetchDescriptor<GrowthMeasurement>(
            sortBy: [SortDescriptor(\.measuredAt)]
        ))) ?? []
        var inserted = 0
        let calendar = Calendar.current

        for record in records {
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

        guard inserted > 0 else { return }
        do {
            try context.save()
            log.notice("已补齐旧成长数据 \(inserted, privacy: .public) 条")
        } catch {
            log.error("补齐旧成长数据失败：\(error.localizedDescription, privacy: .public)")
        }
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
