import Testing
import SwiftUI
@testable import BubuTimeMachine

// MARK: - iPhone Duo WS0：BubuLayout 分档 / 折痕分半 / 偶数网格 / 调试参数

@MainActor
struct DuoLayout2_30Tests {

    @Test func widthClassUsesPointThresholds() {
        #expect(BubuLayout.widthClass(for: 466) == .compact)      // Duo 外屏竖拿
        #expect(BubuLayout.widthClass(for: 599.9) == .compact)
        #expect(BubuLayout.widthClass(for: 600) == .medium)
        #expect(BubuLayout.widthClass(for: 669) == .medium)       // Duo 内屏竖拿
        #expect(BubuLayout.widthClass(for: 899) == .medium)
        #expect(BubuLayout.widthClass(for: 951) == .expanded)     // Duo 内屏横拿
        #expect(BubuLayout.SizeClass.compact < .expanded)
    }

    @Test func heightClassAndShort() {
        #expect(BubuLayout(size: CGSize(width: 678, height: 466)).isShort)    // 外屏横拿
        #expect(BubuLayout(size: CGSize(width: 678, height: 466)).heightClass == .compact)
        #expect(!BubuLayout(size: CGSize(width: 466, height: 678)).isShort)
        #expect(BubuLayout(size: CGSize(width: 669, height: 951)).heightClass == .expanded)
        #expect(BubuLayout(size: CGSize(width: 402, height: 874)).heightClass == .medium)
        // 未测量（尺寸为 0）不能被当成矮屏，否则没挂布局根的页面会误走矮屏布局。
        #expect(!BubuLayout.unknown.isShort)
        #expect(BubuLayout.unknown.widthClass == .compact)
        #expect(BubuLayout(size: CGSize(width: 678, height: 466)).bubuHeight(260, short: 160) == 160)
        #expect(BubuLayout(size: CGSize(width: 466, height: 678)).bubuHeight(260, short: 160) == 260)
    }

    @Test func noFoldGivesSingleSafePane() {
        let layout = BubuLayout(size: CGSize(width: 466, height: 678),
                                safeInsets: EdgeInsets(top: 50, leading: 0, bottom: 30, trailing: 60))
        #expect(layout.fold == nil)
        #expect(layout.foldAxis == nil)
        #expect(layout.panes == [CGRect(x: 0, y: 50, width: 406, height: 598)])
    }

