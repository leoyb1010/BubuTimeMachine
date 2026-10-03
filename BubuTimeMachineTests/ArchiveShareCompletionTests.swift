import Foundation
import XCTest
#if !ARCHIVE_SHARE_STANDALONE
@testable import BubuTimeMachine
#endif
#if canImport(UIKit)
import UIKit
#endif

nonisolated final class ArchiveShareCompletionTests: XCTestCase {
    #if canImport(UIKit)
    @MainActor
    func testShareSheetForwardsCancellationAndErrorsUnchanged() {
        var receivedCompletion: Bool?
        var receivedError: NSError?
        let sheet = ShareSheet(items: ["Synthetic archive"]) { completed, error in
            receivedCompletion = completed
            receivedError = error as NSError?
        }
        let controller = sheet.makeActivityController()
        controller.completionWithItemsHandler?(nil, false, nil, nil)
        XCTAssertEqual(receivedCompletion, false)
        XCTAssertNil(receivedError)
        let failure = NSError(domain: "SyntheticShareFailure", code: 17)
        controller.completionWithItemsHandler?(nil, true, nil, failure)
        XCTAssertEqual(receivedCompletion, true)
        XCTAssertEqual(receivedError, failure)
    }

    @MainActor
    func testExistingShareSheetCallersNeedNoCompletionHandler() {
        let controller = ShareSheet(items: ["Synthetic archive"]).makeActivityController()
        controller.completionWithItemsHandler?(nil, false, nil, nil)
    }
    #endif

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "ArchiveShareCompletionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    func testCompleteArchiveUpdatesTimestampOnlyAfterSuccessfulShare() {
        withDefaults { defaults in
            let archive = ArchiveExportShare(url: URL(fileURLWithPath: "/tmp/synthetic-full.zip"), isComplete: true)
            XCTAssertNil(defaults.object(forKey: "bubu.lastExportAt"))
            archive.recordCompletion(completed: true, error: nil, defaults: defaults,
                                     at: Date(timeIntervalSince1970: 200))
            XCTAssertEqual(defaults.double(forKey: "bubu.lastExportAt"), 200)
        }
    }

    func testCancellationAndErrorPreservePriorExportTimestamp() {
        withDefaults { defaults in
            defaults.set(100.0, forKey: "bubu.lastExportAt")
            let archive = ArchiveExportShare(url: URL(fileURLWithPath: "/tmp/synthetic-full.zip"), isComplete: true)
            archive.recordCompletion(completed: false, error: nil, defaults: defaults,
                                     at: Date(timeIntervalSince1970: 200))
            XCTAssertEqual(defaults.double(forKey: "bubu.lastExportAt"), 100)
            archive.recordCompletion(completed: true, error: NSError(domain: "SyntheticShareFailure", code: 1),
                                     defaults: defaults, at: Date(timeIntervalSince1970: 300))
            XCTAssertEqual(defaults.double(forKey: "bubu.lastExportAt"), 100)
        }
    }

    func testIncompleteShareCannotInheritEarlierCompleteArchiveEligibility() {
        withDefaults { defaults in
            let full = ArchiveExportShare(url: URL(fileURLWithPath: "/tmp/synthetic-full.zip"), isComplete: true)
            full.recordCompletion(completed: true, error: nil, defaults: defaults,
                                  at: Date(timeIntervalSince1970: 100))
            let partial = ArchiveExportShare(url: URL(fileURLWithPath: "/tmp/synthetic-partial.zip"), isComplete: false)
            partial.recordCompletion(completed: true, error: nil, defaults: defaults,
                                     at: Date(timeIntervalSince1970: 200))
            XCTAssertEqual(defaults.double(forKey: "bubu.lastExportAt"), 100)
        }
    }

    func testCancelledFirstExportDoesNotCreateTimestamp() {
        withDefaults { defaults in
            let archive = ArchiveExportShare(url: URL(fileURLWithPath: "/tmp/synthetic-full.zip"), isComplete: true)
            archive.recordCompletion(completed: false, error: nil, defaults: defaults)
            XCTAssertNil(defaults.object(forKey: "bubu.lastExportAt"))
        }
    }

    #if ARCHIVE_SHARE_STANDALONE
    // Source guard supplements behavioral tests on the development host only;
    // installed device tests must never depend on access to the checkout.
    func testGeneratingArchiveDoesNotMarkItExportedBeforeShareCompletion() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BubuTimeMachine/Features/Settings/ExportView.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        XCTAssertFalse(text.contains("UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: \"bubu.lastExportAt\")"),
                       "Generating a temporary ZIP is not a completed export; cancellation must not mark backup health as current.")
    }
    #endif
}
