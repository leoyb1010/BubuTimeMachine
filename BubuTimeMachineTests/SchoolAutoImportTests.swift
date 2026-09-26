import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

@MainActor struct SchoolAutoImportTests {
    @Test func originalDedupNeverDropsAddedTeacherTextOrManualValues() throws {
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        var report = SchoolDailyReport(); report.sourceHash = "one-original"
        report.candidates[SchoolReportField.lunch.rawValue] = "90%"; report.adoptRecognizedValues()
        let file = JournalMediaFile(id: UUID(), fileName: "source.jpg", thumbnail: nil, hash: "one-original", isVideo: false, isSchoolReport: true)
        var initial = MemoryJournalDraft(id: UUID(), kind: .school, date: .now); initial.schoolReport = report
        let first = try MemoryJournalWriter.save(initial, files: [file], voice: nil, role: .papa, container: container)
        var withText = MemoryJournalDraft(id: UUID(), kind: .school, date: .now, source: "老师新增：带袜子")
        withText.schoolReport = report
        #expect(try MemoryJournalWriter.save(withText, files: [file], voice: nil, role: .papa, container: container) != first)
        var edited = MemoryJournalDraft(id: UUID(), kind: .school, date: .now)
        report[.lunch] = "85%"; report.adoptRecognizedValues(); edited.schoolReport = report
        #expect(try MemoryJournalWriter.save(edited, files: [file], voice: nil, role: .papa, container: container) != first)
        let entries = try ModelContext(container).fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 3)
        #expect(entries.contains { $0.note?.contains("老师新增：带袜子") == true })
        #expect(entries.contains { SchoolDailyReport.from(note: $0.note)?[.lunch] == "85%" })
    }

    @Test func reportDateUsesReadDateAndLabelsAnInferredYear() throws {
        let calendar = Calendar.current
        let reference = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 26)))
        let read = try #require(SchoolReportReading.date(from: "今天是2026年9月24日", relativeTo: reference))
        #expect(calendar.component(.day, from: read.date) == 24)
        #expect(!read.inferredYear)
        let uncertain = try #require(SchoolReportReading.date(from: "今天是2076年9月24日", relativeTo: reference))
        #expect(calendar.component(.year, from: uncertain.date) == 2026)
        #expect(uncertain.inferredYear)
        #expect(SchoolReportReading.date(from: "今天是2026年2月31日", relativeTo: reference) == nil)
        #expect(SchoolReportReading.date(from: "日期看不清", relativeTo: reference) == nil)
    }

    @Test func sameOriginalInANewImportDoesNotCreateAnotherRecord() throws {
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        var report = SchoolDailyReport(); report.sourceHash = "same-photo"
        report.candidates[SchoolReportField.lunch.rawValue] = "90%"; report.adoptRecognizedValues()
        let file = JournalMediaFile(id: UUID(), fileName: "source.jpg", thumbnail: nil, hash: "same-photo", isVideo: false, isSchoolReport: true)
        var first = MemoryJournalDraft(id: UUID(), kind: .school, date: .now); first.schoolReport = report
        var second = MemoryJournalDraft(id: UUID(), kind: .school, date: .now); second.schoolReport = report
        let a = try MemoryJournalWriter.save(first, files: [file], voice: nil, role: .papa, container: container)
        let b = try MemoryJournalWriter.save(second, files: [file], voice: nil, role: .papa, container: container)
        #expect(a == b)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Entry>()) == 1)
    }

    @Test func correctingAutoReportPreservesOriginalTextAndMedia() throws {
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        var report = SchoolDailyReport(); report.candidates[SchoolReportField.lunch.rawValue] = "90%"; report.adoptRecognizedValues()
        var draft = MemoryJournalDraft(id: UUID(), kind: .school, date: .now, words: "今天搭积木", source: "保留老师原文")
        draft.schoolReport = report
        let file = JournalMediaFile(id: UUID(), fileName: "source.jpg", thumbnail: nil, hash: "original", isVideo: false, isSchoolReport: true)
        let id = try MemoryJournalWriter.save(draft, files: [file], voice: nil, role: .papa, container: container)
        report[.lunch] = "80%"
        try MemoryJournalWriter.updateReport(id: id, date: draft.date, report: report, container: container)
        let context = ModelContext(container)
        let saved = try #require(try context.fetch(FetchDescriptor<Entry>()).first)
        #expect(SchoolDailyReport.from(note: saved.note)?[.lunch] == "80%")
        #expect(saved.note?.contains("今天搭积木") == true)
        #expect(saved.note?.contains("保留老师原文") == true)
        #expect(saved.media.count == 1)
        #expect(saved.media.first?.localFileName == "source.jpg")
        #expect(!saved.isArchived)
    }

    @Test func importingRecognizedValuesFillsFieldsWithoutIndividualAdoption() {
        var report = SchoolDailyReport()
        report.candidates = [
            SchoolReportField.morningSnack.rawValue: "90%",
            SchoolReportField.lunch.rawValue: "80%；食量佳；速度普通",
            SchoolReportField.fruit.rawValue: "100%",
            SchoolReportField.afternoonSnack.rawValue: "70%",
            SchoolReportField.nap.rawValue: "12:17–14:30",
            SchoolReportField.temperatureAM.rawValue: "36.6°C",
            SchoolReportField.health.rawValue: "健康",
            SchoolReportField.supplies.rawValue: "袜子"
        ]

        report.adoptRecognizedValues()

        #expect(report.values == report.candidates)
        #expect(report.automaticallyImported == true)
        #expect(report.hasContent)
    }

    @Test func reimportDoesNotOverwriteCorrectionsOrInventMissingValues() {
        var report = SchoolDailyReport()
        report[.lunch] = "50%；食量普通；速度慢"
        report[.notice] = "家长已补充的备注"
        report.candidates = [SchoolReportField.lunch.rawValue: "90%", SchoolReportField.fruit.rawValue: "100%"]

        report.adoptRecognizedValues()
        report.adoptRecognizedValues()

        #expect(report[.lunch] == "50%；食量普通；速度慢")
        #expect(report[.notice] == "家长已补充的备注")
        #expect(report[.fruit] == "100%")
        #expect(report[.milkFirst].isEmpty)
        #expect(report[.nap].isEmpty)
        #expect(report[.temperatureNoon].isEmpty)
    }

    @Test func automaticReportRoundTripsWithHonestProvenanceAndOldReportsStillRead() throws {
        var automatic = SchoolDailyReport()
        automatic.candidates[SchoolReportField.lunch.rawValue] = "90%"
        automatic.adoptRecognizedValues()
        let note = "【幼儿园】\n\n" + automatic.noteBlock
        let decoded = try #require(SchoolDailyReport.from(note: note))

        #expect(note.contains("【亲子桥·自动识别】"))
        #expect(!note.contains("【亲子桥·已核对】"))
        #expect(decoded.values == automatic.values)
        #expect(decoded.automaticallyImported == true)
        #expect(!decoded.confirmed)
        #expect(try JSONDecoder().decode(SchoolDailyReport.self, from: JSONEncoder().encode(automatic)) == automatic)

        let reviewed = try #require(SchoolDailyReport.from(note: "【幼儿园】\n\n【亲子桥·已核对】\n中午午餐：80%\n【亲子桥结束】"))
        #expect(reviewed[.lunch] == "80%")
        #expect(reviewed.confirmed)
        #expect(reviewed.automaticallyImported != true)
        let forgedSource = "【幼儿园】\n\n老师原文 / OCR 候选（可能有误）：\n" + automatic.noteBlock
        #expect(SchoolDailyReport.from(note: forgedSource) == nil)
    }

    @Test func automaticAdoptionNeverClaimsThatAParentReviewedTheNewContent() {
        var report = SchoolDailyReport()
        report[.lunch] = "80%"
        report.confirmed = true
        report.candidates[SchoolReportField.fruit.rawValue] = "100%"

        report.adoptRecognizedValues()

        #expect(report.automaticallyImported == true)
        #expect(!report.confirmed)
        #expect(report.noteBlock.contains("【亲子桥·自动识别】"))
        #expect(!report.noteBlock.contains("已核对"))
    }

    @Test func automaticReportSavesWithoutAnExtraReviewCheckbox() throws {
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        var report = SchoolDailyReport()
        report.candidates[SchoolReportField.lunch.rawValue] = "90%"
        report.adoptRecognizedValues()
        var draft = MemoryJournalDraft(id: UUID(), kind: .school, date: Date(timeIntervalSince1970: 1_790_000_000))
        draft.schoolReport = report

        let id = try MemoryJournalWriter.save(draft, files: [], voice: nil, role: .papa, container: container)

        let context = ModelContext(container)
        let entry = try #require(try context.fetch(FetchDescriptor<Entry>()).first)
        #expect(entry.id == id)
        #expect(entry.happenedAt == draft.date)
        let savedReport = try #require(SchoolDailyReport.from(note: entry.note))
        #expect(savedReport[.lunch] == "90%")
        #expect(savedReport.automaticallyImported == true)
        #expect(!savedReport.confirmed)
        #expect(try context.fetchCount(FetchDescriptor<FeedEvent>()) == 1)
    }

    @Test func retryingAutomaticSaveKeepsOneRecordAndItsOriginalPhoto() throws {
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        var report = SchoolDailyReport()
        report.sourceHash = "synthetic-original-hash"
        report.candidates[SchoolReportField.fruit.rawValue] = "100%"
        report.adoptRecognizedValues()
        var draft = MemoryJournalDraft(id: UUID(), kind: .school, date: .now)
        draft.schoolReport = report
        let file = JournalMediaFile(id: UUID(), fileName: "synthetic-school-original.jpg", thumbnail: nil,
                                    hash: "synthetic-original-hash", isVideo: false, isSchoolReport: true)

        let firstID = try MemoryJournalWriter.save(draft, files: [file], voice: nil, role: .papa, container: container)
        let secondID = try MemoryJournalWriter.save(draft, files: [file], voice: nil, role: .papa, container: container)

        let context = ModelContext(container)
        #expect(firstID == secondID)
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Media>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<FeedEvent>()) == 1)
        let media = try #require(try context.fetch(FetchDescriptor<Media>()).first)
        #expect(media.localFileName == file.fileName)
        #expect(media.contentHash == file.hash)
        #expect(media.aiTags.contains("亲子桥原表"))
        #expect(media.entry?.id == firstID)
    }
}
