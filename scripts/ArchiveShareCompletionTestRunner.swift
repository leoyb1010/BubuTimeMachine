// Standalone focused regression runner; does not require an iOS simulator.
import XCTest
import Darwin

@main
struct ArchiveShareCompletionTestRunner {
    static func main() {
        let suite = XCTestSuite(forTestCaseClass: ArchiveShareCompletionTests.self)
        suite.run()
        guard let run = suite.testRun, run.executionCount > 0 else { exit(2) }
        exit(run.totalFailureCount == 0 ? 0 : 1)
    }
}
