import XCTest

/// UI 测试共用的根导航 / 记录入口查找。只认 App 实际呈现出来的元素，不按设备类型或屏幕宽度猜布局：
/// iPhone 底栏、Duo 外屏 / 内屏横拿的竖排栏、iPad 顶部 Tab 与侧栏都走同一套查找。
extension XCUIApplication {
    /// 根 Tab 的视觉顺序（Mac Catalyst 另有「档案馆」，iOS 不出现）。
    static let bubuRootTabs = ["首页", "时光", "学习", "成长", "幼儿园"]

    /// 「记录此刻」的三种入口：窄屏底部附件 / 宽屏侧栏（root.record）、宽屏 Tab 工具栏（root.record.toolbar）、
    /// 首页「今天」卡（home.record）。
    static let bubuRecordEntryIDs = ["root.record", "root.record.toolbar", "home.record"]

    /// 根导航里某一页的入口：优先系统 Tab 栏按钮（水平或竖排），否则任一可点的同名按钮（侧栏）。
    func rootNavigationButton(named name: String) -> XCUIElement {
        let native = tabBars.buttons.matching(identifier: name).firstMatch
        if native.exists && native.isHittable { return native }
        let matches = buttons.matching(identifier: name)
        if let hittable = matches.allElementsBoundByIndex.first(where: { $0.isHittable }) { return hittable }
        return native.exists ? native : matches.firstMatch
    }

    /// 当前可直接点到的「记录此刻」入口；都点不到时返回 nil。
    func hittableRecordEntry() -> XCUIElement? {
        for identifier in Self.bubuRecordEntryIDs {
            let candidates = buttons.matching(identifier: identifier).allElementsBoundByIndex
            if let entry = candidates.first(where: { $0.exists && $0.isHittable }) { return entry }
        }
        return nil
    }

    /// 等到某个记录入口可点（冷启动 + 种子数据可能要几十秒）。
    func waitForRecordEntry(timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let entry = hittableRecordEntry() { return entry }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        } while Date() < deadline
        return hittableRecordEntry()
    }

    /// 返回上一页：水平导航栏时返回键在 navigationBars 里；竖排栏（Duo 外屏 / 内屏横拿）时它在侧边 Toolbar 里，
    /// 标识仍是 BackButton。
    func tapNavigationBack() {
        let back = buttons.matching(identifier: "BackButton").allElementsBoundByIndex.first(where: { $0.isHittable })
        (back ?? navigationBars.buttons.firstMatch).tap()
    }

    /// 导航栏上的文字按钮（取消 / 保存…）：优先在标题为 `title` 的导航栏里找；竖排栏时按钮挪进侧边 Toolbar，
    /// 退回全局里最后一个可点的同名按钮（最上层的弹窗排在无障碍树的后面）。
    func barButton(_ label: String, inNavigationBar title: String) -> XCUIElement {
        let scoped = navigationBars.matching(identifier: title).firstMatch.buttons.matching(identifier: label).firstMatch
        if scoped.exists { return scoped }
        let matches = buttons.matching(identifier: label)
        return matches.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? matches.firstMatch
    }

    /// 旋转等待上限：默认 8 秒。iPhone Duo 外屏模拟器忽略 `XCUIDevice.orientation`（读回值变了，界面不转），
    /// 需要人工用 Simulator 旋转时，用 TEST_RUNNER_BUBU_UITEST_ROTATION_WAIT 放宽，并按日志里的
    /// `BUBU-ROTATION-WAIT` 提示去转。
    static var bubuRotationWait: TimeInterval {
        Double(ProcessInfo.processInfo.environment["BUBU_UITEST_ROTATION_WAIT"] ?? "") ?? 8
    }

    /// 请求转到横屏 / 竖屏并等界面真的转过去；转不过去返回 false（调用方决定跳过还是失败）。
    func rotateInterface(landscape: Bool) -> Bool {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        if waitForInterfaceOrientation(landscape: landscape, timeout: 2) { return true }
        print("BUBU-ROTATION-WAIT " + (landscape ? "landscape" : "portrait"))
        return waitForInterfaceOrientation(landscape: landscape, timeout: Self.bubuRotationWait)
    }

    /// 等窗口转到指定方向（XCUI 的坐标跟随界面方向）；转不过去返回 false。
    func waitForInterfaceOrientation(landscape: Bool, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let size = frame.size
            if size.width > 0, size.height > 0, (size.width > size.height) == landscape { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return false
    }
}

extension XCTestCase {
    @MainActor
    func attachBubuScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func attachBubuHierarchy(_ name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
