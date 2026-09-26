import Foundation
import Testing
import SwiftData
@testable import BubuTimeMachine

@MainActor struct SchoolDailyReportTests {
    @Test func columnsMustNotMixAndPrintedChoicesAreNotAnswers() {
        let lines: [SchoolOCRLine] = [
            .init(text: "1.5-3岁亲子桥", x: 0.3, y: 0.07, confidence: 1),
            .init(text: "上午点心", x: 0.32, y: 0.19, confidence: 1),
            .init(text: "水果", x: 0.71, y: 0.19, confidence: 1),
            .init(text: "中午午餐", x: 0.33, y: 0.29, confidence: 1),
            .init(text: "下午点心", x: 0.7, y: 0.29, confidence: 1),
            .init(text: "睡眠", x: 0.10, y: 0.39, confidence: 1),
            .init(text: "90%", x: 0.29, y: 0.26, confidence: 0.3),
            .init(text: "100%", x: 0.65, y: 0.25, confidence: 0.5),
            .init(text: "80%", x: 0.30, y: 0.35, confidence: 0.3),
            .init(text: "食量：70%", x: 0.55, y: 0.35, confidence: 0.3),
            .init(text: "口很安静 口容易醒 口睡不着", x: 0.55, y: 0.41, confidence: 1),
            .init(text: "中午：357°C", x: 0.44, y: 0.45, confidence: 0.3)
        ]
        let report = SchoolDailyReport.recognize(lines)
        #expect(report != nil)
        #expect(report?.candidates[SchoolReportField.morningSnack.rawValue] == "90%")
        #expect(report?.candidates[SchoolReportField.fruit.rawValue] == "100%")
        #expect(report?.candidates[SchoolReportField.lunch.rawValue] == "80%")
        #expect(report?.candidates[SchoolReportField.afternoonSnack.rawValue] == "70%")
        #expect(report?.values.isEmpty == true)
        #expect(report?.confirmed == false)
        #expect(report?.candidates[SchoolReportField.temperatureNoon.rawValue] == nil)
        #expect(report?.candidates[SchoolReportField.nap.rawValue] == nil)
    }

    @Test func unrecognizedPhotoDoesNotBecomeADailyReport() {
        #expect(SchoolDailyReport.recognize([.init(text: "今天吃了午餐", x: 0.3, y: 0.4, confidence: 1)]) == nil)
    }

    @Test func confirmedFieldsRoundTripWithoutLeakingOCRCandidates() {
        var report = SchoolDailyReport()
        report.values[SchoolReportField.lunch.rawValue] = "90%；食量佳；速度普通"
        report.values[SchoolReportField.nap.rawValue] = "12:17–14:30，安静"
        report.candidates[SchoolReportField.temperatureNoon.rawValue] = "357°C"
        report.confirmed = true
        let note = "【幼儿园】\n\n" + report.noteBlock
        let decoded = SchoolDailyReport.from(note: note)
        #expect(decoded?.values == report.values)
        #expect(decoded?.confirmed == true)
        #expect(!note.contains("357"))
        #expect(SchoolDailyReport.from(note: "老师说午餐很好") == nil)
    }

    @Test func layoutAnchorsMustBePresentBeforeAssigningValues() {
        #expect(SchoolDailyReport.recognize([
            .init(text: "亲子桥", x: 0.2, y: 0.1, confidence: 1),
            .init(text: "90%", x: 0.3, y: 0.3, confidence: 1)
        ])?.candidates.isEmpty == true)
    }

    @Test func unreviewedReportCannotEnterTheTimeline() throws {
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        var draft = MemoryJournalDraft(id: UUID(), kind: .school, date: .now, words: "今天")
        draft.schoolReport = SchoolDailyReport()
        draft.schoolReport?[.lunch] = "90%"
        #expect(throws: JournalDraftError.self) {
            try MemoryJournalWriter.save(draft, files: [], voice: nil, role: .papa, container: container)
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()) == 0)
        draft.schoolReport?.confirmed = true
        _ = try MemoryJournalWriter.save(draft, files: [], voice: nil, role: .papa, container: container)
        let entry = try #require(try ModelContext(container).fetch(FetchDescriptor<Entry>()).first)
        #expect(SchoolDailyReport.from(note: entry.note)?[.lunch] == "90%")
    }

    @Test func editingReviewedValueRequiresAnotherReview() {
        var report = SchoolDailyReport()
        report[.lunch] = "90%"
        report.confirmed = true
        report[.lunch] = "80%"
        #expect(!report.confirmed)
        #expect(report.noteBlock.isEmpty)
    }

    @Test func oldDraftsWithoutReportFieldsStillDecode() throws {
        let object: [String: Any] = ["draft": ["id": UUID().uuidString, "kind": "school", "date": 0,
            "words": "旧故事", "context": "", "meal": "旧餐食", "sleep": "", "source": ""],
            "files": [["id": UUID().uuidString, "fileName": "old.jpg", "hash": "abc", "isVideo": false]]]
        let snapshot = try JSONDecoder().decode(JournalDraftSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(snapshot.draft.schoolReport == nil)
        #expect(snapshot.draft.words == "旧故事")
        #expect(snapshot.files.first?.isSchoolReport == nil)
    }

    @Test func checkboxChoicesKeepPercentagesAndOtherSymptoms() {
        var report = SchoolDailyReport()
        report[.lunch] = "90%"
        report.choose("食量佳", for: .lunch)
        report.choose("速度普通", for: .lunch)
        report.choose("速度慢", for: .lunch)
        #expect(report[.lunch] == "90%；食量佳；速度慢")
        report.choose("健康", for: .health)
        report.choose("咳嗽", for: .health)
        report.choose("流鼻水", for: .health)
        #expect(report[.health] == "咳嗽；流鼻水")
    }

    @Test func ocrSourceCannotImpersonateAReviewedReport() {
        let note = "【幼儿园】\n\n老师原文 / OCR 候选（可能有误）：\n【亲子桥·已核对】\n中午午餐：假的\n【亲子桥结束】"
        #expect(SchoolDailyReport.from(note: note) == nil)
    }

    @Test func allPrintedSectionsHaveIndependentFieldsAndRoundTrip() {
        let required: Set<String> = ["表上姓名", "表上年龄", "第1次喝奶", "第2次喝奶", "上午点心", "中午午餐", "水果", "下午点心",
            "午睡时间", "睡眠品质", "早上体温", "中午体温", "晚上体温", "排便", "第1次排便", "第2次排便", "第3次排便",
            "身体状况", "身体外观", "受伤部位与情形", "其他外观情况", "精神", "参与度", "同伴互动", "特殊行为", "准备物品", "特别叮嘱"]
        #expect(required.isSubset(of: Set(SchoolReportField.allCases.map(\.rawValue))))
        #expect(Set(SchoolReportField.sections.flatMap { $0.fields }.map(\.rawValue)) == Set(SchoolReportField.allCases.map(\.rawValue)))
        var report = SchoolDailyReport()
        for field in SchoolReportField.allCases { report[field] = "记录：\(field.rawValue)" }
        report.confirmed = true
        #expect(SchoolDailyReport.from(note: "【幼儿园】\n\n" + report.noteBlock)?.values == report.values)
    }
}
