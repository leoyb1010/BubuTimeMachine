import XCTest

/// iPhone Duo 尺寸矩阵：外屏竖 / 横（466×678 / 678×466）、内屏竖 / 横（669×951 / 951×669），
/// 以及内屏书本半折（951×669 + 竖直假折痕）和桌面半折（669×951 + 水平假折痕）。
///
/// 每个尺寸怎么跑（只看当前模拟器窗口，不按机型猜）：
/// - 窗口正好是这个尺寸（Duo 外屏竖拿 / 横拿、Duo 内屏）→ 原生跑：真实的竖排栏、安全区和附件位置；
/// - 窗口放得下（iPad 模拟器）→ DEBUG 启动参数 `-uitest-layout WxH` 把场景根限制在左上角 W×H；
/// - 放不下（例如 Duo 外屏跑内屏尺寸）→ 跳过并写明原因。
/// 假折痕用 `-uitest-fake-fold v|h`（见 BubuAdaptiveLayout.swift），不依赖 Device Hub 切姿态。
final class DuoLayoutUITests: XCTestCase {
    private struct LayoutCase {
        let width: CGFloat
        let height: CGFloat
        var fold: String? = nil

        var isLandscape: Bool { width > height }
        var sizeArgument: String { "\(Int(width))x\(Int(height))" }
        var name: String { sizeArgument + (fold.map { "-fold-" + $0 } ?? "") }
    }

    private enum Mode { case native, forced }

    private struct Session {
        let app: XCUIApplication
        /// 内容必须落在里面的区域（全局坐标）：原生 = 窗口；强制尺寸 = 左上角 W×H（顶部多留状态栏余量）。
        let boundary: CGRect
        let mode: Mode
        let name: String
    }

    private static let matrix = [
        LayoutCase(width: 466, height: 678),
        LayoutCase(width: 678, height: 466),
        LayoutCase(width: 669, height: 951),
        LayoutCase(width: 951, height: 669),
        LayoutCase(width: 951, height: 669, fold: "v"),
        LayoutCase(width: 669, height: 951, fold: "h"),
    ]

    /// 横屏回退开关可能被单元测试或手动改过；这里只验证布局，不验证开关本身（开关由 DuoLayout2_30Tests 覆盖）。
    private static let baseArguments = ["-uitest-in-memory", "-bubu.layout.allowLandscape", "YES"]
    private static let seededArguments = baseArguments + ["-uitest-seed"]
    /// 内存库没有档案 + 参数域覆盖「已完成引导」= 首次引导。
    private static let onboardingArguments = baseArguments + ["-bubu.onboarded", "NO"]
    /// `-uitest-layout` 的外框放在窗口安全区左上角：顶部状态栏（iPad 24pt）算进余量。
    private static let forcedTopSlack: CGFloat = 30

