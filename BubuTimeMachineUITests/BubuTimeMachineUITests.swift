import XCTest
import UIKit

final class BubuTimeMachineUITests: XCTestCase {
    @MainActor
    func testAdaptiveRootAndQuickCapture() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed"]
        app.launch()

        // 两种形态各有各的记录入口，用例必须两边都认：
        // - 窄屏（iPhone）：系统底部附件 root.record。行内那个已经去掉了——
        //   底部附件常驻在屏幕下方，两处同名同功能会重复。
        // - 宽屏（iPad / Mac 侧栏）：没有底部附件
        //   （tabViewBottomAccessory(isEnabled: !isWide)），行内 home.record 是唯一入口。
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
        let identityCard = element(named: "home.identity-card", in: app)
        XCTAssertTrue(identityCard.waitForExistence(timeout: 5),
                      "iPhone 首页必须展示完整布布身份卡，不能用简化封面替代")
        let flipButton = app.buttons["home.identity-card.flip"]
        XCTAssertTrue(flipButton.waitForExistence(timeout: 3), "身份卡必须提供稳定、可发现的翻面按钮")
        flipButton.tap()
        let flipped = NSPredicate(format: "label == %@", "翻回身份卡正面")
        expectation(for: flipped, evaluatedWith: flipButton)
        waitForExpectations(timeout: 3)
        attachScreenshot("identity-card-back", to: self)
        flipButton.tap()
        let restoredFront = NSPredicate(format: "label == %@", "翻看身份卡背面")
        expectation(for: restoredFront, evaluatedWith: flipButton)
        waitForExpectations(timeout: 3)
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
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-timeline"]
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
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-open-first-moment"]
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
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed"]
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
    func testSpotlightPrivacyToggleCanBeReversed() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-settings"]
        app.launch()

        let toggle = app.switches["settings.spotlight"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        // 三次翻转都必须落到「读回的值确实变了」，而不是点完立刻读。
        // 旧写法在 CI 的模拟器上稳定失败：轻点已注册但 SwiftUI 状态还没提交，
        // 同步读到的仍是旧值。本机快、CI 慢，于是主干红了却没人看见。
        XCTAssertTrue(setSwitch(toggle, to: false), "关不掉 Spotlight 开关")
        XCTAssertTrue(setSwitch(toggle, to: true), "开不起 Spotlight 开关")
        XCTAssertTrue(setSwitch(toggle, to: false), "第二次关不掉 Spotlight 开关")
        attachScreenshot("spotlight-privacy-off", to: self)
    }

    /// 把开关拨到目标状态并等到读回的值确实变了。
    /// 已经是目标状态就直接返回 true（幂等）。不可点时先把它滚进可视区。
    @MainActor
    @discardableResult
    private func setSwitch(_ element: XCUIElement, to on: Bool,
                           timeout: TimeInterval = 5) -> Bool {
        let target = on ? "1" : "0"
        if element.value as? String == target { return true }
        if !element.isHittable {
            // Form 长页在小屏 iPhone 上会把开关顶出屏幕；轻点非 hittable 元素是静默无效的。
            app_scrollDown()
        }
        element.tap()
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", target),
            object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func app_scrollDown() {
        let scroll = XCUIApplication().scrollViews.firstMatch
        guard scroll.exists else { return }
        scroll.swipeUp()
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
