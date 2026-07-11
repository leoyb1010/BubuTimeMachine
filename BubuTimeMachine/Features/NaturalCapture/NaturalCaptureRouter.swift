import Foundation
import SwiftData

// MARK: - 自然语言记录 → 各模块落库路由
/// LLM 解析结果经用户确认后，由这里写入对应 SwiftData 模型并产生 FeedEvent。
/// 原则：不确定就降级为普通时光记录，绝不编造字段。
@MainActor
struct NaturalCaptureRouter {
    let context: ModelContext
    /// 解耦 AppEnvironment：只需要作者角色字符串，单测可用内存容器直建。
    let authorRole: String

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
            // 确认页体检卡上填的身高/体重/头围：落 GrowthMeasurement 进成长曲线，
            // 并把摘要写进 amountText——之前这些字段被整体丢弃（R4 P2-18）
            let h = item.fields.double("height_cm")
            let w = item.fields.double("weight_kg")
            let hc = item.fields.double("head_circumference_cm")
            if h != nil || w != nil || hc != nil {
                let measurement = GrowthMeasurement(measuredAt: item.date ?? .now, source: "checkup")
                measurement.heightCm = h
                measurement.weightKg = w
                measurement.headCircumferenceCm = hc
                measurement.note = item.note
                measurement.syncState = .local
                context.insert(measurement)
                let summary = [
                    h.map { "身高 \(Self.cleanNumber($0))cm" },
                    w.map { "体重 \(Self.cleanNumber($0))kg" },
                    hc.map { "头围 \(Self.cleanNumber($0))cm" },
                ].compactMap { $0 }.joined(separator: " · ")
                record.amountText = [record.amountText, summary.isEmpty ? nil : summary]
                    .compactMap { $0 }.joined(separator: " · ")
            }
        }

        context.insert(record)
        context.insert(FeedEvent(kind: .healthRecorded,
                                 actorRole: authorRole,
                                 summary: "智能记录了\(kind.title)：\(record.title)"))
    }

    // MARK: 疫苗（结构化 VaccineRecord，自动匹配国家排期剂次）

    private func saveVaccine(_ item: NaturalCaptureItem) {
        let name = item.fields.string("vaccine_name") ?? item.title
        let injectedAt = item.date ?? .now
        // 重复口述保护：同名 + 同一天已有记录就不再入库——
        // 否则模糊匹配会把同一针自动打卡到"下一剂"（R4 P2-19）
        let cal = Calendar.current
        let existing = (try? context.fetch(FetchDescriptor<VaccineRecord>())) ?? []
        if existing.contains(where: { $0.vaccineName == name && cal.isDate($0.injectedAt, inSameDayAs: injectedAt) }) {
            return
        }
        let record = VaccineRecord(vaccineName: name,
                                   injectedAt: injectedAt,
                                   source: "ai")
        record.doseLabel = item.fields.string("dose_label")
        record.hospital = item.fields.string("hospital")
        record.injectionSite = item.fields.string("injection_site")
        record.reaction = item.fields.string("reaction")
        record.note = item.note
        record.syncState = .local
        // 名称太短/太泛（如"疫苗"两个字）不做剂次匹配，避免误打到别的针
        if name.count >= 3, let dose = matchDose(named: name) {
            record.doseId = dose.id
            if record.doseLabel == nil { record.doseLabel = dose.doseLabel }
        }
        context.insert(record)
        context.insert(FeedEvent(kind: .healthRecorded,
                                 actorRole: authorRole,
                                 summary: "智能记录了疫苗接种：\(name)"))
        let ctx = context
        Task { await ReminderScheduler.shared.refreshVaccineReminders(context: ctx) }   // 打卡后自动排下一针
    }

    private static func cleanNumber(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// 名称模糊匹配国家排期：取尚未打卡、名称互相包含的第一个剂次；匹配不到就作为自由疫苗记录。
    private func matchDose(named name: String) -> VaccineDose? {
        let recorded = Set(((try? context.fetch(FetchDescriptor<VaccineRecord>())) ?? []).compactMap(\.doseId))
        return VaccineDose.schedule.first { dose in
            !recorded.contains(dose.id) &&
            (name.contains(dose.shortName) || name.contains(dose.vaccine) || dose.vaccine.contains(name))
        }
    }

    // MARK: 成长测量（结构化 GrowthMeasurement，成长曲线直接读数值）

    private func saveGrowth(_ item: NaturalCaptureItem) {
        let measurement = GrowthMeasurement(measuredAt: item.date ?? .now, source: "ai")
        measurement.heightCm = item.fields.double("height_cm")
        measurement.weightKg = item.fields.double("weight_kg")
        measurement.headCircumferenceCm = item.fields.double("head_circumference_cm")
        measurement.note = item.note
        measurement.syncState = .local
        guard measurement.heightCm != nil || measurement.weightKg != nil || measurement.headCircumferenceCm != nil else {
            saveHealth(item, kind: .checkup)
            return
        }
        context.insert(measurement)
        context.insert(FeedEvent(kind: .healthRecorded,
                                 actorRole: authorRole,
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
                                 actorRole: authorRole,
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
                                 actorRole: authorRole,
                                 summary: "智能记下了「\(item.title)」"))
    }

    private func saveEntry(_ item: NaturalCaptureItem) {
        let entry = Entry(happenedAt: item.date ?? .now,
                          authorRole: authorRole,
                          note: item.note ?? item.sourceText)
        entry.title = item.title
        entry.syncState = .local
        context.insert(entry)
        context.insert(FeedEvent(kind: .entryCreated,
                                 actorRole: authorRole,
                                 summary: "智能记录了一条时光：\(item.title)",
                                 targetLocalId: entry.id.uuidString))
    }
}
