import Foundation
import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#if !YEARBOOK_PREFLIGHT_STANDALONE
@testable import BubuTimeMachine
#endif

nonisolated final class YearbookPhotoPreflightTests: XCTestCase {
    #if canImport(UIKit)
    @MainActor
    func testRepeatedYearbookExportsDoNotOverwriteSharedPDF() async throws {
        let exporter = YearbookExporter(mediaStore: MediaStore(), theme: BubuThemeDefinition.all[0])
        let title = "synthetic-\(UUID())"
        let firstInput = YearbookExporter.Input(childName: "Synthetic First", rangeTitle: title,
            coverImageFileName: nil, entries: [], milestones: [], messages: [])
        let first = try await exporter.makePDF(firstInput)
        defer { try? FileManager.default.removeItem(at: first) }
        let original = try Data(contentsOf: first)
        let secondInput = YearbookExporter.Input(childName: "Synthetic Second", rangeTitle: title,
            coverImageFileName: nil, entries: [], milestones: [], messages: [])
        let second = try await exporter.makePDF(secondInput)
        defer { try? FileManager.default.removeItem(at: second) }
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), original)
    }
    #endif

    private func withFixture(_ body: (URL, URL, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("YearbookPreflight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let valid = folder.appendingPathComponent("synthetic.png")
        let corrupt = folder.appendingPathComponent("corrupt.png")
        let missing = folder.appendingPathComponent("missing.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
                                              bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(valid as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try Data("synthetic non-image payload".utf8).write(to: corrupt)
        try body(valid, corrupt, missing)
    }

    func testValidPhotoAndTextOnlyBookPassPreflight() throws {
        try withFixture { valid, _, _ in
            XCTAssertNoThrow(try YearbookPhotoPreflight.requireAvailable([valid]))
            XCTAssertNoThrow(try YearbookPhotoPreflight.requireAvailable([]))
        }
    }

    func testPreflightChecksOnlyPhotosActuallyLaidOutButAlwaysChecksCover() throws {
        try withFixture { valid, _, missing in
            XCTAssertNoThrow(try YearbookPhotoPreflight.requireAvailable(pages: [[valid, valid, valid, valid, nil]], cover: nil))
            XCTAssertThrowsError(try YearbookPhotoPreflight.requireAvailable(pages: [[nil, valid, valid, valid, valid]], cover: nil))
            XCTAssertThrowsError(try YearbookPhotoPreflight.requireAvailable(pages: [[valid]], cover: missing))
        }
    }

    func testUndownloadedPhotoWithNoLocalFilenameIsBlocked() {
        XCTAssertThrowsError(try YearbookPhotoPreflight.requireAvailable([nil])) { error in
            XCTAssertEqual(error as? YearbookExportError, .unavailablePhotos(1))
        }
    }

    func testMissingAndCorruptFilesAreBothBlocked() throws {
        try withFixture { _, corrupt, missing in
            for url in [missing, corrupt] {
                XCTAssertThrowsError(try YearbookPhotoPreflight.requireAvailable([url])) { error in
                    XCTAssertEqual(error as? YearbookExportError, .unavailablePhotos(1))
                }
            }
        }
    }

    func testMixedSelectionReportsEveryUnavailablePhoto() throws {
        try withFixture { valid, corrupt, missing in
            XCTAssertThrowsError(try YearbookPhotoPreflight.requireAvailable([valid, nil, missing, corrupt])) { error in
                XCTAssertEqual(error as? YearbookExportError, .unavailablePhotos(3))
                XCTAssertTrue(error.localizedDescription.contains("3"))
                XCTAssertTrue(error.localizedDescription.contains("同步与备份"))
            }
        }
    }

    #if YEARBOOK_PREFLIGHT_STANDALONE
    func testYearbookDoesNotDiscardUndownloadedPhotoReferences() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BubuTimeMachine/Features/Settings/YearbookView.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        XCTAssertFalse(text.contains(".filter { $0.type == .photo }.compactMap { $0.localFileName }"),
                       "Missing local originals must remain in the preflight input rather than silently disappearing.")
    }
    #endif
}
