import Testing
import Foundation
import SwiftData
@testable import BubuTimeMachine

// MARK: - Wave N 单元测试（Swift Testing，与工程其余测试同风格）
/// 覆盖：自然语言 DTO 解码容错、上传响应文件名解析、Router 各 domain 落库、疫苗旧打卡迁移幂等。
@MainActor
struct WaveNTests {

    // MARK: 工具

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Entry.self, Media.self, Milestone.self, FirstTime.self,
            TimeCapsule.self, VoiceMemo.self, Comment.self, GrowthMovie.self,
            FamilyMember.self, ChildProfile.self, VoiceNote.self, HealthRecord.self,
            FeedEvent.self, VaccineRecord.self, GrowthMeasurement.self,
            PendingDeletion.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeItem(domain: NaturalCaptureDomain,
                          title: String = "测试记录",
                          date: Date? = Date(timeIntervalSince1970: 1_780_000_000),
                          fields: [String: JSONValue] = [:],
                          confidence: Double = 0.9) -> NaturalCaptureItem {
        NaturalCaptureItem(domain: domain, action: .create, title: title, note: nil,
                           date: date, fields: fields, tags: [],
                           confidence: confidence, needsConfirmation: false,
                           sourceText: "测试输入")
    }

    // MARK: NaturalCaptureCoding 容错

