import Foundation
import SwiftData

// MARK: - 自然语言记录 → 各模块落库路由
/// LLM 解析结果经用户确认后，由这里写入对应 SwiftData 模型并产生 FeedEvent。
/// 原则：不确定就降级为普通时光记录，绝不编造字段。
@MainActor
struct NaturalCaptureRouter {
    let context: ModelContext
    let env: AppEnvironment

    func save(_ item: NaturalCaptureItem) {
        switch item.domain {
        case .vaccine:
            saveVaccine(item)
        case .growth:
            saveGrowth(item)
        case .meal:
            saveHealth(item, kind: .meal)
        case .snack:
            saveHealth(item, kind: .snack)
        case .supplement:
            saveHealth(item, kind: .supplement)
        case .water:
            saveHealth(item, kind: .water)
        case .sleep:
            saveHealth(item, kind: .sleep)
        case .symptom:
            saveHealth(item, kind: .symptom)
        case .checkup:
            saveHealth(item, kind: .checkup)
        case .milestone:
            saveMilestone(item)
        case .firstTime:
            saveFirstTime(item)
        case .timeline, .unknown:
            saveEntry(item)
        }
    }

    // MARK: 健康记录

    private func saveHealth(_ item: NaturalCaptureItem, kind: HealthRecordKind) {
        let record = HealthRecord(kind: kind,
                                  title: item.title,
                                  recordedAt: item.date ?? .now)
        record.detail = item.note
        record.tags = item.tags
        record.syncState = .local

        switch kind {
        case .water:
            if let ml = item.fields.double("amount_ml") {
                record.amountValue = ml
                record.amountUnit = "ml"
                record.amountText = "\(Int(ml))ml"
            }
        case .sleep:
            // HealthRecord 自有 startAt/endAt：优先落区间，时长仅兜底
            record.startAt = item.fields.isoDate("start_at")
            record.endAt = item.fields.isoDate("end_at")
            if record.startAt == nil, record.endAt == nil,
               let minutes = item.fields.double("duration_minutes") {
                record.amountValue = minutes / 60
                record.amountUnit = "小时"
            }
            if let quality = item.fields.string("quality"), record.detail == nil {
                record.detail = quality
            }
        case .symptom:
            record.temperatureCelsius = item.fields.double("temperature_celsius")
            record.tags += item.fields.stringArray("symptoms")
        case .meal, .snack:
            let foods = item.fields.stringArray("food_items")
            if !foods.isEmpty { record.tags += foods }
            record.amountText = item.fields.string("amount_text")
            record.reaction = item.fields.string("reaction")
        case .supplement:
            record.amountText = item.fields.string("amount_text")
            if let name = item.fields.string("supplement_name") { record.tags.append(name) }
        case .checkup:
            if record.detail == nil { record.detail = item.fields.string("note") }
        }

        context.insert(record)
        context.insert(FeedEvent(kind: .healthRecorded,
                                 actorRole: env.config.currentRole.rawValue,
                                 summary: "智能记录了\(kind.title)：\(record.title)"))
    }

    // MARK: 疫苗（Phase 3 暂存体检护理 + 强确认；Phase 4 切 VaccineRecord）

    private func saveVaccine(_ item: NaturalCaptureItem) {
        let name = item.fields.string("vaccine_name") ?? item.title
        let record = HealthRecord(kind: .checkup,
                                  title: "疫苗接种：\(name)",
                                  recordedAt: item.date ?? .now)
        var detailParts: [String] = []
        if let v = item.fields.string("dose_label") { detailParts.append(v) }
        if let v = item.fields.string("hospital") { detailParts.append(v) }
        if let v = item.fields.string("reaction") { detailParts.append("反应：\(v)") }
        if let note = item.note { detailParts.append(note) }
        record.detail = detailParts.isEmpty ? nil : detailParts.joined(separator: " · ")
        record.tags = ["疫苗", name] + item.tags
        record.syncState = .local
        context.insert(record)
        context.insert(FeedEvent(kind: .healthRecorded,
                                 actorRole: env.config.currentRole.rawValue,
                                 summary: "智能记录了疫苗接种：\(name)"))
    }

    // MARK: 成长测量（Phase 3 暂存体检护理；Phase 4 切 GrowthMeasurement）

    private func saveGrowth(_ item: NaturalCaptureItem) {
        let date = item.date ?? .now
        var saved = false
        if let height = item.fields.double("height_cm") {
            let record = HealthRecord(kind: .checkup, title: "身高 \(trimNumber(height)) cm", recordedAt: date)
            record.amountValue = height
            record.amountUnit = "cm"
            record.tags = ["身高"]
            record.syncState = .local
            context.insert(record)
            saved = true
        }
        if let weight = item.fields.double("weight_kg") {
            let record = HealthRecord(kind: .checkup, title: "体重 \(trimNumber(weight)) kg", recordedAt: date)
            record.amountValue = weight
            record.amountUnit = "kg"
            record.tags = ["体重"]
            record.syncState = .local
            context.insert(record)
            saved = true
        }
        if let head = item.fields.double("head_circumference_cm") {
            let record = HealthRecord(kind: .checkup, title: "头围 \(trimNumber(head)) cm", recordedAt: date)
            record.amountValue = head
            record.amountUnit = "cm"
            record.tags = ["头围"]
            record.syncState = .local
            context.insert(record)
            saved = true
        }
        guard saved else {
            saveHealth(item, kind: .checkup)
            return
        }
        context.insert(FeedEvent(kind: .healthRecorded,
                                 actorRole: env.config.currentRole.rawValue,
                                 summary: "智能记录了成长测量：\(item.title)"))
    }

    // MARK: 里程碑 / 第一次 / 普通时光

    private func saveMilestone(_ item: NaturalCaptureItem) {
        guard item.confidence >= 0.6 else {
            saveEntry(item)
            return
        }
        let milestone = Milestone(title: item.title, category: "认知探索",
                                  happenedAt: item.date ?? .now, isCustom: true)
        milestone.detail = item.note
        milestone.syncState = .local
        context.insert(milestone)
        context.insert(FeedEvent(kind: .milestoneLit,
                                 actorRole: env.config.currentRole.rawValue,
                                 summary: "智能点亮了里程碑：\(item.title)"))
    }

    private func saveFirstTime(_ item: NaturalCaptureItem) {
        guard item.confidence >= 0.6 else {
            saveEntry(item)
            return
        }
        let first = FirstTime(what: item.title, happenedAt: item.date ?? .now)
        first.detectedByAI = true
        first.confirmedByParent = true
        first.syncState = .local
        context.insert(first)
        context.insert(FeedEvent(kind: .firstTimeConfirmed,
                                 actorRole: env.config.currentRole.rawValue,
                                 summary: "智能记下了「\(item.title)」"))
    }

    private func saveEntry(_ item: NaturalCaptureItem) {
        let entry = Entry(happenedAt: item.date ?? .now,
                          authorRole: env.config.currentRole.rawValue,
                          note: item.note ?? item.sourceText)
        entry.title = item.title
        entry.syncState = .local
        context.insert(entry)
        context.insert(FeedEvent(kind: .entryCreated,
                                 actorRole: env.config.currentRole.rawValue,
                                 summary: "智能记录了一条时光：\(item.title)",
                                 targetLocalId: entry.id.uuidString))
    }

    private func trimNumber(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
