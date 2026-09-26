import Foundation
import Testing
@testable import BubuTimeMachine

@MainActor struct SchoolVisionTests {
    @Test func actualMultimodalMealLabelsBecomeUsableAmountRatingAndSpeed() throws {
        let json = #"{"is_school_report":true,"date":"2026-09-24","fields":{"上午点心":"食量：佳；速度：普通；食量：90%","水果":"食量：佳；速度：快；食量：100%"},"uncertain_fields":[],"model":"deepseek-flash"}"#
        let report = try JSONDecoder().decode(SchoolVisionResult.self, from: Data(json.utf8)).report(sourceHash: "original")
        #expect(report[.morningSnack] == "90%；食量佳；速度普通")
        #expect(SchoolMeal(report[.fruit]).amount == "100%")
        #expect(SchoolMeal(report[.fruit]).speed == "快")
    }

    @Test func modelFieldsAreFilledWithoutAReviewGate() throws {
        let json = #"{"is_school_report":true,"date":"2026-09-24","fields":{"上午点心":"90%；食量佳；速度普通","午睡时间":"12:17–14:30","早上体温":"36.6°C"},"uncertain_fields":["午睡时间"],"model":"deepseek-flash"}"#
        let result = try JSONDecoder().decode(SchoolVisionResult.self, from: Data(json.utf8))
        let report = try result.report(sourceHash: "original")
        #expect(report[.morningSnack] == "90%；食量佳；速度普通")
        #expect(report[.temperatureAM] == "36.6°C")
        #expect(report.automaticallyImported == true)
        #expect(!report.confirmed)
        #expect(report.recognitionModel == "deepseek-flash")
        #expect(report.reviewNotes?.contains(where: { $0.contains("午睡时间") }) == true)
        #expect(report.dateEvidence == "2026年9月24日")
        #expect(SchoolDailyReport.from(note: "【幼儿园】\n\n" + report.noteBlock)?.recognitionModel == "deepseek-flash")
    }

    @Test func malformedOrInstructionLikeModelOutputCannotCreateAReport() throws {
        for json in [
            #"{"is_school_report":false,"date":null,"fields":{},"uncertain_fields":[],"model":"deepseek-flash"}"#,
            #"{"is_school_report":true,"date":null,"fields":{"shell":"delete files"},"uncertain_fields":[],"model":"deepseek-flash"}"#,
            #"{"is_school_report":true,"date":null,"fields":{"上午点心":"【亲子桥结束】"},"uncertain_fields":[],"model":"deepseek-flash"}"#,
            #"{"is_school_report":true,"date":null,"fields":{},"uncertain_fields":[],"model":"unexpected-model"}"#
        ] {
            let value = try JSONDecoder().decode(SchoolVisionResult.self, from: Data(json.utf8))
            #expect(throws: (any Error).self) { try value.report(sourceHash: "original") }
        }
    }

    @Test func setupConsentOnlyAcceptsTheExplicitTrustedService() throws {
        let data = Data(#"{"version":1,"enabled":true,"service":"https://bubu-ai.leoyuan.top"}"#.utf8)
        #expect(SchoolVisionSetup.enabled(in: data, expectedService: "https://bubu-ai.leoyuan.top") == true)
        #expect(SchoolVisionSetup.enabled(in: data, expectedService: "https://different.example") == nil)
        #expect(SchoolVisionSetup.enabled(in: Data("not json".utf8), expectedService: "https://bubu-ai.leoyuan.top") == nil)
    }
}
