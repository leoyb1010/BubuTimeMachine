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

// MARK: - 成长数值统一取值口径

/// 首页、成长曲线与小组件共用的“哪条才是最新值”选择器。
///
/// 历史迁移可能为同一天生成 `legacy-health` / `health-fallback` 派生记录；用户后来编辑
/// 正式体检时，两者的秒级时间可能前后交错。若只按 `measuredAt` 精确秒排序，旧派生值会
/// 盖住刚保存的新值。统一规则：先看测量日期；同一天优先正式结构化来源，再看更新时间。
enum GrowthMeasurementResolver {
    enum Metric: Sendable {
        case height
        case weight
        case head
    }

    private struct Candidate {
        let id: String
        let measuredAt: Date
        let updatedAt: Date
        let createdAt: Date
        let source: String
        let value: Double
    }

    static func latestValue(
        _ metric: Metric,
        from measurements: [GrowthMeasurement],
        calendar: Calendar = .current
    ) -> Double? {
        candidates(metric, from: measurements)
            .sorted { isPreferred($0, over: $1, calendar: calendar) }
            .first?.value
    }

    /// 成长曲线每个月龄只画一个点；跨日取该月最新，同一天仍按正式来源优先。
    static func valuesByMonth(
        _ metric: Metric,
        birthday: Date,
        measurements: [GrowthMeasurement],
        calendar: Calendar = .current
    ) -> [Int: Double] {
        var grouped: [Int: [Candidate]] = [:]
        for candidate in candidates(metric, from: measurements) {
            let month = calendar.dateComponents(
                [.month], from: birthday, to: candidate.measuredAt
            ).month ?? 0
            guard month >= 0, month <= 60 else { continue }
            grouped[month, default: []].append(candidate)
        }
        return grouped.reduce(into: [:]) { result, item in
            result[item.key] = item.value
                .sorted { isPreferred($0, over: $1, calendar: calendar) }
                .first?.value
        }
    }

    private static func candidates(
        _ metric: Metric,
        from measurements: [GrowthMeasurement]
    ) -> [Candidate] {
        measurements.compactMap { item in
            let value: Double?
            switch metric {
            case .height: value = item.heightCm
            case .weight: value = item.weightKg
            case .head: value = item.headCircumferenceCm
            }
            guard let value else { return nil }
            return Candidate(
                id: item.id.uuidString,
                measuredAt: item.measuredAt,
                updatedAt: item.updatedAt,
                createdAt: item.createdAt,
                source: item.sourceRaw,
                value: value
            )
        }
    }

    private static func isPreferred(
        _ lhs: Candidate,
        over rhs: Candidate,
        calendar: Calendar
    ) -> Bool {
        let lhsDay = calendar.startOfDay(for: lhs.measuredAt)
        let rhsDay = calendar.startOfDay(for: rhs.measuredAt)
        if lhsDay != rhsDay { return lhsDay > rhsDay }

        let lhsPriority = sourcePriority(lhs.source)
        let rhsPriority = sourcePriority(rhs.source)
        if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.measuredAt != rhs.measuredAt { return lhs.measuredAt > rhs.measuredAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id < rhs.id
    }

    private static func sourcePriority(_ source: String) -> Int {
        switch source {
        case "checkup", "manual": 3
        case "ai": 2
        case "legacy-health", "health-fallback": 0
        default: 1
        }
    }
}
