import XCTest
import UIKit

final class BubuTimeMachineUITests: XCTestCase {
    @MainActor
    func testSchoolReferenceHeaderCanOpenHistoryAndReturn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-tab", "3", "-uitest-school-report"]
        app.launch()
        XCTAssertTrue(app.buttons["school.history"].waitForExistence(timeout: 12))
        app.buttons["school.history"].tap()
        XCTAssertTrue(app.navigationBars["幼儿园回忆"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["journal.primary"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPreviouslyImportedSchoolDraftFinishesAutomaticallyAfterUpgrade() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-tab", "3", "-uitest-legacy-school-draft"]
        app.launch()
        XCTAssertTrue(app.staticTexts["每日亲子桥"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["90%"].exists)
        XCTAssertTrue(app.staticTexts["school.record-status"].label.contains("自动记录"))
        XCTAssertTrue(app.buttons["school.saved-original"].exists)
        attachScreenshot("school-legacy-import-completed-automatically", to: self)
    }

    @MainActor
    func testSchoolImportCanBeStoppedWithoutLockingNextDraft() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-tab", "3", "-uitest-journal-slow-import"]
        app.launch()
        XCTAssertTrue(app.buttons["journal.primary"].waitForExistence(timeout: 12))
        app.buttons["journal.primary"].tap()
        app.buttons["老师照片 / 视频"].tap()
        try tapSystemPickerAsset(.photo, in: app)
        try confirmSystemPickerSelection(in: app)
        XCTAssertTrue(app.buttons["停止导入"].waitForExistence(timeout: 5))
        app.buttons["停止导入"].tap()
        XCTAssertTrue(app.buttons["school.manual-report"].isEnabled)
        XCTAssertFalse(app.staticTexts["已选 1 个素材"].exists)
        app.buttons["以后再说"].tap()
        XCTAssertTrue(app.buttons["journal.primary"].waitForExistence(timeout: 5))
        app.buttons["journal.primary"].tap()
        XCTAssertTrue(app.buttons["school.manual-report"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["school.manual-report"].isEnabled, "取消的迟到任务不能锁住下一份草稿")
        attachScreenshot("school-import-cancel-and-reopen", to: self)
    }

    @MainActor
    func testSchoolSystemPhotoPickerImportsReport() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-tab", "3"]
        app.launch()
        XCTAssertTrue(app.buttons["journal.primary"].waitForExistence(timeout: 12))
        app.buttons["journal.primary"].tap()
        app.buttons["读一张亲子桥"].tap()
        attachScreenshot("school-system-picker-open", to: self)
        try tapSystemPickerAsset(.photo, in: app)
        try confirmSystemPickerSelection(in: app, allowsAutomaticDismissal: true)
        // No text entry, no candidate adoption, no review toggle, no save tap.
        XCTAssertTrue(app.staticTexts["每日亲子桥"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["school.record-status"].label.contains("自动记录"))
        XCTAssertTrue(app.staticTexts["90%"].exists)
        XCTAssertTrue(app.staticTexts["100%"].exists)
        XCTAssertTrue(app.staticTexts["80%"].exists)
        XCTAssertTrue(app.staticTexts["70%"].exists)
        XCTAssertTrue(app.buttons["school.saved-original"].exists)
        attachScreenshot("school-one-step-auto-filled-and-saved", to: self)
        app.buttons["school.correct-report"].tap()
        let amount = app.textFields["school.field.上午点心"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (amount.value as? String ?? "").count) + "85%")
        app.buttons["school.correction-save"].tap()
        attachScreenshot("school-after-correction", to: self)
        XCTAssertTrue(app.staticTexts["85%"].waitForExistence(timeout: 5))
        // Reimport the identical original: retain the correction and keep a single memory.
        app.buttons["journal.primary"].tap()
        app.buttons["读一张亲子桥"].tap()
        try tapSystemPickerAsset(.photo, in: app)
        try confirmSystemPickerSelection(in: app, allowsAutomaticDismissal: true)
        XCTAssertTrue(app.staticTexts["85%"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts.matching(identifier: "每日亲子桥").count, 1)
        attachScreenshot("school-auto-correct-and-deduplicate", to: self)
    }

    @MainActor
    func testSchoolSystemPhotoPickerImportsPhotoAndVideo() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-tab", "3"]
        app.launch()
        XCTAssertTrue(app.buttons["journal.primary"].waitForExistence(timeout: 12))
        app.buttons["journal.primary"].tap()
        app.buttons["老师照片 / 视频"].tap()
        try tapSystemPickerAsset(.video, in: app)
        try tapSystemPickerAsset(.photo, in: app)
        try confirmSystemPickerSelection(in: app)
        XCTAssertTrue(app.staticTexts["已选 2 个素材"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["journal.save"].isEnabled)
        attachScreenshot("school-system-mixed-import", to: self)
        app.buttons["journal.save"].tap()
        XCTAssertTrue(app.staticTexts["老师镜头里的她"].waitForExistence(timeout: 8), "只选照片视频、不填写文字的日记也必须出现在幼儿园")
    }

    private enum SystemPickerAsset {
        case photo, video

        var labels: (english: String, chinese: String) {
            switch self {
            case .photo: return ("Photo", "照片")
            case .video: return ("Video", "视频")
            }
        }
    }

    @MainActor
    private func tapSystemPickerAsset(_ kind: SystemPickerAsset, in app: XCUIApplication) throws {
        let labels = kind.labels
        // The app is Chinese, but the hosted simulator's system picker is English.
        let asset = NSPredicate(format: "identifier == %@ AND (label BEGINSWITH[c] %@ OR label BEGINSWITH %@)",
                                "PXGGridLayout-Info", labels.english, labels.chinese)
        let images = app.images.matching(asset)
        guard images.firstMatch.waitForExistence(timeout: 15) else {
            throw systemPickerFailure("Missing synthetic \(labels.english) asset", in: app)
        }
        // iOS 26 exposes PXGGridLayout-Info as an informational descendant: it can
        // have a visible frame but no hit point. Tap its actual containing cell.
        let cell = app.cells.containing(asset).firstMatch
        if cell.waitForExistence(timeout: 3) {
            guard cell.wait(for: \.isHittable, toEqual: true, timeout: 12) else {
                throw systemPickerFailure("\(labels.english) picker cell never became hittable", in: app)
            }
            cell.tap()
            return
        }
        // Some picker versions expose the asset itself as the tappable element.
        // This fallback still requires a real hit point; never tap coordinates
        // derived from a nonhittable informational image.
        let image = images.firstMatch
        guard image.wait(for: \.isHittable, toEqual: true, timeout: 12) else {
            throw systemPickerFailure("No hittable \(labels.english) picker asset or containing cell", in: app)
        }
        image.tap()
    }

    @MainActor
    private func confirmSystemPickerSelection(in app: XCUIApplication,
                                              allowsAutomaticDismissal: Bool = false) throws {
        let add = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Add", "添加")).firstMatch
        if allowsAutomaticDismissal && !add.waitForExistence(timeout: 2) {
            // Single-selection pickers may close as soon as the asset is tapped.
            // The caller still verifies the actual OCR/import/save result.
            guard app.images.matching(identifier: "PXGGridLayout-Info").firstMatch.waitForNonExistence(timeout: 5) else {
                throw systemPickerFailure("Single-selection picker neither dismissed nor offered Add", in: app)
            }
            return
        }
        guard add.waitForExistence(timeout: 10),
              add.wait(for: \.isEnabled, toEqual: true, timeout: 10),
              add.wait(for: \.isHittable, toEqual: true, timeout: 10) else {
            throw systemPickerFailure("Picker Add button never became enabled and hittable", in: app)
        }
        add.tap()
        guard app.images.matching(identifier: "PXGGridLayout-Info").firstMatch.waitForNonExistence(timeout: 10) else {
            throw systemPickerFailure("Picker did not dismiss after confirming selection", in: app)
        }
    }

    @MainActor
    private func systemPickerFailure(_ message: String, in app: XCUIApplication) -> NSError {
        let hierarchy = app.debugDescription
        print("PhotosPicker failure: \(message)\n\(hierarchy)")
        let attachment = XCTAttachment(string: hierarchy)
        attachment.name = "school-system-picker-failure-hierarchy"
        attachment.lifetime = .keepAlways
        add(attachment)
        attachScreenshot("school-system-picker-failure", to: self)
        return NSError(domain: "BubuSystemPickerUITest", code: 1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    @MainActor
    func testSchoolGraphicJournalDisplaysEveryReportGroup() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-tab", "3", "-uitest-school-report"]
        app.launch()
        XCTAssertTrue(app.staticTexts["每日亲子桥"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["100%"].exists)
        attachScreenshot("school-graphic-life", to: self)
        for name in ["午睡", "体温", "在园表现", "身体与外观", "排便", "老师叮嘱"] {
            let section = app.staticTexts[name].firstMatch
            for _ in 0..<8 where !section.isHittable { app.swipeUp() }
            XCTAssertTrue(section.exists)
            if name == "体温" { attachScreenshot("school-graphic-nap-temperature", to: self) }
            if name == "身体与外观" { attachScreenshot("school-graphic-observations", to: self) }
        }
        XCTAssertTrue(app.staticTexts["明天带上替换衣物（验收样例）"].exists)
        attachScreenshot("school-graphic-notes", to: self)
    }

    @MainActor
    func testSchoolOriginalCanBeComparedAfterAutomaticSave() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-tab", "3", "-uitest-school-import"]
        app.launch()
        let original = app.buttons["school.saved-original"]
        XCTAssertTrue(original.waitForExistence(timeout: 20))
        for _ in 0..<4 where !original.isHittable { app.swipeUp() }
        XCTAssertTrue(original.isEnabled)
        original.tap()
        XCTAssertTrue(app.navigationBars["亲子桥原表"].waitForExistence(timeout: 5))
        attachScreenshot("school-original-comparison", to: self)
        app.buttons["看好了"].tap()
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        XCTAssertTrue(original.isEnabled, "原表随自动记录保存，可随时对照")
        XCTAssertTrue(app.buttons["journal.primary"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSchoolReportRequiresReviewAndSavesReadableFields() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-tab", "3"]
        app.launch()
        XCTAssertTrue(app.buttons["journal.primary"].waitForExistence(timeout: 12))
        attachScreenshot("school-journal-redesigned", to: self)
        app.buttons["journal.primary"].tap()
        XCTAssertTrue(app.buttons["school.manual-report"].waitForExistence(timeout: 5))
        app.buttons["school.manual-report"].tap()
        for (name, amount) in [("上午点心", "90%"), ("中午午餐", "90%"), ("水果", "100%"), ("下午点心", "90%")] {
            let field = app.descendants(matching: .any).matching(identifier: "school.field.\(name)").firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            revealSchoolControl(field, in: app)
            field.tap(); field.typeText(amount)
            let appetite = app.segmentedControls["school.appetite.\(name)"]
            revealSchoolControl(appetite, in: app)
            appetite.buttons["佳"].tap()
            let speed = app.segmentedControls["school.speed.\(name)"]
            revealSchoolControl(speed, in: app)
            speed.buttons[name == "水果" ? "快" : "普通"].tap()
        }
        XCTAssertFalse(app.buttons["journal.save"].isEnabled)
        // Dismiss keyboard without changing the draft, then reach its explicit review gate.
        app.swipeDown()
        let reviewed = app.switches["school.confirmed"]
        revealSchoolControl(reviewed, in: app)
        XCTAssertTrue(reviewed.isHittable)
        reviewed.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["journal.save"].isEnabled)
        attachScreenshot("school-reviewed-form", to: self)
        app.buttons["journal.save"].tap()
        XCTAssertTrue(app.staticTexts["每日亲子桥"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["一天四餐"].exists)
        XCTAssertTrue(app.staticTexts["100%"].exists)
        for name in ["上午点心", "中午午餐", "水果", "下午点心"] { XCTAssertTrue(app.staticTexts[name].exists) }
        attachScreenshot("school-four-meals-saved", to: self)
        for name in ["午睡", "体温", "在园表现", "身体与外观", "排便", "老师叮嘱"] {
            let section = app.staticTexts[name].firstMatch
            for _ in 0..<6 where !section.isHittable { app.swipeUp() }
            XCTAssertTrue(section.exists, "原表栏目不能因为没有填值而消失：\(name)")
        }
        attachScreenshot("school-all-sections", to: self)
    }

    @MainActor
    func testSayingDraftCanBeResumedAndExplicitlyDiscarded() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-sayings"]
        app.launch()
        XCTAssertTrue(app.buttons["journal.primary"].waitForExistence(timeout: 12))
        app.buttons["journal.primary"].tap()
        let words = app.descendants(matching: .any).matching(identifier: "journal.words").firstMatch
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        words.tap(); words.typeText("草稿里的小星星")
        app.buttons["以后再说"].tap()
        app.buttons["留在草稿，下次继续"].tap()
        XCTAssertTrue(app.buttons["journal.primary"].waitForExistence(timeout: 5))
        app.buttons["journal.primary"].tap()
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        XCTAssertEqual(words.value as? String, "草稿里的小星星")
        app.buttons["以后再说"].tap()
        app.buttons["丢弃草稿"].tap()
        XCTAssertTrue(app.buttons["journal.primary"].waitForExistence(timeout: 5))
        app.buttons["journal.primary"].tap()
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        XCTAssertNotEqual(words.value as? String, "草稿里的小星星")
        app.buttons["以后再说"].tap()
    }

    @MainActor
    func testSchoolJournalSavesIntoTimelineAndKeepsIdentity() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-tab", "3"]
        app.launch()
        XCTAssertTrue(app.buttons["journal.primary"].waitForExistence(timeout: 12))
        attachScreenshot("school-empty", to: self)
        app.buttons["journal.primary"].tap()
        let words = app.descendants(matching: .any).matching(identifier: "journal.words").firstMatch
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        words.tap(); words.typeText("今天在幼儿园搭了小房子")
        app.buttons["journal.save"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "搭了小房子")).firstMatch.waitForExistence(timeout: 8))
        attachScreenshot("school-saved", to: self)
        element(named: "时光", in: app).tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "搭了小房子")).firstMatch.waitForExistence(timeout: 8))
    }

    @MainActor
    func testSayingsTextCanBeSavedWithoutMicrophone() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-sayings"]
        app.launch()
        XCTAssertTrue(app.buttons["journal.primary"].waitForExistence(timeout: 12))
        app.buttons["journal.primary"].tap()
        let words = app.descendants(matching: .any).matching(identifier: "journal.words").firstMatch
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        words.tap(); words.typeText("月亮也要睡觉吗？")
        attachScreenshot("saying-compose", to: self)
        app.buttons["journal.save"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "月亮也要睡觉吗")).firstMatch.waitForExistence(timeout: 8))
        attachScreenshot("saying-saved", to: self)
    }

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
        // 超时给足：这条用例是套件里第一个跑的，要付冷启动 + 种子数据的钱，
        // iPad 上实测 50 秒量级，CI 的 runner 还要更慢。
        // 之前 2 秒/6 秒的余量在 CI 上会随机失败——门禁一旦不稳就等于没有门禁。
        if globalRecord.waitForExistence(timeout: 12) {
            record = globalRecord
        } else {
            record = homeRecord
            XCTAssertTrue(record.waitForExistence(timeout: 20), "自适应根导航必须保留记录入口")
        }
        XCTAssertTrue(element(named: "首页", in: app).exists)
        XCTAssertTrue(element(named: "时光", in: app).exists)
        XCTAssertTrue(element(named: "成长", in: app).exists)
        XCTAssertTrue(element(named: "幼儿园", in: app).exists)
        let identityCard = element(named: "home.identity-card", in: app)
        XCTAssertTrue(identityCard.waitForExistence(timeout: 15),
                      "iPhone 首页必须展示完整布布身份卡，不能用简化封面替代")
        let flipButton = app.buttons["home.identity-card.flip"]
        XCTAssertTrue(flipButton.waitForExistence(timeout: 10), "身份卡必须提供稳定、可发现的翻面按钮")
        flipButton.tap()
        let flipped = NSPredicate(format: "label == %@", "翻回身份卡正面")
        expectation(for: flipped, evaluatedWith: flipButton)
        // 云端 runner 的可访问性快照有额外延迟；仍验证真实翻面结果，给状态同步留足时间。
        waitForExpectations(timeout: 10)
        attachScreenshot("identity-card-back", to: self)
        flipButton.tap()
        let restoredFront = NSPredicate(format: "label == %@", "翻看身份卡背面")
        expectation(for: restoredFront, evaluatedWith: flipButton)
        waitForExpectations(timeout: 10)
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
        XCTAssertTrue(element(named: "幼儿园", in: app).exists)
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
    private func revealSchoolControl(_ element: XCUIElement, in app: XCUIApplication) {
        let visibleTop = app.navigationBars["记幼儿园的一天"].frame.maxY + 12
        let reviewBar = app.switches["school.confirmed"]
        let isReviewBar = element.identifier == "school.confirmed"
        let footerTop = !isReviewBar && reviewBar.exists ? reviewBar.frame.minY - 12 : app.frame.maxY
        let visibleBottom = min(footerTop, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY)
        if element.isHittable && element.frame.midY > visibleTop && element.frame.midY < visibleBottom { return }
        let scroll = app.scrollViews.containing(element.elementType, identifier: element.identifier).firstMatch
        XCTAssertTrue(scroll.exists)
        // Capture the sheet viewport before scrolling. A descendant-based query can
        // stop matching mid-gesture when SwiftUI drops an offscreen AX descendant.
        let bounds = scroll.frame
        for _ in 0..<18 {
            let navBottom = app.navigationBars["记幼儿园的一天"].frame.maxY
            let keyboard = app.keyboards.firstMatch
            let currentFooterTop = !isReviewBar && reviewBar.exists ? reviewBar.frame.minY - 12 : bounds.maxY
            let bottom = min(currentFooterTop, min(bounds.maxY, keyboard.exists ? keyboard.frame.minY : bounds.maxY)) - 24
            let top = max(bounds.minY, navBottom) + 24
            let center = element.frame.midY
            if element.isHittable && center > top && center < bottom { return }
            // iPad sheets do not fill the screen. An app-wide fling can overshoot the
            // field above the sheet's navigation bar even while AX reports it hittable.
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: bounds.maxX - 12, dy: (top + bottom) / 2))
            let offset = max(-150, min(150, (top + bottom) / 2 - center))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: offset)))
        }
        XCTFail("表单控件未进入可见区域：\(element.identifier)")
    }

    @MainActor
    /// 按 identifier 找元素。
    /// `descendants(matching: .any)` 会遍历**整棵**无障碍树，在 iPad 的侧栏 + 长页上很贵，
    /// 而这个 helper 每条用例要调四五次。先走按类型的快路径（几乎都是按钮或静态文本），
    /// 找不到再回退到全树遍历，语义不变、代价小得多。
    private func element(named name: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons.matching(identifier: name).firstMatch
        if button.exists { return button }
        let text = app.staticTexts.matching(identifier: name).firstMatch
        if text.exists { return text }
        return app.descendants(matching: .any).matching(identifier: name).firstMatch
    }

    @MainActor
    private func attachScreenshot(_ name: String, to testCase: XCTestCase) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}