    @Test("ISO8601 解析容忍小数秒")
    func parseDateToleratesFractionalSeconds() {
        #expect(NaturalCaptureCoding.parseDate("2026-06-20T10:00:00+08:00") != nil)
        #expect(NaturalCaptureCoding.parseDate("2026-06-20T10:00:00.123456+08:00") != nil,
                "服务端 pydantic 偶发输出微秒时不能整包失败")
        #expect(NaturalCaptureCoding.parseDate("2026-06-20T02:00:00Z") != nil)
        #expect(NaturalCaptureCoding.parseDate("不是日期") == nil)
    }

    @Test("未知 domain/action 解码降级而非抛错；小数秒日期可解")
    func resultDecodingTolerates() throws {
        let json = """
        {
          "confidence": 0.8,
          "items": [
            {"domain": "made_up", "action": "explode", "title": "未知类型",
             "date": "2026-06-20T10:00:00.500+08:00",
             "fields": {"any": 1}, "tags": [], "confidence": 0.5,
             "needs_confirmation": true, "source_text": "原文"}
          ],
          "warnings": []
        }
        """
        let result = try NaturalCaptureCoding.decoder()
            .decode(NaturalCaptureResult.self, from: Data(json.utf8))
        #expect(result.items.count == 1)
        #expect(result.items[0].domain == .unknown)
        #expect(result.items[0].action == .create)
        #expect(result.items[0].date != nil)
    }

    // MARK: 上传响应文件名解析

    @Test("PocketBase 上传响应文件名：字符串/数组/缺失三态")
    func storedFileNameParsing() {
        #expect(PocketBaseClient.storedFileName(
            in: ["file": "photo_aBcD1234.jpg"], fileField: "file", fallback: "photo.jpg")
            == "photo_aBcD1234.jpg")
        #expect(PocketBaseClient.storedFileName(
            in: ["file": ["a_x1.jpg", "b_x2.jpg"]], fileField: "file", fallback: "photo.jpg")
            == "a_x1.jpg", "多文件字段取第一个")
        #expect(PocketBaseClient.storedFileName(
            in: ["file": ""], fileField: "file", fallback: "photo.jpg")
            == "photo.jpg", "空字符串回退本地名")
        #expect(PocketBaseClient.storedFileName(
            in: [:], fileField: "voiceFile", fallback: "voice.m4a")
            == "voice.m4a", "字段缺失回退本地名")
    }

    // MARK: Router 落库

    @Test("喝水落 HealthRecord 并产生 FeedEvent")
    func routerSavesWater() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let router = NaturalCaptureRouter(context: context, authorRole: "妈妈")

        router.save(makeItem(domain: .water, title: "喝水", fields: ["amount_ml": .number(120)]))
        try context.save()

        let records = try context.fetch(FetchDescriptor<HealthRecord>())
        #expect(records.count == 1)
        #expect(records.first?.kind == .water)
        #expect(records.first?.amountValue == 120)
        #expect(records.first?.amountUnit == "ml")
        #expect(try context.fetch(FetchDescriptor<FeedEvent>()).count == 1)
    }

    @Test("睡眠优先落 startAt/endAt 区间")
    func routerSavesSleepInterval() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let router = NaturalCaptureRouter(context: context, authorRole: "妈妈")

        router.save(makeItem(domain: .sleep, title: "睡眠", fields: [
            "start_at": .string("2026-06-11T13:00:00Z"),
            "end_at": .string("2026-06-11T23:00:00Z"),
        ]))
        try context.save()

        let records = try context.fetch(FetchDescriptor<HealthRecord>())
        #expect(records.count == 1)
        #expect(records.first?.kind == .sleep)
        #expect(records.first?.startAt != nil)
        #expect(records.first?.endAt != nil)
    }

    @Test("疫苗落 VaccineRecord 且名称模糊匹配排期剂次")
    func routerSavesVaccineWithDoseMatch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let router = NaturalCaptureRouter(context: context, authorRole: "妈妈")

        router.save(makeItem(domain: .vaccine, title: "卡介苗",
                             fields: ["vaccine_name": .string("卡介苗")]))
        try context.save()

        let records = try context.fetch(FetchDescriptor<VaccineRecord>())
        #expect(records.count == 1)
        #expect(records.first?.doseId == "BCG-1")
        #expect(records.first?.sourceRaw == "ai")
    }

    @Test("身高体重落 GrowthMeasurement")
    func routerSavesGrowthMeasurement() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let router = NaturalCaptureRouter(context: context, authorRole: "妈妈")

        router.save(makeItem(domain: .growth, title: "身高体重", fields: [
            "height_cm": .number(82), "weight_kg": .number(10.6),
        ]))
        try context.save()

        let records = try context.fetch(FetchDescriptor<GrowthMeasurement>())
        #expect(records.count == 1)
        #expect(records.first?.heightCm == 82)
        #expect(records.first?.weightKg == 10.6)
    }

    @Test("低置信里程碑降级为普通时光记录")
    func routerLowConfidenceMilestoneFallsBack() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let router = NaturalCaptureRouter(context: context, authorRole: "妈妈")

        router.save(makeItem(domain: .milestone, title: "可能是里程碑", confidence: 0.3))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Milestone>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Entry>()).count == 1)
    }

    private enum SaveFailure: Error { case diskFull }

    @Test("智能记录整批保存失败回滚、保留其它页面草稿，重试只新增一批")
    func batchFailureIsAtomicAndRetryKeepsUnrelatedDraft() throws {
        let container = try makeContainer()
        container.mainContext.autosaveEnabled = false
        let unrelated = Entry(happenedAt: .now, authorRole: "爸爸", note: "另一个页面未保存的草稿")
        container.mainContext.insert(unrelated)
        let items = [makeItem(domain: .water, fields: ["amount_ml": .number(120)]),
                     makeItem(domain: .timeline, title: "审计测试时光")]
        var attempted: ModelContext?
        #expect(throws: SaveFailure.self) {
            try NaturalCaptureRouter.saveBatch(items, authorRole: "妈妈", container: container, save: {
                attempted = $0
                #expect(!$0.autosaveEnabled)
                throw SaveFailure.diskFull
            })
        }
        let failed = try #require(attempted)
        #expect(!failed.hasChanges)
        #expect(container.mainContext.hasChanges)
        #expect(unrelated.note == "另一个页面未保存的草稿")
        let verification = ModelContext(container)
        #expect(try verification.fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(try verification.fetchCount(FetchDescriptor<HealthRecord>()) == 0)
        #expect(try verification.fetchCount(FetchDescriptor<FeedEvent>()) == 0)
        try NaturalCaptureRouter.saveBatch(items, authorRole: "妈妈", container: container)
        let saved = ModelContext(container)
        #expect(try saved.fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(try saved.fetchCount(FetchDescriptor<HealthRecord>()) == 1)
        #expect(try saved.fetchCount(FetchDescriptor<FeedEvent>()) == 2)
        #expect(container.mainContext.hasChanges)
        container.mainContext.rollback()
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()) == 1)
    }

    @Test("智能体检测量与记录稳定关联；同日第二次记录不会抢占关联")
    func checkupLinksExactGrowthMeasurement() throws {
        let container = try makeContainer()
        try NaturalCaptureRouter.saveBatch([
            makeItem(domain: .checkup, title: "第一次体检", fields: ["height_cm": .number(90)]),
            makeItem(domain: .checkup, title: "第二次体检", fields: ["height_cm": .number(91)])
        ], authorRole: "妈妈", container: container)
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<HealthRecord>())
        let measurements = try context.fetch(FetchDescriptor<GrowthMeasurement>())
        #expect(records.count == 2 && measurements.count == 2)
        #expect(Set(records.compactMap(\.growthMeasurementId)).count == 2)
        for record in records {
            let measurement = try #require(measurements.first { $0.id == record.growthMeasurementId })
            #expect(measurement.heightCm == (record.title == "第一次体检" ? 90 : 91))
        }
    }

    @Test("空确认列表无写入；疫苗重试保留去重规则")
    func emptyBatchAndVaccineRepeatAreSafe() throws {
        let container = try makeContainer()
        try NaturalCaptureRouter.saveBatch([], authorRole: "妈妈", container: container)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<FeedEvent>()) == 0)
        let vaccine = makeItem(domain: .vaccine, title: "卡介苗", fields: ["vaccine_name": .string("卡介苗")])
        try NaturalCaptureRouter.saveBatch([vaccine], authorRole: "妈妈", container: container)
        try NaturalCaptureRouter.saveBatch([vaccine], authorRole: "妈妈", container: container)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<VaccineRecord>()) == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<FeedEvent>()) == 1)
    }

    @Test("非法数量不进入 Int 转换，也不能在确认保存时被静默丢掉")
    func invalidNumericFieldsRetainReviewAndBlockWrites() throws {
        let container = try makeContainer()
        let values: [JSONValue] = [.number(.infinity), .number(.nan), .number(1e100),
                                   .string("1e100"), .string("NaN"), .string("不确定"),
                                   .number(1_000_000_000), .array([]), .bool(true)]
        for value in values {
            let item = makeItem(domain: .water, fields: ["amount_ml": value])
            #expect(item.fields.double("amount_ml") == nil)
            #expect(item.hasInvalidNumericFields)
            #expect(throws: NaturalCaptureRouter.SaveError.self) {
                try NaturalCaptureRouter.saveBatch([item], authorRole: "妈妈", container: container)
            }
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<HealthRecord>()) == 0)
        let validFields: [[String: JSONValue]] = [[:], ["amount_ml": .null],
            ["amount_ml": .number(120)], ["amount_ml": .string("120.5")]]
        for fields in validFields {
            #expect(!makeItem(domain: .water, fields: fields).hasInvalidNumericFields)
        }
        let repaired = makeItem(domain: .water, fields: ["amount_ml": .string("120.5")])
        try NaturalCaptureRouter.saveBatch([repaired], authorRole: "妈妈", container: container)
        let saved = try #require(try ModelContext(container).fetch(FetchDescriptor<HealthRecord>()).first)
        #expect(saved.amountValue == 120.5)
    }

    @Test("未消费数量不锁住普通时光；未确认坏项不阻止保存其余已确认项")
    func irrelevantAndUnconfirmedNumericFieldsDoNotBlockOtherRecords() throws {
        let container = try makeContainer()
        let timeline = makeItem(domain: .timeline, title: "普通时光",
                                fields: ["amount_ml": .string("not used by timeline")])
        #expect(!timeline.hasInvalidNumericFields)
        let symptom = makeItem(domain: .symptom,
                               fields: ["temperature_celsius": .string("待核对")], confidence: 0.1)
        #expect(symptom.hasInvalidNumericFields && symptom.requiresHardConfirmation)
        let confirmedIDs: Set<UUID> = []
        let eligible = [timeline, symptom].filter { !$0.requiresHardConfirmation || confirmedIDs.contains($0.id) }
        #expect(eligible.count == 1 && !eligible.contains(where: \.hasInvalidNumericFields))
        try NaturalCaptureRouter.saveBatch(eligible, authorRole: "妈妈", container: container)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<HealthRecord>()) == 0)
        #expect(!makeItem(domain: .vaccine, fields: ["amount_ml": .number(.infinity)]).hasInvalidNumericFields)
        #expect(!makeItem(domain: .water, fields: ["height_cm": .string("unused")]).hasInvalidNumericFields)
    }

    // MARK: 疫苗旧打卡迁移

    @Test("旧打卡迁移：建结构化记录、保留旧键、二次执行幂等")
    func vaccineLegacyMigrationIdempotent() throws {
        let suiteName = "wave-n-migration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(#"["HepB-1","BCG-1","HepB-2"]"#, forKey: VaccineLegacyMigrator.legacyKey)

        let container = try makeContainer()
        let context = container.mainContext
        let profile = ChildProfile(name: "布布", birthday: Date(timeIntervalSince1970: 1_731_000_000))
        context.insert(profile)
        try context.save()

        VaccineLegacyMigrator.migrateIfNeeded(context: context, defaults: defaults)

        let first = try context.fetch(FetchDescriptor<VaccineRecord>())
        #expect(first.count == 3)
        #expect(Set(first.compactMap(\.doseId)) == ["HepB-1", "BCG-1", "HepB-2"])
        #expect(first.allSatisfy { $0.sourceRaw == "migration" })
        #expect(defaults.bool(forKey: VaccineLegacyMigrator.migratedKey))
        #expect(defaults.string(forKey: VaccineLegacyMigrator.legacyKey) != nil, "旧键必须保留以便回滚")

        // 二次执行：幂等，不重复迁移
        VaccineLegacyMigrator.migrateIfNeeded(context: context, defaults: defaults)
        #expect(try context.fetch(FetchDescriptor<VaccineRecord>()).count == 3)
    }
}
