import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 2.25 成长：WHO LMS、发育参考清单、成长脸缓存规则
@MainActor
struct Growth2_25Tests {

    private func value(_ metric: WHOGrowthStandard.Metric, month: Double, z: Double) -> Double {
        WHOGrowthStandard.lms(metric: metric, gender: "女", ageMonths: month)!.value(z: z)
    }

    @Test func girlLMSMatchesPublishedWHOPercentiles() {
        // WHO 2006 女孩百分位表（保留一位小数）
        #expect(abs(value(.weight, month: 0, z: WHOGrowthStandard.Z.p3) - 2.4) < 0.1)
        #expect(abs(value(.weight, month: 0, z: WHOGrowthStandard.Z.p50) - 3.2) < 0.05)
        #expect(abs(value(.weight, month: 60, z: WHOGrowthStandard.Z.p97) - 24.4) < 0.1)
        #expect(abs(value(.height, month: 12, z: WHOGrowthStandard.Z.p50) - 74.0) < 0.05)
        #expect(abs(value(.height, month: 12, z: WHOGrowthStandard.Z.p3) - 69.2) < 0.1)
        #expect(abs(value(.height, month: 60, z: -2) - 99.9) < 0.1)
        #expect(abs(value(.head, month: 0, z: WHOGrowthStandard.Z.p3) - 31.7) < 0.1)
        #expect(abs(value(.head, month: 12, z: WHOGrowthStandard.Z.p50) - 44.9) < 0.05)
    }

    @Test func percentileRoundTripsThroughZScore() {
        let median = value(.weight, month: 29.5, z: 0)
        let p = WHOGrowthStandard.percentile(metric: .weight, gender: "女", ageMonths: 29.5, value: median)!
        #expect(abs(p - 50) < 0.01)
        let high = value(.height, month: 18, z: WHOGrowthStandard.Z.p85)
        let p85 = WHOGrowthStandard.percentile(metric: .height, gender: nil, ageMonths: 18, value: high)!
        #expect(abs(p85 - 85) < 0.1)
    }

    @Test func girlBandsAreMonthlyAndOrdered() {
        let bands = WHOGrowthStandard.bands(metric: .head, gender: "女")
        #expect(bands.count == 61)
        #expect(bands.allSatisfy { $0.p3 < $0.p15 && $0.p15 < $0.p50 && $0.p50 < $0.p85 && $0.p85 < $0.p97 })
        #expect(WHOGrowthStandard.isApproximate(gender: "男"))
        #expect(!WHOGrowthStandard.isApproximate(gender: "女"))
    }

    @Test func checklistShowsPreviousCurrentNextBand() {
        #expect(DevelopmentChecklist.visibleBands(ageMonths: 29).map(\.months) == [24, 30, 36])
        #expect(DevelopmentChecklist.visibleBands(ageMonths: 30).map(\.months) == [24, 30, 36])
        #expect(DevelopmentChecklist.visibleBands(ageMonths: 5).map(\.months) == [12, 15])
        #expect(DevelopmentChecklist.visibleBands(ageMonths: 70).map(\.months) == [48, 60])
    }

    @Test func checklistItemIDsAreUniqueAndEveryBandHasAllDomains() {
        let all = DevelopmentChecklist.bands.flatMap(\.items)
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(DevelopmentChecklist.bands.map(\.months) == DevelopmentChecklist.bandMonths)
        for band in DevelopmentChecklist.bands {
            #expect(Set(band.items.map(\.domain)) == Set(DevDomain.allCases))
        }
    }

    @Test func ticksRoundTripAndBrainMatching() {
        let ids: Set<String> = ["cdc24-movement-1", "cdc30-language-2"]
        #expect(DevChecklistTicks.decode(DevChecklistTicks.encode(ids)) == ids)
        #expect(DevChecklistTicks.decode("").isEmpty)
        let kick = DevelopmentChecklist.bands.first { $0.months == 24 }!.items.first { $0.text == "会踢球" }!
        #expect(DevelopmentChecklist.matches(kick, texts: ["第一次踢球 来自第二大脑：在公园踢球"]))
        #expect(!DevelopmentChecklist.matches(kick, texts: ["第一次吃西瓜"]))
    }

    @Test func faceCacheRechecksOnlyWhenNeeded() {
        let now = Date.now
        let pastEnd = now.addingTimeInterval(-40 * 86_400)
        #expect(FaceTimelapseCache.needsCheck(nil, monthEnd: pastEnd, now: now))
        #expect(!FaceTimelapseCache.needsCheck(.init(itemId: "a", checkedAt: now.addingTimeInterval(-90 * 86_400)), monthEnd: pastEnd, now: now))
        #expect(!FaceTimelapseCache.needsCheck(.init(itemId: nil, checkedAt: now.addingTimeInterval(-86_400)), monthEnd: pastEnd, now: now))
        #expect(FaceTimelapseCache.needsCheck(.init(itemId: nil, checkedAt: now.addingTimeInterval(-8 * 86_400)), monthEnd: pastEnd, now: now))
        #expect(FaceTimelapseCache.needsCheck(.init(itemId: "a", checkedAt: now.addingTimeInterval(-13 * 3600)), monthEnd: now.addingTimeInterval(86_400), now: now))
    }

    @Test func firstDTODecodesContractShape() throws {
        let json = #"{"items":[{"id":"f1","concept":"walk","title":"第一次独立行走","date":"2025-06-01","item_id":"x","preview_url":"/learning/api/online-timeline/x/preview","description":"在客厅走了三步","status":"candidate"}]}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let list = try decoder.decode(GrowthFirstListDTO.self, from: Data(json.utf8))
        #expect(list.items.first?.displayTitle == "第一次独立行走")
        #expect(list.items.first?.day != nil)
        #expect(GrowthServiceAvailability.hides(LearningServiceError.server(503)))
        #expect(GrowthServiceAvailability.hides(LearningServiceError.unavailableMedia))
        #expect(!GrowthServiceAvailability.hides(LearningServiceError.unauthorized))
    }
}
