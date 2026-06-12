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
