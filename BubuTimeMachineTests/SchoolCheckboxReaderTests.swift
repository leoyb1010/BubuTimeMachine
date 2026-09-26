import CoreGraphics
import Testing
import UIKit
@testable import BubuTimeMachine

@MainActor struct SchoolCheckboxReaderTests {
    @Test func healthyAndSymptomConflictIsFlaggedInsteadOfPublishedAsAHealthFact() throws {
        let rows = [SchoolOCRLine(text: "亲子桥", x: 0.3, y: 0.1, confidence: 1),
                    SchoolOCRLine(text: "身体状况", x: 0.1, y: 0.6, confidence: 1),
                    SchoolOCRLine(text: "口健康 口发烧", x: 0.2, y: 0.6, confidence: 1, checkedOptions: ["健康", "发烧"])]
        let report = try #require(SchoolDailyReport.recognize(rows))
        #expect(report.candidates[SchoolReportField.health.rawValue] == nil)
        #expect(report.reviewNotes?.contains(where: { $0.contains("身体状况") }) == true)
    }

    @Test func anEmptyPrintedBoxIsNotASelectedAnswer() throws {
        let image = try checkboxImage { _ in }
        #expect(!SchoolCheckboxReader.containsMark(in: image))
    }

    @Test func aClearHandwrittenTickInsideTheBoxIsSelected() throws {
        let image = try checkboxImage { context in
            context.setStrokeColor(UIColor.black.cgColor)
            context.setLineWidth(6)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: 10, y: 20))
            context.addLine(to: CGPoint(x: 18, y: 27))
            context.addLine(to: CGPoint(x: 31, y: 11))
            context.strokePath()
        }
        #expect(SchoolCheckboxReader.containsMark(in: image))
    }

    @Test func sparseScanNoiseDoesNotTurnAnEmptyBoxIntoAnAnswer() throws {
        let image = try checkboxImage { context in
            context.setFillColor(UIColor.black.cgColor)
            for point in [CGPoint(x: 13, y: 14), CGPoint(x: 22, y: 19), CGPoint(x: 17, y: 26)] {
                context.fill(CGRect(origin: point, size: CGSize(width: 1, height: 1)))
            }
        }
        #expect(!SchoolCheckboxReader.containsMark(in: image))
    }

    @Test func checkedMealOptionsJoinThePercentageInTheirOwnMealCell() throws {
        var lines = mealAnchors
        lines += [
            .init(text: "食量：口佳 口普通 口不佳", x: 0.30, y: 0.22, confidence: 1, checkedOptions: ["佳"]),
            .init(text: "速度：口快 口普通 口慢", x: 0.30, y: 0.24, confidence: 1, checkedOptions: ["普通"]),
            .init(text: "食量：90%", x: 0.30, y: 0.26, confidence: 1),
            .init(text: "食量：100%", x: 0.70, y: 0.26, confidence: 1)
        ]

        let report = try #require(SchoolDailyReport.recognize(lines))

        #expect(report.candidates[SchoolReportField.morningSnack.rawValue] == "90%；食量佳；速度普通")
        #expect(report.candidates[SchoolReportField.fruit.rawValue] == "100%")
        #expect(report.candidates[SchoolReportField.lunch.rawValue] == nil)
        #expect(report.candidates[SchoolReportField.afternoonSnack.rawValue] == nil)
    }

    @Test func printedOptionsWithoutChecksNeverBecomeMealSelections() throws {
        var lines = mealAnchors
        lines += [
            .init(text: "食量：口佳 口普通 口不佳", x: 0.30, y: 0.22, confidence: 1),
            .init(text: "速度：口快 口普通 口慢", x: 0.30, y: 0.24, confidence: 1),
            .init(text: "食量：90%", x: 0.30, y: 0.26, confidence: 1),
            .init(text: "食量：口佳 口普通 口不佳", x: 0.70, y: 0.22, confidence: 1),
            .init(text: "速度：口快 口普通 口慢", x: 0.70, y: 0.24, confidence: 1)
        ]

        let report = try #require(SchoolDailyReport.recognize(lines))

        #expect(report.candidates[SchoolReportField.morningSnack.rawValue] == "90%")
        #expect(report.candidates[SchoolReportField.fruit.rawValue] == nil)
    }

    @Test func conflictingChecksAreNotSilentlyResolvedToTheFirstOption() throws {
        var lines = mealAnchors
        lines += [
            .init(text: "食量：口佳 口普通 口不佳", x: 0.30, y: 0.22, confidence: 1, checkedOptions: ["佳", "普通"]),
            .init(text: "速度：口快 口普通 口慢", x: 0.30, y: 0.24, confidence: 1, checkedOptions: ["快", "慢"]),
            .init(text: "食量：90%", x: 0.30, y: 0.26, confidence: 1)
        ]

        let report = try #require(SchoolDailyReport.recognize(lines))

        #expect(report.candidates[SchoolReportField.morningSnack.rawValue] == "90%")
    }

    private var mealAnchors: [SchoolOCRLine] {
        [
            .init(text: "1.5–3岁亲子桥", x: 0.30, y: 0.07, confidence: 1),
            .init(text: "上午点心", x: 0.30, y: 0.19, confidence: 1),
            .init(text: "水果", x: 0.70, y: 0.19, confidence: 1),
            .init(text: "中午午餐", x: 0.30, y: 0.29, confidence: 1),
            .init(text: "下午点心", x: 0.70, y: 0.29, confidence: 1),
            .init(text: "睡眠", x: 0.10, y: 0.39, confidence: 1)
        ]
    }

    private func checkboxImage(ink: (CGContext) -> Void) throws -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40), format: format).image { renderer in
            let context = renderer.cgContext
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            context.setStrokeColor(UIColor.black.cgColor)
            context.setLineWidth(3)
            context.stroke(CGRect(x: 3, y: 3, width: 34, height: 34))
            ink(context)
        }
        return try #require(image.cgImage)
    }
}