    @Test func verticalFoldSplitsLeftAndRight() {
        let size = CGSize(width: 951, height: 669)
        let fold = BubuLayout.fakeFold(axis: .vertical, in: size)
        #expect(fold == CGRect(x: 463.5, y: 0, width: 24, height: 669))
        let layout = BubuLayout(size: size, safeInsets: EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0), fold: fold)
        #expect(layout.foldAxis == .vertical)
        #expect(layout.panes == [CGRect(x: 0, y: 20, width: 463.5, height: 629),
                                 CGRect(x: 487.5, y: 20, width: 463.5, height: 629)])
    }

    @Test func horizontalFoldSplitsTopAndBottom() {
        let size = CGSize(width: 669, height: 951)
        let fold = BubuLayout.fakeFold(axis: .horizontal, in: size)
        #expect(fold == CGRect(x: 0, y: 463.5, width: 669, height: 24))
        let layout = BubuLayout(size: size, fold: fold)
        #expect(layout.foldAxis == .horizontal)
        #expect(layout.panes == [CGRect(x: 0, y: 0, width: 669, height: 463.5),
                                 CGRect(x: 0, y: 487.5, width: 669, height: 463.5)])
        // 水平折痕不切阅读列（滚动内容允许滚过折痕）。
        #expect(layout.columnSplit(minX: 0, width: 669) == nil)
    }

    @Test func foldOutsideSafeAreaKeepsOnePane() {
        let layout = BubuLayout(size: CGSize(width: 400, height: 800),
                                safeInsets: EdgeInsets(top: 0, leading: 100, bottom: 0, trailing: 0),
                                fold: CGRect(x: 40, y: 0, width: 24, height: 800))
        #expect(layout.panes == [CGRect(x: 100, y: 0, width: 300, height: 800)])
    }

    @Test func columnSplitKeepsContentOffTheFold() {
        let size = CGSize(width: 951, height: 669)
        let layout = BubuLayout(size: size, fold: BubuLayout.fakeFold(axis: .vertical, in: size))
        let split = layout.columnSplit(minX: 16, width: 919)
        #expect(split == BubuLayout.ColumnSplit(leading: 435.5, gutter: 48, trailing: 435.5))
        if let split { #expect(split.leading + split.gutter + split.trailing == 919) }
        // 列整体在折痕一侧（如弹窗）时不分栏。
        #expect(layout.columnSplit(minX: 500, width: 400) == nil)
        // 某一侧太窄也不分栏。
        #expect(layout.columnSplit(minX: 400, width: 500) == nil)
        #expect(BubuLayout(size: size).columnSplit(minX: 0, width: 951) == nil)
    }

    @Test func foldGridColumnMath() {
        // 窄屏无折痕：沿用原有列数。
        let narrow = BubuLayout.foldGridSpec(width: 402, widthClass: .compact, compactColumns: 2,
                                             minItemWidth: 160, spacing: 12, foldGutter: nil)
        #expect(narrow == BubuLayout.FoldGridSpec(count: 2, spacing: 12, centerSpacing: 12))
        // 宽屏无折痕：按最小格宽取偶数列。951 → (951-12+24)/172 = 5.6 → 5 → 偶数 4。
        let wide = BubuLayout.foldGridSpec(width: 951, widthClass: .expanded, compactColumns: 2,
                                           minItemWidth: 160, spacing: 12, foldGutter: nil)
        #expect(wide.count == 4)
        #expect(wide.centerSpacing == 12)
        // 竖直折痕：正中间距 = 折痕宽 + 两侧边距，列数仍为偶数。
        let folded = BubuLayout.foldGridSpec(width: 951, widthClass: .expanded, compactColumns: 2,
                                             minItemWidth: 120, spacing: 12, foldGutter: 48)
        #expect(folded.count == 6)
        #expect(folded.centerSpacing == 48)
        let items = folded.gridItems
        #expect(items.count == 6)
        #expect(items[2].spacing == 48)
        #expect(items[1].spacing == 12)
        // 极窄宽屏也至少两列；上限不超过 maxColumns 且为偶数。
        #expect(BubuLayout.foldGridSpec(width: 200, widthClass: .medium, compactColumns: 1,
                                        minItemWidth: 160, spacing: 12, foldGutter: nil).count == 2)
        #expect(BubuLayout.foldGridSpec(width: 4000, widthClass: .expanded, compactColumns: 2,
                                        minItemWidth: 100, spacing: 8, foldGutter: nil, maxColumns: 7).count == 6)
        // 实例方法：外屏竖拿 2 列；内屏假折痕时中缝对齐折痕。
        let inner = BubuLayout(size: CGSize(width: 951, height: 669),
                               fold: BubuLayout.fakeFold(axis: .vertical, in: CGSize(width: 951, height: 669)))
        #expect(inner.bubuFoldGrid(minItemWidth: 120).count == 6)
        #expect(BubuLayout(size: CGSize(width: 466, height: 678)).bubuFoldGrid().count == 2)
    }

    @Test func debugArgumentParsing() {
        #expect(BubuLayoutDebug.parseForcedSize(["app", "-uitest-layout", "466x678"]) == CGSize(width: 466, height: 678))
        #expect(BubuLayoutDebug.parseForcedSize(["-uitest-layout", "951×669"]) == CGSize(width: 951, height: 669))
        #expect(BubuLayoutDebug.parseForcedSize(["-uitest-layout", "678X466"]) == CGSize(width: 678, height: 466))
        #expect(BubuLayoutDebug.parseForcedSize(["-uitest-layout"]) == nil)
        #expect(BubuLayoutDebug.parseForcedSize(["-uitest-layout", "abc"]) == nil)
        #expect(BubuLayoutDebug.parseForcedSize(["-uitest-layout", "0x100"]) == nil)
        #expect(BubuLayoutDebug.parseForcedSize([]) == nil)

        #expect(BubuLayoutDebug.parseFakeFold(["-uitest-fake-fold", "v"]) == .vertical)
        #expect(BubuLayoutDebug.parseFakeFold(["-uitest-fake-fold", "H"]) == .horizontal)
        #expect(BubuLayoutDebug.parseFakeFold(["-uitest-fake-fold", "x"]) == nil)
        #expect(BubuLayoutDebug.parseFakeFold(["-uitest-fake-fold"]) == nil)
        #expect(BubuLayoutDebug.parseFakeFold(["-uitest-tab", "1"]) == nil)
    }

    @Test func arrangementFallbackDirection() {
        #expect(BubuDuo.arrangementIsHorizontal(size: CGSize(width: 951, height: 669), axes: [.horizontal, .vertical]))
        #expect(!BubuDuo.arrangementIsHorizontal(size: CGSize(width: 669, height: 951), axes: [.horizontal, .vertical]))
        #expect(BubuDuo.arrangementIsHorizontal(size: CGSize(width: 300, height: 900), axes: .horizontal))
        #expect(!BubuDuo.arrangementIsHorizontal(size: CGSize(width: 900, height: 300), axes: .vertical))
    }

    @Test func landscapeSwitchDefaultsOn() {
        let key = BubuAppDelegate.allowLandscapeKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        #expect(BubuAppDelegate.allowsLandscape)
        UserDefaults.standard.set(false, forKey: key)
        #expect(!BubuAppDelegate.allowsLandscape)
    }
}
