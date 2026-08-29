import XCTest
import UIKit

final class BubuTimeMachineUITests: XCTestCase {
    @MainActor
    func testAdaptiveRootAndQuickCapture() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-seed"]
        app.launch()

        let globalRecord = app.buttons["root.record"]
        let homeRecord = app.buttons["home.record"]
        let record: XCUIElement
        if globalRecord.waitForExistence(timeout: 2) {
            record = globalRecord
        } else {
            record = homeRecord
            XCTAssertTrue(record.waitForExistence(timeout: 6), "自适应根导航必须保留记录入口")
        }
        XCTAssertTrue(element(named: "首页", in: app).exists)
        XCTAssertTrue(element(named: "时光", in: app).exists)
        XCTAssertTrue(element(named: "成长", in: app).exists)
        XCTAssertTrue(element(named: "魔法屋", in: app).exists)
        attachScreenshot("adaptive-root", to: self)

        record.tap()
        XCTAssertTrue(app.navigationBars["记录此刻"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["保存"].exists)
        attachScreenshot("quick-capture", to: self)

        app.buttons["以后再说"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
    }

    @MainActor
    func testTimelineProbeRendersAndSearches() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-seed", "-uitest-timeline"]
        app.launch()

        XCTAssertTrue(app.navigationBars["时光轴"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(element(named: "2026年8月", in: app).exists || app.scrollViews.firstMatch.exists)
        attachScreenshot("timeline", to: self)
    }

    @MainActor
    func testColdMomentDeepLinkOpensExactEntry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-seed", "-uitest-open-first-moment"]
        app.launch()

        let note = app.staticTexts["布布今天第一次自己扶着沙发站起来了！"]
        XCTAssertTrue(note.waitForExistence(timeout: 10), "冷启动系统搜索必须直达具体时光，不能停在空白页")
        attachScreenshot("moment-deeplink", to: self)
    }

    @MainActor
    func testIPadLandscapeKeepsNavigationAndRecord() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-seed"]
        app.launch()

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["home.record"].waitForExistence(timeout: 8))
        XCTAssertTrue(element(named: "首页", in: app).exists)
        XCTAssertTrue(element(named: "时光", in: app).exists)
        XCTAssertTrue(element(named: "成长", in: app).exists)
        XCTAssertTrue(element(named: "魔法屋", in: app).exists)
        attachScreenshot("ipad-landscape-root", to: self)
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func element(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: name).firstMatch
    }

    @MainActor
    private func attachScreenshot(_ name: String, to testCase: XCTestCase) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}
