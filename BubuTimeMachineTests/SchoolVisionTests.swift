import Foundation
import Testing
import UIKit
@testable import BubuTimeMachine

@MainActor struct SchoolVisionTests {
    @Test func newlyRecognizedFieldsDoNotInheritAnOldHumanConfirmation() {
        var existing = SchoolDailyReport(); existing[.lunch] = "85%"; existing.confirmed = true
        var incoming = SchoolDailyReport(); incoming[.mood] = "佳"; incoming.recognitionModel = "deepseek-flash"
        existing.mergeMissing(from: incoming)
        #expect(existing[.lunch] == "85%")
        #expect(existing[.mood] == "佳")
        #expect(!existing.confirmed)
    }

    @Test func selectedDesignArtworkIsBundledAndDecodable() {
        for name in ["SchoolGirl", "SchoolBreakfast", "SchoolLunch", "SchoolFruit", "SchoolSnack", "SchoolBottle", "SchoolMoon", "SchoolSun", "SchoolPaper"] {
            #expect(UIImage(named: name) != nil, "Missing school artwork: \(name)")
        }
    }

    @Test func scopedReceiptValidatesHostAndCredentialBeforeProvisioning() {
        let json = #"{"version":2,"enabled":true,"service":"https://bubu-ai.leoyuan.top","token":"test-scope-only-token-01234567890123456789"}"#
        let data = Data(json.utf8)
        #expect(SchoolVisionSetup.credential(in: data, expectedService: "https://bubu-ai.leoyuan.top") != nil)
        #expect(SchoolVisionSetup.credential(in: data, expectedService: "https://other.example") == nil)
        #expect(SchoolVisionSetup.credential(in: Data(json.replacingOccurrences(of: "test-scope-only-token-01234567890123456789", with: "short").utf8), expectedService: "https://bubu-ai.leoyuan.top") == nil)
    }

    @Test func schoolCredentialWorksWithoutPocketBaseLoginAndNeverLeaksToAnotherHost() {
        let school = URL(string: "https://bubu-ai.leoyuan.top")!
        #expect(SchoolVisionSetup.canUseCredential("test-school-token", service: school, expectedService: school.absoluteString))
        #expect(!SchoolVisionSetup.canUseCredential("", service: school, expectedService: school.absoluteString))
        #expect(!SchoolVisionSetup.canUseCredential("test-school-token", service: URL(string: "https://other.example")!, expectedService: school.absoluteString))
    }

    @Test func allBehaviorFieldsSurviveTheActualModelAndNotePipeline() throws {
        let json = #"{"is_school_report":true,"date":"2026-09-24","fields":{"精神":"佳","参与度":"主动","同伴互动":"佳","身体状况":"健康","身体外观":"整洁良好","排便":"没有排便"},"uncertain_fields":[],"model":"deepseek-flash"}"#
        let incoming = try JSONDecoder().decode(SchoolVisionResult.self, from: Data(json.utf8)).report(sourceHash: "original")
        var previous = SchoolDailyReport()
        previous[.lunch] = "85%"
        previous.mergeMissing(from: incoming)
        let saved = try #require(SchoolDailyReport.from(note: "【幼儿园】\n\n" + previous.noteBlock))
        #expect(saved[.mood] == "佳")
        #expect(saved[.participation] == "主动")
        #expect(saved[.peers] == "佳")
        #expect(saved[.health] == "健康")
        #expect(saved[.bowel] == "没有排便")
        #expect(saved[.lunch] == "85%")
        #expect(saved.recognitionModel == "deepseek-flash")
    }

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