    override func setUp() async throws {
        continueAfterFailure = false
        await MainActor.run { XCUIDevice.shared.orientation = .portrait }
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIDevice.shared.orientation = .portrait }
    }

    // MARK: - 尺寸矩阵

    @MainActor func testOuterPortrait466x678() throws { try runMatrixCase(Self.matrix[0]) }
    @MainActor func testOuterLandscape678x466() throws { try runMatrixCase(Self.matrix[1]) }
    @MainActor func testInnerPortrait669x951() throws { try runMatrixCase(Self.matrix[2]) }
    @MainActor func testInnerLandscape951x669() throws { try runMatrixCase(Self.matrix[3]) }
    @MainActor func testInnerBookFold951x669() throws { try runMatrixCase(Self.matrix[4]) }
    @MainActor func testInnerTabletopFold669x951() throws { try runMatrixCase(Self.matrix[5]) }

    @MainActor
    private func runMatrixCase(_ layout: LayoutCase) throws {
        let session = try launch(layout, arguments: Self.seededArguments)
        let app = session.app
        XCTAssertTrue(app.rootNavigationButton(named: "首页").waitForExistence(timeout: 20),
                      "\(session.name)：根导航没有出现")
        attachBubuScreenshot("\(session.name)-launch")

        for name in XCUIApplication.bubuRootTabs {
            XCTContext.runActivity(named: "\(session.name) · \(name)") { _ in
                select(name, in: session)
                assertRecordEntry(onTab: name, in: session)
                settle()
                attachBubuScreenshot("\(session.name)-\(name)")
                assertNothingClipped(in: session, context: name)
            }
        }

        // 首页以外的页面也能就地打开「记录此刻」，关掉后根导航完好。
        XCTContext.runActivity(named: "\(session.name) · 记录此刻") { _ in
            select("时光", in: session)
            openAndCloseRecord(in: session)
        }

        app.terminate()
        let onboarding = try launch(layout, arguments: Self.onboardingArguments, mode: session.mode)
        XCTContext.runActivity(named: "\(session.name) · 首次引导") { _ in
            checkOnboarding(in: onboarding)
        }
        onboarding.app.terminate()
    }

    // MARK: - 真机旋转（Duo 外屏竖 ↔ 横）

    @MainActor
    func testRotationKeepsTabsAndTimelineContent() throws {
        let app = XCUIApplication()
        app.launchArguments = Self.seededArguments
        app.launch()
        XCTAssertTrue(app.waitForInterfaceOrientation(landscape: false), "启动时应为竖屏")
        let session = Session(app: app, boundary: app.frame, mode: .native, name: "rotation")
        XCTAssertTrue(app.rootNavigationButton(named: "时光").waitForExistence(timeout: 20))
        select("时光", in: session)
        XCTAssertTrue(waitForTimelineContent(in: app), "竖屏时光没有内容")
        let hadFamilyRecords = app.buttons.matching(identifier: "timeline.family").firstMatch.exists
        attachBubuScreenshot("rotation-portrait-timeline")

        guard app.rotateInterface(landscape: true) else {
            throw XCTSkip("XCUIDevice 方向没有让界面转到横屏（iPhone Duo 外屏模拟器忽略它，界面本身可以转）。"
                          + "人工验证：TEST_RUNNER_BUBU_UITEST_ROTATION_WAIT=90，看到 BUBU-ROTATION-WAIT 时用 Simulator 旋转")
        }
        settle()
        attachBubuScreenshot("rotation-landscape-timeline")
        let landscape = Session(app: app, boundary: app.frame, mode: .native, name: "rotation-landscape")
        assertTimelineKeepsContent(in: app, hadFamilyRecords: hadFamilyRecords, context: "横屏")
        for name in XCUIApplication.bubuRootTabs { select(name, in: landscape) }
        select("时光", in: landscape)
        assertTimelineKeepsContent(in: app, hadFamilyRecords: hadFamilyRecords, context: "横屏切页后")
        assertNothingClipped(in: landscape, context: "时光")

        XCTAssertTrue(app.rotateInterface(landscape: false), "转回竖屏没有生效")
        settle()
        attachBubuScreenshot("rotation-portrait-again-timeline")
        let portrait = Session(app: app, boundary: app.frame, mode: .native, name: "rotation-portrait")
        assertTimelineKeepsContent(in: app, hadFamilyRecords: hadFamilyRecords, context: "转回竖屏")
        for name in XCUIApplication.bubuRootTabs { select(name, in: portrait) }
    }

    // MARK: - 学习互动（只有联调服务才有可播放的课程）

    @MainActor
    func testLearningPlayAnswersStayHittableAcrossSizes() throws {
        var environment: [String: String] = [:]
        for key in ["BUBU_UITEST_PB_URL", "BUBU_UITEST_AI_URL", "BUBU_UITEST_EMAIL", "BUBU_UITEST_PASSWORD"] {
            if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty { environment[key] = value }
        }
        try XCTSkipIf(environment["BUBU_UITEST_AI_URL"] == nil,
                      "离线没有可播放的课程种子；提供 TEST_RUNNER_BUBU_UITEST_* 联调服务后才验证学习互动")
        var ran = 0
        for layout in Self.matrix {
            let session: Session
            do {
                session = try launch(layout, arguments: ["-uitest-seed", "-uitest-server-config", "-uitest-skip-consent",
                                                         "-uitest-tab", "5", "-bubu.layout.allowLandscape", "YES"],
                                     environment: environment)
            } catch is XCTSkip {
                continue
            }
            XCTContext.runActivity(named: "\(session.name) · 学习互动") { _ in checkLearningPlay(in: session) }
            session.app.terminate()
            ran += 1
        }
        if ran == 0 { throw XCTSkip("矩阵里没有一个尺寸放得下当前模拟器窗口") }
    }

    // MARK: - 启动

    @MainActor
    private func launch(_ layout: LayoutCase, arguments: [String], mode required: Mode? = nil,
                        environment: [String: String] = [:]) throws -> Session {
        XCUIDevice.shared.orientation = layout.isLandscape ? .landscapeLeft : .portrait
        let fold = layout.fold.map { ["-uitest-fake-fold", $0] } ?? []
        let app = XCUIApplication()
        app.launchEnvironment = environment
        if required != .forced {
            app.launchArguments = arguments + fold
            app.launch()
            let window = settledWindow(of: app, landscape: layout.isLandscape)
            if abs(window.width - layout.width) <= 2 && abs(window.height - layout.height) <= 2 {
                return Session(app: app, boundary: window, mode: .native, name: layout.name)
            }
            app.terminate()
            guard required == nil,
                  window.width >= layout.width, window.height >= layout.height + Self.forcedTopSlack else {
                let turned = (window.width > window.height) == layout.isLandscape
                throw XCTSkip("\(layout.name)：当前模拟器窗口 \(Int(window.width))×\(Int(window.height)) 放不下这个尺寸，"
                              + (turned ? "需要 Duo 内屏或 iPad 模拟器"
                                        : "且界面没转到所需方向（Duo 外屏模拟器忽略 XCUIDevice 方向，可先用 Simulator 旋转）"))
            }
        }
        app.launchArguments = arguments + fold + ["-uitest-layout", layout.sizeArgument]
        app.launch()
        let window = settledWindow(of: app, landscape: layout.isLandscape)
        let box = CGRect(x: window.minX, y: window.minY, width: layout.width,
                         height: layout.height + Self.forcedTopSlack).intersection(window)
        return Session(app: app, boundary: box, mode: .forced, name: layout.name)
    }

    /// 启动后等界面方向就位；没转过去就再请求一次（Duo 外屏模拟器会忽略，窗口尺寸照实返回）。
    @MainActor
    private func settledWindow(of app: XCUIApplication, landscape: Bool) -> CGRect {
        if !app.waitForInterfaceOrientation(landscape: landscape, timeout: 4) {
            _ = app.rotateInterface(landscape: landscape)
        }
        return app.frame
    }

    // MARK: - 根导航与记录入口

    @MainActor
    private func select(_ name: String, in session: Session) {
        let app = session.app
        let button = app.rootNavigationButton(named: name)
        guard button.waitForExistence(timeout: 8) else {
            attachBubuHierarchy("\(session.name)-missing-\(name)", of: app)
            XCTFail("\(session.name)：根导航缺少「\(name)」")
            return
        }
        XCTAssertTrue(button.isHittable, "\(session.name)：「\(name)」必须可直接点选，frame=\(button.frame)")
        XCTAssertTrue(session.boundary.insetBy(dx: -1, dy: -1).contains(CGPoint(x: button.frame.midX, y: button.frame.midY)),
                      "\(session.name)：「\(name)」在可见区域外，frame=\(button.frame)，区域=\(session.boundary)")
        button.tap()
        if !waitForTab(name, in: app) {
            attachBubuScreenshot("\(session.name)-select-\(name)-failed")
            attachBubuHierarchy("\(session.name)-select-\(name)-failed", of: app)
            XCTFail("\(session.name)：点「\(name)」后没有切到该页")
        }
    }

    /// 切页完成：Tab 按钮被选中，或这一页的标志元素出现（非当前 Tab 的内容不在无障碍树里）。
    @MainActor
    private func waitForTab(_ name: String, in app: XCUIApplication, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.rootNavigationButton(named: name).isSelected { return true }
            if tabMarkers(name, in: app).contains(where: \.exists) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return false
    }

    @MainActor
    private func tabMarkers(_ name: String, in app: XCUIApplication) -> [XCUIElement] {
        switch name {
        case "首页":
            [app.descendants(matching: .any).matching(identifier: "home.identity-card").firstMatch,
             app.buttons.matching(identifier: "home.record").firstMatch,
             app.buttons.matching(identifier: "设置").firstMatch]
        case "时光": [app.navigationBars.matching(identifier: "时光").firstMatch]
        case "学习": [app.navigationBars.matching(identifier: "每日学习").firstMatch,
                     app.descendants(matching: .any).matching(identifier: "learning.home").firstMatch]
        case "成长": [app.navigationBars.matching(identifier: "成长").firstMatch]
        case "幼儿园": [app.navigationBars.matching(identifier: "幼儿园").firstMatch,
                      app.buttons.matching(identifier: "journal.primary").firstMatch]
        default: []
        }
    }

    @MainActor
    private func assertRecordEntry(onTab name: String, in session: Session) {
        let app = session.app
        var found = app.waitForRecordEntry(timeout: 5)
        // 宽屏首页没有底部附件，入口是「今天」卡里的 home.record：先回到页顶再找。
        for _ in 0..<3 where found == nil {
            swipe(up: false, in: session)
            found = app.hittableRecordEntry()
        }
        guard let entry = found else {
            attachBubuHierarchy("\(session.name)-\(name)-no-record", of: app)
            XCTFail("\(session.name)：「\(name)」页找不到可点的记录入口（root.record / root.record.toolbar / home.record）")
            return
        }
        let center = CGPoint(x: entry.frame.midX, y: entry.frame.midY)
        XCTAssertTrue(session.boundary.insetBy(dx: -1, dy: -1).contains(center),
                      "\(session.name)：「\(name)」页的记录入口 \(entry.identifier) 在可见区域外，frame=\(entry.frame)")
    }

    @MainActor
    private func openAndCloseRecord(in session: Session) {
        let app = session.app
        guard let entry = app.waitForRecordEntry(timeout: 5) else {
            XCTFail("\(session.name)：时光页没有可点的记录入口")
            return
        }
        entry.tap()
        let cancel = app.buttons.matching(identifier: "不记了").firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), "\(session.name)：记录此刻面板没有打开")
        attachBubuScreenshot("\(session.name)-record-sheet")
        XCTAssertTrue(cancel.isHittable, "\(session.name)：记录面板的关闭按钮点不到")
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 8), "\(session.name)：空白记录面板应能直接关闭")
        XCTAssertTrue(app.rootNavigationButton(named: "时光").isHittable, "\(session.name)：关掉记录后根导航必须完好")
    }

    // MARK: - 首次引导

    @MainActor
    private func checkOnboarding(in session: Session) {
        let app = session.app
        let next = app.buttons.matching(identifier: "继续").firstMatch
        guard next.waitForExistence(timeout: 20) else {
            attachBubuHierarchy("\(session.name)-onboarding-missing", of: app)
            XCTFail("\(session.name)：内存库 + -bubu.onboarded NO 应进入首次引导")
            return
        }
        let join = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "我是来加入的")).firstMatch
        assertReachable(join, "加入已有家庭", in: session)
        assertReachable(next, "继续（欢迎）", in: session)
        attachBubuScreenshot("\(session.name)-onboarding-welcome")
        next.tap()

        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "\(session.name)：生日页缺少名字输入框")
        assertReachable(name, "名字输入框", in: session)
        let date = app.datePickers.firstMatch
        if date.exists { assertReachable(date, "生日选择", in: session) }
        assertReachable(next, "继续（生日）", in: session)
        attachBubuScreenshot("\(session.name)-onboarding-birthday")
        next.tap()

        let mama = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "妈妈")).firstMatch
        XCTAssertTrue(mama.waitForExistence(timeout: 5), "\(session.name)：关系页缺少选项")
        assertReachable(mama, "关系选项", in: session)
        let finish = app.buttons.matching(identifier: "开始记录布布的成长").firstMatch
        assertReachable(finish, "开始记录", in: session)
        attachBubuScreenshot("\(session.name)-onboarding-member")
    }

    /// 可以滚动到，但必须可点，且左右不能被裁出可见区域（竖向滚动页面里横向溢出就是排版错乱）。
    @MainActor
    private func assertReachable(_ element: XCUIElement, _ label: String, in session: Session) {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("\(session.name)：缺少「\(label)」")
            return
        }
        for _ in 0..<5 where !(element.isHittable && session.boundary.insetBy(dx: -1, dy: -1).contains(element.frame)) {
            swipe(up: true, in: session)
        }
        let frame = element.frame
        XCTAssertTrue(element.isHittable, "\(session.name)：「\(label)」点不到，frame=\(frame)")
        XCTAssertTrue(frame.minX >= session.boundary.minX - 1 && frame.maxX <= session.boundary.maxX + 1,
                      "\(session.name)：「\(label)」左右超出可见区域，frame=\(frame)，区域=\(session.boundary)")
    }

    // MARK: - 学习互动

    @MainActor
    private func checkLearningPlay(in session: Session) {
        let app = session.app
        let courses = app.buttons.matching(identifier: "learning.course")
        guard courses.firstMatch.waitForExistence(timeout: 60) else {
            XCTFail("\(session.name)：联调服务里没有课程")
            return
        }
        var opened = false
        for index in 0..<min(courses.count, 6) where !opened {
            let course = courses.element(boundBy: index)
            for _ in 0..<4 where !course.isHittable { swipe(up: true, in: session) }
            guard course.isHittable else { continue }
            course.tap()
            let play = app.buttons.matching(identifier: "learning.play").firstMatch
            if play.waitForExistence(timeout: 10) {
                for _ in 0..<4 where !play.isHittable { swipe(up: true, in: session) }
                play.tap()
                opened = true
            } else {
                app.tapNavigationBack()
            }
        }
        guard opened else {
            XCTFail("\(session.name)：没有已开放、可「开始一起学」的课程")
            return
        }
        XCTAssertTrue(app.buttons.matching(identifier: "learning.play.listen").firstMatch.waitForExistence(timeout: 20),
                      "\(session.name)：互动页没有打开")
        // 全屏互动由 UIKit 按整个窗口呈现，不受 -uitest-layout 外框约束：按窗口判断。
        let window = app.frame.insetBy(dx: -1, dy: -1)
        let choices = app.buttons.matching(identifier: "learning.play.choice")
        if choices.firstMatch.waitForExistence(timeout: 5) {
            for choice in choices.allElementsBoundByIndex {
                XCTAssertTrue(choice.isHittable, "\(session.name)：答案按钮点不到，frame=\(choice.frame)")
                XCTAssertTrue(window.contains(choice.frame), "\(session.name)：答案按钮超出窗口，frame=\(choice.frame)")
            }
        } else {
            let alternative = ["说出来啦", "一起唱完啦"].map { app.buttons.matching(identifier: $0).firstMatch }.first(where: \.exists)
            XCTAssertTrue(alternative?.isHittable ?? false, "\(session.name)：互动页没有可点的作答按钮")
        }
        attachBubuScreenshot("\(session.name)-learning-play")
        let close = app.buttons.matching(identifier: "learning.play.close").firstMatch
        if close.exists && close.isHittable { close.tap() }
    }

    // MARK: - 时光内容

    @MainActor
    private func timelineHasContent(in app: XCUIApplication) -> Bool {
        app.buttons.matching(identifier: "timeline.family").firstMatch.exists
            || app.buttons.matching(identifier: "timeline.item").firstMatch.exists
            || app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "未连接家里的服务器")).firstMatch.exists
    }

    @MainActor
    private func waitForTimelineContent(in app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if timelineHasContent(in: app) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        } while Date() < deadline
        return false
    }

    @MainActor
    private func assertTimelineKeepsContent(in app: XCUIApplication, hadFamilyRecords: Bool, context: String) {
        XCTAssertTrue(waitForTimelineContent(in: app), "\(context)：时光没有内容")
        if hadFamilyRecords {
            XCTAssertTrue(app.buttons.matching(identifier: "timeline.family").firstMatch.waitForExistence(timeout: 8),
                          "\(context)：家人记录不能在旋转后消失")
        }
    }

    // MARK: - 裁切检查

    /// 文字和控件不能被可见区域裁掉一部分：
    /// - 不在滚动容器里（栏、附件、固定标题）→ 必须完整落在区域内；
    /// - 只在竖向滚动容器里 → 屏幕上下方的行本来就在外面，只要求左右不出界（固定宽度撑破窄屏 = 排版错乱）；
    /// - 在横向滚动容器里（轮播、筛选条）→ 本来就可以滑到屏幕外，不检查。
    /// 完全在区域外的元素（收起的侧栏、懒加载的行）不算裁切。
    @MainActor
    private func assertNothingClipped(in session: Session, context: String) {
        guard let root = try? session.app.snapshot() else {
            XCTFail("\(session.name) \(context)：取不到无障碍快照")
            return
        }
        let checked: Set<XCUIElement.ElementType> = [
            .button, .staticText, .textField, .secureTextField, .searchField, .textView, .switch, .toggle,
            .segmentedControl, .slider, .stepper, .link, .datePicker, .menuButton, .popUpButton,
        ]
        let scrolling: Set<XCUIElement.ElementType> = [.scrollView, .table, .collectionView, .webView]
        let bounds = session.boundary
        let limit = bounds.insetBy(dx: -1, dy: -1)
        var clipped: [String] = []

        /// 子树里所有元素的外包矩形：只往左右溢出 = 横向滚动容器。
        func contentUnion(_ node: XCUIElementSnapshot) -> CGRect {
            node.children.reduce(CGRect.null) { union, child in
                let frame = child.frame.isEmpty ? CGRect.null : child.frame
                return union.union(frame).union(contentUnion(child))
            }
        }
        enum Scope { case fixed, vertical, horizontal }
        func visit(_ node: XCUIElementSnapshot, scope: Scope) {
            let frame = node.frame
            let isScroll = scrolling.contains(node.elementType)
            if checked.contains(node.elementType) || isScroll, !frame.isEmpty, frame.intersects(bounds) {
                let fits: Bool
                switch scope {
                case .fixed: fits = limit.contains(frame)
                case .vertical: fits = frame.minX >= limit.minX && frame.maxX <= limit.maxX
                case .horizontal: fits = true
                }
                if !fits {
                    clipped.append("\(node.elementType.rawValue) id=\(node.identifier) label=\(node.label) frame=\(frame)")
                }
            }
            var childScope = scope
            if isScroll, scope != .horizontal {
                let content = contentUnion(node)
                let spillsSideways = !content.isNull
                    && (content.minX < frame.minX - 1 || content.maxX > frame.maxX + 1)
                    && content.minY >= frame.minY - 1 && content.maxY <= frame.maxY + 1
                childScope = spillsSideways ? .horizontal : .vertical
            }
            for child in node.children { visit(child, scope: childScope) }
        }
        visit(root, scope: .fixed)
        if !clipped.isEmpty {
            attachBubuHierarchy("\(session.name)-\(context)-clipped", of: session.app)
            XCTFail("\(session.name) \(context)：\(clipped.count) 个元素超出可见区域 \(bounds)：\n"
                    + clipped.prefix(12).joined(separator: "\n"))
        }
    }

    // MARK: - 手势

    /// 在可见区域内滑动（强制尺寸时窗口正中可能在外框之外）；横向取左侧 35%，避开右侧竖排栏和竖直折痕。
    @MainActor
    private func swipe(up: Bool, in session: Session) {
        let app = session.app
        let bounds = session.boundary
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let x = bounds.minX + bounds.width * 0.35 - app.frame.minX
        let upper = bounds.minY + bounds.height * 0.3 - app.frame.minY
        let lower = bounds.minY + bounds.height * 0.7 - app.frame.minY
        let start = origin.withOffset(CGVector(dx: x, dy: up ? lower : upper))
        let end = origin.withOffset(CGVector(dx: x, dy: up ? upper : lower))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func settle(_ seconds: TimeInterval = 0.6) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
