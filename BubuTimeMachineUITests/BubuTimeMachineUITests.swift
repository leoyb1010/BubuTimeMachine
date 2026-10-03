import XCTest
import UIKit

final class BubuTimeMachineUITests: XCTestCase {
    @MainActor
    func testMemberSaveFailureRetainsDraftAndRetryAddsExactlyOnce() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-members", "-uitest-member-fail-save"]
        app.launch()
        XCTAssertTrue(app.buttons["添加家庭成员"].waitForExistence(timeout: 12))
        app.buttons["添加家庭成员"].tap()
        let name = app.textFields["显示名字"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        attachScreenshot("members-editor-before-save", to: self)
        name.tap(); name.typeText("测试家人")
        app.buttons["保存"].tap()
        let failure = app.alerts["没有保存成功"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        attachScreenshot("members-save-failure-retains-draft", to: self)
        failure.buttons["好"].tap()
        XCTAssertEqual(name.value as? String, "测试家人")
        app.buttons["保存"].tap()
        let added = app.buttons["切换到测试家人"]
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "切换到测试家人").count, 1)
        app.buttons["编辑测试家人"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "测试家人")
        app.buttons["取消"].tap()
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        attachScreenshot("members-save-retry-once-and-reopen", to: self)
    }

    @MainActor
    func testCurrentMemberDeleteFailureKeepsIdentityUntilRetry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-members", "-uitest-member-fail-delete"]
        app.launch()
        let current = app.buttons["切换到妈妈"]
        XCTAssertTrue(current.waitForExistence(timeout: 12))
        current.tap()
        let cell = app.cells.containing(.button, identifier: "切换到妈妈").firstMatch
        XCTAssertTrue(cell.exists)
        XCTAssertTrue(cell.staticTexts["当前"].exists)
        cell.swipeLeft()
        app.buttons["删除"].tap()
        app.buttons["删除「妈妈」"].tap()
        let failure = app.alerts["提示"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        attachScreenshot("members-delete-failure-preserves-identity", to: self)
        failure.buttons["好"].tap()
        XCTAssertTrue(current.exists)
        XCTAssertTrue(cell.staticTexts["当前"].exists)
        cell.swipeLeft(); app.buttons["删除"].tap(); app.buttons["删除「妈妈」"].tap()
        XCTAssertTrue(current.waitForNonExistence(timeout: 5))
        let fallback = app.cells.containing(.button, identifier: "切换到姥姥").firstMatch
        XCTAssertTrue(fallback.staticTexts["当前"].waitForExistence(timeout: 5))
        attachScreenshot("members-delete-retry-switches-after-save", to: self)
    }

    @MainActor
    func testRootTabsRemainSelectableInsideChildRecognitionSettings() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed"]
        app.launch()
        let settings = app.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 12))
        settings.tap()
        let recognition = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "认布布与精选")).firstMatch
        XCTAssertTrue(recognition.waitForExistence(timeout: 5))
        recognition.tap()
        XCTAssertTrue(app.navigationBars["认布布与精选"].waitForExistence(timeout: 5))
        app.swipeUp()
        assertRootNavigation(in: app)
        attachScreenshot("tabs-visible-in-recognition-settings", to: self)
        rootNavigationButton(named: "时光", in: app).tap()
        XCTAssertTrue(app.navigationBars["时光轴"].waitForExistence(timeout: 5))
        assertRootNavigation(in: app)
        rootNavigationButton(named: "首页", in: app).tap()
        assertRootNavigation(in: app)
    }

    @MainActor
    func testRootTabsStaySelectableAfterScrollingAndQuickCapture() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-school-report"]
        app.launch()
        XCTAssertTrue(app.buttons["root.record"].waitForExistence(timeout: 12) || app.buttons["home.record"].waitForExistence(timeout: 5))
        attachScreenshot("tabs-initial", to: self)
        assertRootNavigation(in: app)

        for _ in 0..<2 {
            for name in ["首页", "时光", "成长", "幼儿园"] {
                rootNavigationButton(named: name, in: app).tap()
                app.swipeUp()
                app.swipeUp()
                attachScreenshot("tabs-after-scrolling-" + name, to: self)
                assertRootNavigation(in: app)
            }
        }

        rootNavigationButton(named: "首页", in: app).tap()
        let record = app.buttons["root.record"].isHittable ? app.buttons["root.record"] : app.buttons["home.record"]
        for _ in 0..<2 {
            if !record.isHittable { app.swipeDown(); app.swipeDown() }
            XCTAssertTrue(record.isHittable)
            record.tap()
            XCTAssertTrue(app.navigationBars["记录此刻"].waitForExistence(timeout: 5))
            app.buttons["以后再说"].tap()
            assertRootNavigation(in: app)
            app.swipeUp()
            assertRootNavigation(in: app)
        }
        rootNavigationButton(named: "时光", in: app).tap()
        XCTAssertTrue(app.navigationBars["时光轴"].waitForExistence(timeout: 5))
        attachScreenshot("tabs-restored-after-recording", to: self)
    }

    @MainActor
    private func rootNavigationButton(named name: String, in app: XCUIApplication) -> XCUIElement {
        let native = app.tabBars.buttons.matching(identifier: name).firstMatch
        if native.exists && native.isHittable { return native }
        return app.buttons.matching(identifier: name).allElementsBoundByIndex.first(where: { $0.isHittable })
            ?? app.buttons.matching(identifier: name).firstMatch
    }

    @MainActor
    private func assertRootNavigation(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let names = ["首页", "时光", "成长", "幼儿园"]
        let buttons = names.map { rootNavigationButton(named: $0, in: app) }
        for (index, button) in buttons.enumerated() {
            guard button.exists else {
                XCTFail("根导航缺少页面入口：" + names[index], file: file, line: line)
                return
            }
            print("Root navigation \(names[index]): id=\(button.identifier), frame=\(button.frame), hittable=\(button.isHittable)")
            XCTAssertTrue(button.exists && button.isHittable, "滚动或关闭记录后必须仍可选择：" + names[index], file: file, line: line)
            XCTAssertTrue(app.frame.contains(CGPoint(x: button.frame.midX, y: button.frame.midY)), file: file, line: line)
            XCTAssertGreaterThanOrEqual(button.frame.width, 40, "Tab不能收缩成不可选择的小点", file: file, line: line)
        }
        for index in 0..<(buttons.count - 1) {
            // Native tab hit rectangles include touch slop and may overlap a few
            // points. Their centers, rather than their expanded AX bounds, must
            // remain separate so each page can be selected directly.
            let dx = abs(buttons[index].frame.midX - buttons[index + 1].frame.midX)
            let dy = abs(buttons[index].frame.midY - buttons[index + 1].frame.midY)
            XCTAssertGreaterThanOrEqual(max(dx, dy), 44, "四个页面必须保留独立点击区域", file: file, line: line)
        }
    }

    func testSystemPickerBoundsTolerateOnlySubpixelRounding() {
        let viewport = CGRect(x: 0, y: 300, width: 440, height: 500)
        let observed = CGRect(x: -0.0000008477, y: 329.9999975, width: 145.5555573, height: 145.6666718)
        XCTAssertTrue(Self.pickerContains(viewport, asset: observed))
        XCTAssertFalse(Self.pickerContains(viewport, asset: observed.offsetBy(dx: -1, dy: 0)))
        XCTAssertFalse(Self.pickerContains(viewport, asset: CGRect(x: 10, y: 299, width: 100, height: 100)))
        XCTAssertFalse(Self.pickerContains(viewport, asset: CGRect(x: 10, y: 750, width: 100, height: 100)))
        XCTAssertFalse(Self.pickerContains(.zero, asset: observed))
        XCTAssertFalse(Self.pickerContains(viewport, asset: .zero))
    }

    private static func pickerContains(_ bounds: CGRect, asset: CGRect) -> Bool {
        guard !bounds.isEmpty, !asset.isEmpty else { return false }
        let center = CGPoint(x: asset.midX, y: asset.midY)
        // Native Photos AX sometimes reports an edge at -0.0000008 instead of 0.
        // Keep the actual tap center strictly inside and permit only half a point
        // of edge rounding; genuinely clipped/offscreen assets remain rejected.
        return bounds.contains(center) && bounds.insetBy(dx: -0.5, dy: -0.5).contains(asset)
    }

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
        let navigation = systemPickerNavigation(in: app)
        let content = app.scrollViews["photosView_content_scroll_view"].firstMatch
        guard navigation.waitForExistence(timeout: 30), content.waitForExistence(timeout: 30) else {
            throw systemPickerFailure("Photos picker did not become ready", in: app)
        }
        // Scope to the actual Photos grid, not unrelated or stale app images.
        let grid = content.otherElements["PXGGridLayout-Group"].firstMatch
        let asset = NSPredicate(format: "identifier == %@ AND (label BEGINSWITH[c] %@ OR label BEGINSWITH %@)",
                                "PXGGridLayout-Info", labels.english, labels.chinese)
        let image = grid.images.matching(asset).firstMatch
        guard grid.waitForExistence(timeout: 30), image.waitForExistence(timeout: 30) else {
            throw systemPickerFailure("Missing synthetic \(labels.english) asset", in: app)
        }
        let confirmation = systemPickerConfirmation(in: app)
        let requiresConfirmation = confirmation.exists
        let beganWithEmptySelection = requiresConfirmation && systemPickerSelectionIsEmpty(grid: grid, confirmation: confirmation)
        let assetLabel = image.label
        attachScreenshot("school-system-picker-before-\(labels.english)", to: self)
        // The captured iPhone/iPad AX hierarchies have no asset Cells. These
        // informational image leaves have valid frames but no computed hit point.
        // Use only the fresh leaf center after bounding it to the active picker.
        let appBounds = app.frame
        let contentBounds = content.frame.intersection(appBounds)
        let navigationBounds = navigation.frame
        let pickerBounds = CGRect(x: contentBounds.minX,
                                  y: max(contentBounds.minY, navigationBounds.maxY),
                                  width: contentBounds.width,
                                  height: max(0, contentBounds.maxY - max(contentBounds.minY, navigationBounds.maxY)))
        let assetBounds = image.frame
        guard navigation.exists, content.exists, image.exists,
              !pickerBounds.isEmpty, !assetBounds.isEmpty,
              Self.pickerContains(pickerBounds, asset: assetBounds),
              Self.pickerContains(grid.frame, asset: assetBounds) else {
            throw systemPickerFailure("\(labels.english) asset is outside the active picker viewport: \(assetBounds)", in: app)
        }
        print("PhotosPicker selecting \(image.label), asset=\(assetBounds), viewport=\(pickerBounds)")
        if image.isHittable {
            image.tap()
        } else {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: assetBounds.midX - appBounds.minX,
                dy: assetBounds.midY - appBounds.minY)).tap()
        }
        if requiresConfirmation {
            if !confirmation.wait(for: \.isEnabled, toEqual: true, timeout: 15) {
                // Hosted iPad evidence showed one unconfirmed tap: the same asset
                // remained unselected and Done stayed disabled. Retry only that
                // observed empty state, never a picker with an existing selection.
                let canRetry = beganWithEmptySelection &&
                    canRetryEmptySystemPicker(in: app, assetLabel: assetLabel, assetBounds: assetBounds)
                // AX inspection may outlast a delayed successful selection. Let the
                // caller confirm and verify its import instead of tapping it again.
                if confirmation.exists && confirmation.isEnabled { return }
                guard canRetry else {
                    throw systemPickerFailure("Selecting \(labels.english) did not enable Done/Add; empty-state retry is unsafe", in: app)
                }
                let state = "PhotosPicker one-time empty-selection retry: \(assetLabel), frame=\(assetBounds), Done/Add disabled\n\(app.debugDescription)"
                print(state)
                let attachment = XCTAttachment(string: state)
                attachment.name = "school-system-picker-empty-selection-retry"
                attachment.lifetime = .keepAlways
                add(attachment)
                attachScreenshot("school-system-picker-empty-selection-retry", to: self)
                // Screenshot/AX capture can take time. Reobserve immediately before
                // tapping so a delayed successful selection is never toggled off.
                let remainsEmpty = canRetryEmptySystemPicker(in: app, assetLabel: assetLabel, assetBounds: assetBounds)
                if confirmation.exists && confirmation.isEnabled { return }
                guard remainsEmpty else {
                    throw systemPickerFailure("Picker selection changed before the bounded retry", in: app)
                }
                let retryImage = grid.images.matching(NSPredicate(
                    format: "identifier == %@ AND label == %@", "PXGGridLayout-Info", assetLabel)).firstMatch
                if retryImage.isHittable {
                    retryImage.tap()
                } else {
                    let retryAppBounds = app.frame
                    app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                        dx: assetBounds.midX - retryAppBounds.minX,
                        dy: assetBounds.midY - retryAppBounds.minY)).tap()
                }
                guard confirmation.wait(for: \.isEnabled, toEqual: true, timeout: 15) else {
                    throw systemPickerFailure("Selecting \(labels.english) did not enable Done/Add after one empty-state retry", in: app)
                }
            }
        } else if !content.waitForNonExistence(timeout: 15) {
            throw systemPickerFailure("Selecting \(labels.english) did not dismiss the single-selection picker", in: app)
        }
    }

    @MainActor
    private func systemPickerSelectionIsEmpty(grid: XCUIElement, confirmation: XCUIElement) -> Bool {
        guard grid.exists, confirmation.exists, !confirmation.isEnabled else { return false }
        let assets = grid.images.matching(identifier: "PXGGridLayout-Info").allElementsBoundByIndex
        return !assets.isEmpty && assets.allSatisfy { $0.exists && !$0.isSelected } && !confirmation.isEnabled
    }

    @MainActor
    private func canRetryEmptySystemPicker(in app: XCUIApplication, assetLabel: String, assetBounds: CGRect) -> Bool {
        let navigation = systemPickerNavigation(in: app)
        let content = app.scrollViews["photosView_content_scroll_view"].firstMatch
        let grid = content.otherElements["PXGGridLayout-Group"].firstMatch
        let confirmation = systemPickerConfirmation(in: app)
        let matchingAssets = grid.images.matching(NSPredicate(
            format: "identifier == %@ AND label == %@", "PXGGridLayout-Info", assetLabel))
        guard navigation.exists, content.exists, content.isHittable, grid.exists, matchingAssets.count == 1,
              matchingAssets.firstMatch.frame == assetBounds,
              !matchingAssets.firstMatch.isSelected,
              systemPickerSelectionIsEmpty(grid: grid, confirmation: confirmation) else { return false }
        let visible = content.frame.intersection(app.frame)
        let top = max(visible.minY, navigation.frame.maxY)
        let pickerBounds = CGRect(x: visible.minX, y: top, width: visible.width,
                                  height: max(0, visible.maxY - top))
        return !pickerBounds.isEmpty && !assetBounds.isEmpty &&
            Self.pickerContains(pickerBounds, asset: assetBounds) &&
            Self.pickerContains(grid.frame, asset: assetBounds) &&
            confirmation.exists && !confirmation.isEnabled
    }

    @MainActor
    private func systemPickerNavigation(in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.matching(NSPredicate(
            format: "identifier == %@ OR identifier == %@ OR label == %@ OR label == %@",
            "Photos", "照片", "Photos", "照片")).firstMatch
    }

    @MainActor
    private func systemPickerConfirmation(in app: XCUIApplication) -> XCUIElement {
        systemPickerNavigation(in: app).buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@ OR label == %@ OR label == %@",
            "Done", "完成", "Add", "添加")).firstMatch
    }

    @MainActor
    private func confirmSystemPickerSelection(in app: XCUIApplication,
                                              allowsAutomaticDismissal: Bool = false) throws {
        let content = app.scrollViews["photosView_content_scroll_view"].firstMatch
        if allowsAutomaticDismissal && !content.exists { return }
        let confirmation = systemPickerConfirmation(in: app)
        guard confirmation.waitForExistence(timeout: 10),
              confirmation.wait(for: \.isEnabled, toEqual: true, timeout: 10),
              confirmation.wait(for: \.isHittable, toEqual: true, timeout: 10) else {
            throw systemPickerFailure("Picker Done/Add button never became enabled and hittable", in: app)
        }
        confirmation.tap()
        guard content.waitForNonExistence(timeout: 15) else {
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
    func testNaturalCaptureCancelThenSaveReturnsToTimeline() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-in-memory", "-uitest-seed", "-uitest-natural-local", "-uitest-natural-fail-save"]
        app.launch()
        let globalRecord = app.buttons["root.record"]
        let record = globalRecord.waitForExistence(timeout: 12) ? globalRecord : app.buttons["home.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 20))
        record.tap()
        let natural = app.buttons["打开一句话智能记录"]
        XCTAssertTrue(natural.waitForExistence(timeout: 8))
        natural.tap()
        // A populated SwiftUI vertical TextField no longer exposes its placeholder
        // as its identifier after sheet dismissal; use stable semantic identity.
        let field = app.descendants(matching: .any).matching(identifier: "natural.input").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        let note = "Synthetic review audit memory"
        field.typeText(note)
        app.buttons["识别并保存这句话"].tap()
        XCTAssertTrue(app.navigationBars["确认保存"].waitForExistence(timeout: 8))
        attachScreenshot("natural-review-before-cancel", to: self)
        app.navigationBars["确认保存"].buttons["取消"].tap()
        XCTAssertTrue(app.buttons["识别并保存这句话"].waitForExistence(timeout: 8))
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertEqual(field.value as? String, note, "取消确认页必须保留原文")
        app.buttons["识别并保存这句话"].tap()
        XCTAssertTrue(app.navigationBars["确认保存"].waitForExistence(timeout: 8))
        app.navigationBars["确认保存"].buttons["保存"].tap()
        XCTAssertTrue(app.alerts["没能保存"].waitForExistence(timeout: 8))
        attachScreenshot("natural-review-save-failure-retains-draft", to: self)
        app.alerts["没能保存"].buttons["返回重试"].tap()
        XCTAssertTrue(app.alerts["没能保存"].waitForNonExistence(timeout: 8), "错误提示必须真正退出后才能重试")
        let retrySave = app.navigationBars["确认保存"].buttons["保存"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: retrySave)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        XCTAssertTrue(app.navigationBars["确认保存"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[note].firstMatch.exists, "保存失败后确认内容不能消失")
        app.navigationBars["确认保存"].buttons["保存"].tap()
        let returnedToInput = app.navigationBars["一句话智能记录"].waitForExistence(timeout: 8)
        if !returnedToInput {
            attachScreenshot("natural-retry-final-state", to: self)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "natural-retry-final-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(returnedToInput, "重试保存后应回到智能记录输入页")
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.buttons["以后再说"].waitForExistence(timeout: 8))
        app.buttons["以后再说"].tap()
        let timeline = element(named: "时光", in: app)
        XCTAssertTrue(timeline.waitForExistence(timeout: 8))
        timeline.tap()
        XCTAssertTrue(app.staticTexts[note].firstMatch.waitForExistence(timeout: 8), "已保存内容必须从真实 SwiftData 回到时光页")
        attachScreenshot("natural-review-saved-timeline", to: self)
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
        let reviewBar = app.switches["school.confirmed"]
        let isReviewBar = element.identifier == "school.confirmed"
        let isTextInput = element.elementType == .textField || element.elementType == .textView
        let scroll = app.scrollViews.containing(element.elementType, identifier: element.identifier).firstMatch
        // Keep the last observed viewport only while AX drops an offscreen child;
        // refresh it whenever available, since keyboard dismissal resizes sheets.
        var lastScrollBounds: CGRect?
        var attemptedKeyboardDismissal = false
        for _ in 0..<18 {
            let appBounds = app.frame
            if scroll.exists { lastScrollBounds = scroll.frame.intersection(appBounds) }
            let bounds = lastScrollBounds ?? appBounds
            let navBottom = app.navigationBars["记幼儿园的一天"].frame.maxY
            let top = max(bounds.minY, navBottom) + 16
            var bottom = bounds.maxY - 16
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists, keyboard.frame.intersects(bounds), keyboard.frame.minY > top {
                bottom = min(bottom, keyboard.frame.minY - 12)
            }
            if !isReviewBar, reviewBar.exists, !reviewBar.frame.isEmpty,
               reviewBar.frame.intersects(bounds), reviewBar.frame.minY > top {
                bottom = min(bottom, reviewBar.frame.minY - 12)
            }
            let target = element.frame
            if element.isHittable && target.minY >= top && target.maxY <= bottom { return }
            guard lastScrollBounds != nil, bottom - top > 60, bounds.width > 48 else { break }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let x = bounds.maxX - 24 - appBounds.minX

            if !isTextInput, keyboard.exists, !attemptedKeyboardDismissal {
                // The form uses interactive keyboard dismissal. Do it inside the
                // live sheet viewport before chasing controls around its animation.
                attemptedKeyboardDismissal = true
                let start = origin.withOffset(CGVector(dx: x, dy: top + 12 - appBounds.minY))
                let end = origin.withOffset(CGVector(dx: x, dy: bottom - 12 - appBounds.minY))
                start.press(forDuration: 0.05, thenDragTo: end)
                _ = keyboard.waitForNonExistence(timeout: 3)
                continue
            }
            if !element.isHittable, target.midY > top, target.midY < bottom,
               element.wait(for: \.isHittable, toEqual: true, timeout: 1) { continue }

            let middle = (top + bottom) / 2
            let maximumStep = min(120, (bottom - top) * 0.45)
            var offset = max(-maximumStep, min(maximumStep, middle - target.midY))
            // A nonhittable centered control previously produced a zero-length
            // gesture for all 18 retries. Always move, and keep both points visible.
            if abs(offset) < 30 { offset = offset < 0 ? -30 : 30 }
            let start = origin.withOffset(CGVector(dx: x, dy: middle - offset / 2 - appBounds.minY))
            let end = origin.withOffset(CGVector(dx: x, dy: middle + offset / 2 - appBounds.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        print("School control reveal failed: \(element.identifier)\n\(app.debugDescription)")
        attachScreenshot("school-control-reveal-failure", to: self)
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
