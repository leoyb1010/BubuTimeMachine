import Testing
import Foundation
@testable import BubuTimeMachine

@Suite("健康数值草稿")
struct HealthRecordDraftTests {
    @Test("越界数值不能沿用旧值保存")
    func invalidNumericInputBlocksSave() {
        var draft = HealthRecordDraft()
        draft.weightKg = 9
        draft.weightInputInvalid = true

        #expect(!draft.canSave(kind: .checkup))
    }

    @Test("合法成长数值可以保存")
    func validGrowthInputCanSave() {
        var draft = HealthRecordDraft()
        draft.heightCm = 92.5
        draft.weightKg = 13.4

        #expect(draft.canSave(kind: .checkup))
    }

    @Test("稳定关联优先于同日其它测量")
    func stableLinkWins() {
        let recordedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = HealthRecord(kind: .checkup, title: "体检", recordedAt: recordedAt)
        let linked = GrowthMeasurement(measuredAt: recordedAt.addingTimeInterval(-3_600), source: "checkup")
        let closer = GrowthMeasurement(measuredAt: recordedAt.addingTimeInterval(10), source: "checkup")
        record.growthMeasurementId = linked.id

        let result = HealthRecordGrowthLink.preferredMeasurement(
            for: record,
            from: [closer, linked]
        )

        #expect(result?.id == linked.id)
    }

    @Test("旧记录按时间距离确定性匹配")
    func legacyRecordUsesClosestMeasurement() {
        let recordedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = HealthRecord(kind: .checkup, title: "体检", recordedAt: recordedAt)
        let farther = GrowthMeasurement(measuredAt: recordedAt.addingTimeInterval(-1_800), source: "checkup")
        let closer = GrowthMeasurement(measuredAt: recordedAt.addingTimeInterval(60), source: "checkup")

        let result = HealthRecordGrowthLink.preferredMeasurement(
            for: record,
            from: [farther, closer]
        )

        #expect(result?.id == closer.id)
    }
}
