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
        app.launchArguments = ["-uitest-seed", "-uitest-server-config", "-uitest-skip-consent", "-uitest-tab", String(tab)]
        app.launchEnvironment = environment
        app.launch()
        return app
    }

    /// 来源与类型都收在「筛选」菜单里：先展开菜单，再点选项（标识符取不到时按文字找）。
    @MainActor
    private func pickFilter(_ identifier: String, label: String, in app: XCUIApplication) {
        let menu = app.buttons["timeline.filter"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "缺少筛选菜单")
        menu.tap()
        let byID = app.buttons[identifier].firstMatch
        let option = byID.waitForExistence(timeout: 3) ? byID : app.buttons[label].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "筛选菜单里缺少「\(label)」")
        option.tap()
    }

    @MainActor
    func testOnlineTimelineShowsSecondBrainPhotosAndVideos() throws {
        let app = launch(tab: 1)
        let first = app.buttons["timeline.item"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 90), "时光必须直接显示第二大脑的布布素材")
        // 数量在导航副标题里（照片 N · 视频 N）。
        let counts = app.navigationBars.staticTexts.containing(NSPredicate(format: "label CONTAINS '视频'")).firstMatch
        XCTAssertTrue(counts.waitForExistence(timeout: 10), "导航副标题应显示照片/视频数量")
        sleep(3)
        shot("01-timeline-list", app)

        pickFilter("timeline.kind.video", label: "只看视频", in: app)
        XCTAssertTrue(app.staticTexts["timeline.online.total"].waitForExistence(timeout: 30))
        sleep(3)
        shot("02-timeline-videos", app)
        app.buttons["timeline.item"].firstMatch.tap()
        let play = app.buttons["timeline.video.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        play.tap()
        sleep(6)
        shot("03-timeline-video-detail", app)
        app.tapNavigationBack()

        pickFilter("timeline.kind.all", label: "不限类型", in: app)
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
        let unique = "水果单词 " + String(Int(Date().timeIntervalSince1970) % 100_000)
        title.typeText(unique)
        let submit = app.buttons["learning.upload.submit"]
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: submit)
        waitForExpectations(timeout: 30)
        shot("11-upload-form", app)
        submit.tap()

        // Upload (compression + one request per file) finishes when the sheet closes.
        let closed = NSPredicate(format: "exists == false")
        let waiter = XCTNSPredicateExpectation(predicate: closed, object: submit)
        if XCTWaiter().wait(for: [waiter], timeout: 300) != .completed {
            shot("11b-upload-stuck", app)
            XCTFail("上传表单没有关闭")
            return
        }
        let course = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                      "learning.course", unique)).firstMatch
        XCTAssertTrue(course.waitForExistence(timeout: 30), "上传后应出现这节课")
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
        let original = app.buttons["learning.review.original"].firstMatch
        scrollUntilHittable(original, in: app)
        XCTAssertTrue(original.exists, "核对时应能看提问前后的原片片段")
        original.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 20))
        sleep(6)
        shot("13b-original-clip", app)
        app.buttons["完成"].tap()
        sleep(1)

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
            if choice.waitForExistence(timeout: 3) {
                // 2.29：选错会温柔提示再选一次，依次点选项直到出现「下一个」。
                for option in app.buttons.matching(identifier: "learning.play.choice").allElementsBoundByIndex {
                    if app.buttons["learning.play.next"].exists { break }
                    if option.isHittable { option.tap(); sleep(1) }
                }
            } else {
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

        app.tapNavigationBack()
        let week = app.buttons["learning.review.week"]
        scrollUntilHittable(week, in: app)
        week.tap()
        XCTAssertTrue(app.buttons["learning.review.start"].waitForExistence(timeout: 30), "开放的课程应进入本周复习")
        shot("19-week-review", app)
    }

    @MainActor
    func testConsentAppearsOnceBeforeSecondBrainContent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-seed", "-uitest-server-config", "-uitest-tab", "1"]
        app.launchEnvironment = environment
        app.launch()
        let accept = app.buttons["consent.accept"]
        if accept.waitForExistence(timeout: 20) {
            shot("20-consent", app)
            accept.tap()
        }
        XCTAssertTrue(app.buttons["timeline.item"].firstMatch.waitForExistence(timeout: 90))
        app.terminate()
        app.launch()
        XCTAssertFalse(app.buttons["consent.accept"].waitForExistence(timeout: 6), "确认过一次后不再弹出")
    }

    @MainActor
    func testUpgrade225Surfaces() throws {
        let app = launch(tab: 1)
        XCTAssertTrue(app.buttons["timeline.item"].firstMatch.waitForExistence(timeout: 90))
        XCTAssertTrue(app.buttons["timeline.filter"].exists, "时光应有筛选菜单（全部/照片视频/家人写的）")
        sleep(2)
        shot("21-timeline-merged", app)
        pickFilter("timeline.source.family", label: "家人写的", in: app)
        XCTAssertTrue(app.buttons["timeline.family"].firstMatch.waitForExistence(timeout: 15), "家人记录应出现在时光里")
        shot("22-timeline-family", app)
        pickFilter("timeline.source.brain", label: "照片视频", in: app)
        let scrubber = app.descendants(matching: .any)["timeline.scrubber"]
        if !scrubber.waitForExistence(timeout: 15), let folder = ProcessInfo.processInfo.environment["BUBU_UITEST_SHOTS"] {
            try? app.debugDescription.write(toFile: folder + "/scrubber-tree.txt", atomically: true, encoding: .utf8)
            shot("22b-brain-no-scrubber", app)
        }
        XCTAssertTrue(scrubber.exists, "按月拖动条")
        let person = app.buttons["timeline.person"].firstMatch
        if person.waitForExistence(timeout: 10) {
            person.tap()
            let someone = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '和'")).firstMatch
            XCTAssertTrue(someone.waitForExistence(timeout: 5), "人物菜单应列出家人")
            someone.tap()
            XCTAssertTrue(app.staticTexts["timeline.online.total"].waitForExistence(timeout: 20))
            sleep(2)
            shot("23-timeline-person", app)
            person.tap()
            app.buttons["不限"].firstMatch.tap()
        }
        pickFilter("timeline.source.merged", label: "全部", in: app)

        app.buttons["timeline.menu"].tap()
        app.buttons["认一认"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["brain.recognition"].waitForExistence(timeout: 20))
        sleep(4)
        shot("24-recognition", app)
        app.tapNavigationBack()
        app.buttons["timeline.menu"].tap()
        app.buttons["每月成长小报"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["brain.monthly"].waitForExistence(timeout: 20))
        sleep(5)
        shot("25-monthly", app)
        app.tapNavigationBack()

        // 首页回忆与生日倒计时
        let home = app.tabBars.buttons["首页"].firstMatch.exists ? app.tabBars.buttons["首页"].firstMatch : app.buttons["首页"].firstMatch
        home.tap()
        let memory = app.buttons["home.memory"].firstMatch
        scrollUntilHittable(memory, in: app)
        XCTAssertTrue(memory.waitForExistence(timeout: 30), "首页应有今日回忆")
        shot("26-home-memories", app)
        memory.tap()
        XCTAssertTrue(app.buttons["timeline.item"].firstMatch.waitForExistence(timeout: 10) || app.otherElements.firstMatch.exists)
        sleep(3)
        shot("27-memory-detail", app)
    }

    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while (!element.exists || !element.isHittable) && tries < 40 {
            app.swipeUp()
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
