import Testing
import Foundation
import SwiftData
@testable import BubuTimeMachine

// MARK: - 成长数据完整性 + 一次性迁移框架 回归测试
/// 覆盖三块修复：
/// (a) 头围/身高消歧：只写头围的记录不再污染身高曲线；正常身高记录照常提取。
/// (b) 回填一次性：同批记录跑两次不新增/不复活；删除后不再被回填复活。
/// (c) DataMigrationRunner：成功落标记、失败留痕不阻塞后续；VaccineLegacyMigrator 幂等。
@MainActor
struct GrowthIntegrityMigrationTests {

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

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "growth-integrity-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    private func healthRecord(kind: HealthRecordKind, title: String,
                              detail: String? = nil,
                              recordedAt: Date) -> HealthRecord {
        let record = HealthRecord(kind: kind, title: title, recordedAt: recordedAt)
        record.detail = detail
        return record
    }

    // MARK: (a) 头围 / 身高消歧

    @Test("只写头围的体检记录不产生身高测量")
    func headCircumferenceDoesNotBecomeHeight() {
        let record = healthRecord(kind: .checkup, title: "体检", detail: "头围45cm",
                                  recordedAt: Date(timeIntervalSince1970: 1_780_000_000))
        let values = GrowthMeasurementExtractor.values(from: record)
        #expect(values.headCircumferenceCm == 45)
        #expect(values.heightCm == nil, "头围45cm 不能被误当身高污染成长曲线")
    }

    @Test("正常身高记录仍能提取身高")
    func explicitHeightStillExtracted() {
        let record = healthRecord(kind: .checkup, title: "身高88cm",
                                  recordedAt: Date(timeIntervalSince1970: 1_780_000_000))
        let values = GrowthMeasurementExtractor.values(from: record)
        #expect(values.heightCm == 88)
    }

    @Test("同一条既有身高又有头围：各归各位，身高不取到头围的数字")
    func heightAndHeadCoexistWithoutCrosstalk() {
        let record = healthRecord(kind: .checkup, title: "体检", detail: "身高82cm 头围45cm",
                                  recordedAt: Date(timeIntervalSince1970: 1_780_000_000))
        let values = GrowthMeasurementExtractor.values(from: record)
        #expect(values.heightCm == 82)
        #expect(values.headCircumferenceCm == 45)
    }

    @Test("有身高关键词但只有头围数字：身高兜底被 excluding 挡住")
    func heightKeywordButOnlyHeadNumberDoesNotReuse() {
        // 「头围45cm 身高」——含身高关键词，但唯一的 cm 数字 45 已被头围消费。
        let record = healthRecord(kind: .checkup, title: "体检", detail: "头围45cm 身高",
                                  recordedAt: Date(timeIntervalSince1970: 1_780_000_000))
        let values = GrowthMeasurementExtractor.values(from: record)
        #expect(values.headCircumferenceCm == 45)
        #expect(values.heightCm == nil, "45 已被头围消费，不能被身高复用")
    }

    // MARK: (b) 回填一次性 / 不复活

    @Test("同批健康记录跑两次回填：幂等不新增")
    func backfillIsIdempotentAcrossRuns() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        context.insert(healthRecord(kind: .checkup, title: "体检", detail: "身高80cm 体重10kg",
                                    recordedAt: Date(timeIntervalSince1970: 1_780_000_000)))
        context.insert(healthRecord(kind: .checkup, title: "体检", detail: "身高85cm 体重11kg",
                                    recordedAt: Date(timeIntervalSince1970: 1_782_000_000)))
        try context.save()

        try GrowthMeasurementBackfill.perform(context: context, defaults: defaults)
        let afterFirst = try context.fetch(FetchDescriptor<GrowthMeasurement>()).count
        #expect(afterFirst == 2)

        try GrowthMeasurementBackfill.perform(context: context, defaults: defaults)
        let afterSecond = try context.fetch(FetchDescriptor<GrowthMeasurement>()).count
        #expect(afterSecond == 2, "二次回填不能重复插入")
    }

    @Test("删除自动生成的测量后再次回填不会复活")
    func deletedMeasurementIsNotRevived() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        context.insert(healthRecord(kind: .checkup, title: "体检", detail: "身高80cm",
                                    recordedAt: Date(timeIntervalSince1970: 1_780_000_000)))
        try context.save()

        try GrowthMeasurementBackfill.perform(context: context, defaults: defaults)
        var measurements = try context.fetch(FetchDescriptor<GrowthMeasurement>())
        #expect(measurements.count == 1)

        // 用户删除自动生成的测量
        context.delete(measurements[0])
        try context.save()

        // 再次回填：源记录 id 已在 processed 集合中 → 不复活
        try GrowthMeasurementBackfill.perform(context: context, defaults: defaults)
        measurements = try context.fetch(FetchDescriptor<GrowthMeasurement>())
        #expect(measurements.isEmpty, "删除后的测量不能被回填复活")
    }

    // MARK: (c) DataMigrationRunner

    @Test("迁移成功才落完成标记，且只执行一次")
    func runnerMarksDoneOnSuccessAndRunsOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let counter = Counter()
        let runner = DataMigrationRunner(
            migrations: [DataMigration(id: "unit-success-v1") { _ in counter.value += 1 }],
            defaults: defaults)

        runner.runPendingMigrations(context: context)
        #expect(counter.value == 1)
        #expect(runner.hasCompleted("unit-success-v1"))
        #expect(defaults.bool(forKey: DataMigrationRunner.doneKey(for: "unit-success-v1")))

        // 二次启动：已完成的迁移被跳过
        runner.runPendingMigrations(context: context)
        #expect(counter.value == 1, "已完成的迁移不再重复执行")
    }

    @Test("迁移失败不落标记、不阻塞后续迁移")
    func runnerFailureDoesNotBlockOrMark() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let laterRan = Counter()
        let runner = DataMigrationRunner(
            migrations: [
                DataMigration(id: "unit-fail-v1") { _ in throw TestError.boom },
                DataMigration(id: "unit-after-fail-v1") { _ in laterRan.value += 1 }
            ],
            defaults: defaults)

        runner.runPendingMigrations(context: context)
        #expect(!runner.hasCompleted("unit-fail-v1"), "失败迁移不落完成标记，下次重试")
        #expect(runner.hasCompleted("unit-after-fail-v1"), "前一个失败不阻塞后续迁移")
        #expect(laterRan.value == 1)
    }

    @Test("VaccineLegacyMigrator 经迁移框架执行：建记录且二次幂等")
    func vaccineMigratorViaRunnerIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(#"["HepB-1","BCG-1"]"#, forKey: VaccineLegacyMigrator.legacyKey)
        context.insert(ChildProfile(name: "布布", birthday: Date(timeIntervalSince1970: 1_731_000_000)))
        try context.save()

        let runner = DataMigrationRunner(
            migrations: [DataMigration(id: "vaccine-legacy-v1") {
                try VaccineLegacyMigrator.perform(context: $0, defaults: defaults)
            }],
            defaults: defaults)

        runner.runPendingMigrations(context: context)
        #expect(try context.fetch(FetchDescriptor<VaccineRecord>()).count == 2)
        #expect(runner.hasCompleted("vaccine-legacy-v1"))

        // 再跑一次（模拟老用户已有 migrated 标记但无 done 标记的重跑场景由框架跳过；
        // 这里直接调用 perform 验证 doseId 去重幂等）
        try VaccineLegacyMigrator.perform(context: context, defaults: defaults)
        #expect(try context.fetch(FetchDescriptor<VaccineRecord>()).count == 2, "按 doseId 去重，重复执行不产生重复记录")
    }

    // MARK: 测试辅助

    private final class Counter { var value = 0 }
    private enum TestError: Error { case boom }
}
