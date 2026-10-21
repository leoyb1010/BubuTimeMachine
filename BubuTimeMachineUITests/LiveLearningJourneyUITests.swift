import XCTest

/// 真实联调旅程：模拟器连接本机回环的测试服务（测试账号 + 第二大脑真实素材的只读快照）。
/// 只在显式提供 TEST_RUNNER_BUBU_UITEST_* 环境变量时运行，平时自动跳过。
final class LiveLearningJourneyUITests: XCTestCase {
    private var environment: [String: String] = [:]

    override func setUpWithError() throws {
        continueAfterFailure = false
        let source = ProcessInfo.processInfo.environment
        for key in ["BUBU_UITEST_PB_URL", "BUBU_UITEST_AI_URL", "BUBU_UITEST_EMAIL", "BUBU_UITEST_PASSWORD", "BUBU_UITEST_COURSE_FILES"] {
            if let value = source[key], !value.isEmpty { environment[key] = value }
        }
        try XCTSkipIf(environment["BUBU_UITEST_AI_URL"] == nil, "未提供联调服务，跳过真实旅程")
    }

    @MainActor
    private func launch(tab: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-seed", "-uitest-server-config", "-uitest-tab", String(tab)]
        app.launchEnvironment = environment
        app.launch()
        return app
    }

    @MainActor
    func testOnlineTimelineShowsSecondBrainPhotosAndVideos() throws {
        let app = launch(tab: 1)
        let first = app.buttons["timeline.item"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 90), "时光必须直接显示第二大脑的布布素材")
        let counts = app.staticTexts["timeline.online.counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 10))
        XCTAssertTrue(counts.label.contains("视频"), counts.label)
        sleep(3)
        shot("01-timeline-list", app)

        app.buttons["timeline.kind.video"].tap()
        XCTAssertTrue(app.staticTexts["timeline.online.total"].waitForExistence(timeout: 30))
        sleep(3)
        shot("02-timeline-videos", app)
        app.buttons["timeline.item"].firstMatch.tap()
        let play = app.buttons["timeline.video.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        play.tap()
        sleep(6)
        shot("03-timeline-video-detail", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["timeline.kind.all"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("南瓜")
        sleep(4)
        XCTAssertTrue(app.buttons["timeline.item"].firstMatch.waitForExistence(timeout: 30), "检索应命中已有解析")
        shot("04-timeline-search", app)
    }

    @MainActor
    func testDailyLearningUploadReviewPublishAndPlay() throws {
        try XCTSkipIf(environment["BUBU_UITEST_COURSE_FILES"] == nil, "未提供测试课程视频")
        let app = launch(tab: 5)
        let upload = app.buttons["learning.upload"]
        XCTAssertTrue(upload.waitForExistence(timeout: 60), "每日学习必须有独立上传入口")
        shot("10-learning-home", app)
        upload.tap()

        let title = app.textFields["learning.upload.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText("水果单词 UI联调")
        let submit = app.buttons["learning.upload.submit"]
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: submit)
        waitForExpectations(timeout: 30)
        shot("11-upload-form", app)
        submit.tap()

        let course = app.buttons["learning.course"].firstMatch
        XCTAssertTrue(course.waitForExistence(timeout: 300), "上传后应出现这节课")
        // iPad shows the upload form as a sheet; tap only once it has fully gone away.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: submit)
        waitForExpectations(timeout: 30)
        shot("12-course-listed", app)
        let detail = app.descendants(matching: .any)["learning.course.detail"]
        for _ in 0..<3 where !detail.exists {
            if course.isHittable { course.tap() }
            _ = detail.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(detail.exists, "点课程应打开课程详情")

        // 服务端完整解析老师原声并生成互动；家长核对按钮出现即为草稿就绪。
        let publish = app.buttons["learning.review.publish"]
        XCTAssertTrue(publish.waitForExistence(timeout: 900), "解析后应进入家长核对")
        sleep(3)
        shot("13-parent-review", app)
        let prompt = app.buttons["learning.review.prompt"].firstMatch
        if prompt.exists { prompt.tap(); sleep(3) }

        var guardCount = 0
        while guardCount < 12 {
            guardCount += 1
            let unchecked = app.switches.matching(identifier: "learning.review.check").allElementsBoundByIndex
                .first { ($0.value as? String) == "0" }
            guard let toggle = unchecked else { break }
            scrollUntilHittable(toggle, in: app)
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        let date = app.switches["learning.review.date"]
        scrollUntilHittable(date, in: app)
        if (date.value as? String) == "0" { date.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        scrollUntilHittable(publish, in: app)
        shot("14-review-checked", app)
        XCTAssertTrue(publish.isEnabled, "全部核对后才能开放")
        publish.tap()

        let play = app.buttons["learning.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 60), "开放后可以开始一起学")
        shot("15-published", app)
        play.tap()

        let listen = app.buttons["learning.play.listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: 20))
        sleep(3)
        shot("16-play-first", app)
        for step in 0..<8 {
            let choice = app.buttons["learning.play.choice"].firstMatch
            if choice.waitForExistence(timeout: 3) { choice.tap() }
            else {
                for label in ["说出来啦", "一起唱完啦"] where app.buttons[label].exists { app.buttons[label].tap(); break }
            }
            sleep(2)
            if step == 0 { shot("17-play-answered", app) }
            let next = app.buttons["learning.play.next"]
            guard next.waitForExistence(timeout: 5) else { break }
            next.tap()
            if app.buttons["learning.play.done"].waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(app.buttons["learning.play.done"].waitForExistence(timeout: 10))
        shot("18-play-finished", app)
        app.buttons["learning.play.done"].tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let week = app.buttons["learning.review.week"]
        scrollUntilHittable(week, in: app)
        week.tap()
        XCTAssertTrue(app.buttons["learning.review.start"].waitForExistence(timeout: 30), "开放的课程应进入本周复习")
        shot("19-week-review", app)
    }

    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while (!element.exists || !element.isHittable) && tries < 12 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
    }

    @MainActor
    private func shot(_ name: String, _ app: XCUIApplication) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["BUBU_UITEST_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
        }
    }
}
