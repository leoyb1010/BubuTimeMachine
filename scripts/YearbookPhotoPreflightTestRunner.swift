// Focused macOS regression runner; no simulator or real family photos.
import XCTest
import Darwin

@main
struct YearbookPhotoPreflightTestRunner {
    static func main() {
        let suite = XCTestSuite(forTestCaseClass: YearbookPhotoPreflightTests.self)
        suite.run()
        guard let run = suite.testRun, run.executionCount > 0 else { exit(2) }
        exit(run.totalFailureCount == 0 ? 0 : 1)
    }
}
