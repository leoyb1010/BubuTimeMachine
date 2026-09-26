import Foundation
import Testing
import UIKit
@testable import BubuTimeMachine

/// Real file-boundary tests: PhotosPicker providers need not preserve a useful suffix.
/// Fixtures are generated locally; no family photos, Photos library, or server are used.
@MainActor struct JournalImportRegressionTests {
    @Test func recognitionFailureKeepsOriginalAndEditableUnconfirmedReport() async throws {
        let url = fixtureURL().appendingPathExtension("jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try jpeg(text: "亲子桥")
        try data.write(to: url)
        let store = MediaStore()
        let result = try await JournalImport.prepare(url: url, report: true, store: store, recognize: { _ in
            throw CocoaError(.coderReadCorrupt)
        })
        defer { store.deleteLocalFiles(media: result.file.fileName, thumbnail: result.file.thumbnail) }
        #expect(result.warning != nil)
        #expect(result.schoolReport?.confirmed == false)
        #expect(result.schoolReport?.sourceHash == result.file.hash)
        #expect(result.file.isSchoolReport == true)
        #expect(try Data(contentsOf: store.mediaURL(for: result.file.fileName)) == data)
    }

    @Test func extensionlessJPEGImportsAndPreservesOriginalBytes() async throws {
        let url = fixtureURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try jpeg()
        try data.write(to: url)
        let store = MediaStore()

        let result = try await JournalImport.prepare(url: url, report: false, store: store)
        defer { store.deleteLocalFiles(media: result.file.fileName, thumbnail: result.file.thumbnail) }

        #expect(!result.file.isVideo)
        #expect(result.file.fileName.hasSuffix(".jpg"))
        #expect(result.file.thumbnail != nil)
        #expect(result.file.hash == MediaStore.sha256Hex(data))
        #expect(try Data(contentsOf: store.mediaURL(for: result.file.fileName)) == data)
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func genericProviderSuffixDoesNotRejectDecodableJPEG() async throws {
        let url = fixtureURL().appendingPathExtension("tmp")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try jpeg()
        try data.write(to: url)
        let store = MediaStore()

        let result = try await JournalImport.prepare(url: url, report: false, store: store)
        defer { store.deleteLocalFiles(media: result.file.fileName, thumbnail: result.file.thumbnail) }

        #expect(result.file.fileName.hasSuffix(".jpg"))
        #expect(!result.file.isVideo)
        #expect(try Data(contentsOf: store.mediaURL(for: result.file.fileName)) == data)
    }

    @Test func extensionlessReportStillRecognizesTextAndCreatesEditableReport() async throws {
        let url = fixtureURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try jpeg(text: "亲子桥\n午睡：12:10 到 13:30")
        try data.write(to: url)
        let store = MediaStore()

        let result = try await JournalImport.prepare(url: url, report: true, store: store)
        defer { store.deleteLocalFiles(media: result.file.fileName, thumbnail: result.file.thumbnail) }

        #expect(result.recognizedText.contains("12:10"), "OCR evidence: \(result.recognizedText)")
        #expect(result.file.isSchoolReport == true)
        let report = try #require(result.schoolReport)
        #expect(!report.confirmed)
        #expect(report.values.isEmpty)
        #expect(report.sourceHash == MediaStore.sha256Hex(data))
        #expect(try Data(contentsOf: store.mediaURL(for: result.file.fileName)) == data)
    }

    @Test func unreadableReportStillRetainsOriginalAndAllowsManualEntry() async throws {
        let url = fixtureURL().appendingPathExtension("jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try jpeg()
        try data.write(to: url)
        let store = MediaStore()

        let result = try await JournalImport.prepare(url: url, report: true, store: store)
        defer { store.deleteLocalFiles(media: result.file.fileName, thumbnail: result.file.thumbnail) }

        var report = try #require(result.schoolReport)
        #expect(result.recognizedText.isEmpty)
        #expect(result.file.isSchoolReport == true)
        #expect(report.sourceHash == MediaStore.sha256Hex(data))
        #expect(!report.confirmed)
        report[.lunch] = "90%"
        report.confirmed = true
        #expect(report.noteBlock.contains("90%"))
        #expect(try Data(contentsOf: store.mediaURL(for: result.file.fileName)) == data)
    }

    @Test func invalidExtensionlessFileIsRejectedWithoutChangingSource() async throws {
        let url = fixtureURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("not a photograph or a movie".utf8)
        try data.write(to: url)

        await #expect(throws: (any Error).self) {
            try await JournalImport.prepare(url: url, report: true, store: MediaStore())
        }
        #expect(try Data(contentsOf: url) == data)
    }

    private func fixtureURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("journal-regression-\(UUID())")
    }

    private func jpeg(text: String = "") throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 360)).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 1000, height: 360))
            (text as NSString).draw(in: CGRect(x: 40, y: 40, width: 920, height: 280),
                withAttributes: [.font: UIFont.systemFont(ofSize: 56), .foregroundColor: UIColor.black])
        }
        return try #require(image.jpegData(compressionQuality: 0.95))
    }
}
