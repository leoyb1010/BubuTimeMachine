import Testing
import SwiftUI
@testable import BubuTimeMachine

// MARK: - 2.30 iPhone Duo 边界情况：未测量 / 零宽、折痕贴边、单张照片成行、没有折痕
// 补 DuoLayout2_30Tests / TimelineDuo2_30Tests 没覆盖的输入：布局根第一次测量之前尺寸是 0，
// 折痕可能贴在安全区边上，时光可能只有一张照片。

@MainActor
struct DuoLayoutEdgeCases2_30Tests {

    @Test func unmeasuredRootHasNoPanesAndDefaultGrid() {
        let unmeasured = BubuLayout(size: .zero)
        #expect(unmeasured.panes.isEmpty)
        #expect(unmeasured.widthClass == .compact)
        #expect(unmeasured.heightClass == .medium)
        #expect(unmeasured.bubuFoldGrid(compactColumns: 2, availableWidth: 0).count == 2)
        // 折痕先于尺寸到达也不能切出负宽度的块。
        let foldFirst = BubuLayout(size: .zero, fold: CGRect(x: 0, y: 0, width: 24, height: 669))
        #expect(foldFirst.panes.isEmpty)
        // 安全区比尺寸还大（转场中的瞬间值）：安全区收成 0，不出现负宽度。
        let squeezed = BubuLayout(size: CGSize(width: 100, height: 100),
                                  safeInsets: EdgeInsets(top: 0, leading: 80, bottom: 0, trailing: 80))
        #expect(squeezed.safeRect.width == 0)
        #expect(squeezed.panes.isEmpty)
    }

    @Test func gridNeverDropsBelowTwoColumnsOnTinyOrNegativeWidths() {
        for width: CGFloat in [-50, 0, 1, 150] {
            for widthClass in [BubuLayout.SizeClass.medium, .expanded] {
                let spec = BubuLayout.foldGridSpec(width: width, widthClass: widthClass, compactColumns: 3,
                                                   minItemWidth: 160, spacing: 12, foldGutter: nil)
                #expect(spec.count == 2)
                #expect(spec.gridItems.count == 2)
            }
            let folded = BubuLayout.foldGridSpec(width: width, widthClass: .expanded, compactColumns: 3,
                                                 minItemWidth: 160, spacing: 12, foldGutter: 48)
            #expect(folded.count == 2)
            #expect(folded.centerSpacing == 48)
        }
        // compactColumns 0 不会给出空网格。
        #expect(BubuLayout.foldGridSpec(width: 300, widthClass: .compact, compactColumns: 0,
                                        minItemWidth: 160, spacing: 12, foldGutter: nil).count == 1)
        // 折痕间距比普通间距还窄时，中缝至少是普通间距。
        #expect(BubuLayout.foldGridSpec(width: 951, widthClass: .expanded, compactColumns: 2,
                                        minItemWidth: 160, spacing: 12, foldGutter: 4).centerSpacing == 12)
    }

    @Test func compactWidthWithAVerticalFoldStillCentersTheGutter() {
        // 外屏宽度（compact）也可能被假折痕切开：取偶数列，正中留出折痕。
        let spec = BubuLayout.foldGridSpec(width: 466, widthClass: .compact, compactColumns: 3,
                                           minItemWidth: 160, spacing: 12, foldGutter: 48)
        #expect(spec == BubuLayout.FoldGridSpec(count: 2, spacing: 12, centerSpacing: 48))
        #expect(spec.gridItems[0].spacing == 48)
    }

    @Test func zeroWidthColumnIsNeverSplit() {
        let size = CGSize(width: 951, height: 669)
        let layout = BubuLayout(size: size, fold: BubuLayout.fakeFold(axis: .vertical, in: size))
        #expect(layout.columnSplit(minX: 0, width: 0) == nil)
        #expect(layout.columnSplit(minX: 475, width: -10) == nil)
    }

    @Test func verticalFoldAtEitherEdgeLeavesOnePane() {
        let size = CGSize(width: 951, height: 669)
        let leading = BubuLayout(size: size, fold: CGRect(x: 0, y: 0, width: 24, height: 669))
        #expect(leading.foldAxis == .vertical)
        #expect(leading.panes == [CGRect(x: 24, y: 0, width: 927, height: 669)])
        #expect(leading.columnSplit(minX: 0, width: 951) == nil)

        let trailing = BubuLayout(size: size, fold: CGRect(x: 927, y: 0, width: 24, height: 669))
        #expect(trailing.panes == [CGRect(x: 0, y: 0, width: 927, height: 669)])
        #expect(trailing.columnSplit(minX: 0, width: 951) == nil)


        // 时光的阅读列（16pt 边距、两侧至少 120pt）：折痕太靠边时不分栏，照片照常整行排。
        let nearEdge = BubuLayout(size: size, fold: CGRect(x: 100, y: 0, width: 24, height: 669))
        #expect(nearEdge.columnSplit(minX: 16, width: 919, margin: 4, minPane: 120) == nil)
        let nearTrailingEdge = BubuLayout(size: size, fold: CGRect(x: 827, y: 0, width: 24, height: 669))
        #expect(nearTrailingEdge.columnSplit(minX: 16, width: 919, margin: 4, minPane: 120) == nil)
    }

    @Test func horizontalFoldAtTheTopEdgeLeavesOnePane() {
        let layout = BubuLayout(size: CGSize(width: 669, height: 951), fold: CGRect(x: 0, y: 0, width: 669, height: 24))
        #expect(layout.foldAxis == .horizontal)
        #expect(layout.panes == [CGRect(x: 0, y: 24, width: 669, height: 927)])
    }

    /// 折痕只有一部分落在安全区里（弹窗边缘压在折痕上、折痕伸出屏幕）：只剩安全区内那一块，
    /// 不能多出一块「负宽度」的假区域（CGRect.width 取绝对值，负宽度会被当成正的）。
    @Test func foldPartlyOutsideTheSafeAreaKeepsOnlyTheInnerPart() {
        let straddle = BubuLayout(size: CGSize(width: 400, height: 800),
                                  safeInsets: EdgeInsets(top: 0, leading: 100, bottom: 0, trailing: 0),
                                  fold: CGRect(x: 90, y: 0, width: 24, height: 800))
        #expect(straddle.panes == [CGRect(x: 114, y: 0, width: 286, height: 800)])
        let overhang = BubuLayout(size: CGSize(width: 951, height: 669), fold: CGRect(x: 940, y: 0, width: 24, height: 669))
        #expect(overhang.panes == [CGRect(x: 0, y: 0, width: 940, height: 669)])
        let sheetTopOnFold = BubuLayout(size: CGSize(width: 669, height: 400),
                                        fold: CGRect(x: 0, y: -10, width: 669, height: 24))
        #expect(sheetTopOnFold.panes == [CGRect(x: 0, y: 14, width: 669, height: 386)])
    }
}

@MainActor
struct TimelineDuoEdgeCases2_30Tests {

    private func item(_ index: Int, day: String = "2026-10-01", aspect: Double = 1) -> OnlineTimelineItem {
        let id = "z" + String(format: "%023d", index)
        return OnlineTimelineItem(id: id, contentHash: id, kind: "photo", capturedAt: day + "T10:00:00+08:00", localDay: day,
                                  description: "", ocr: "", tags: [], segments: [], labelProvenanceText: "",
                                  previewUrl: "/learning/api/online-timeline/\(id)/preview", largeUrl: "", mediaUrl: "",
                                  aspect: aspect, people: nil, place: nil, confirmedByFamily: nil,
                                  descriptionAdjusted: nil, transcriptHidden: nil)
    }

    private func mixed(_ count: Int) -> [OnlineTimelineItem] {
        (0..<count).map { index in
            item(index, day: String(format: "2026-10-%02d", max(1, 28 - index / 3)), aspect: [0.75, 1.33, 1, 1.78, 0.56][index % 5])
        }
    }

    private func build(_ items: [OnlineTimelineItem], hasMore: Bool = false, width: CGFloat = 402,
                       target: CGFloat = 118, split: BubuLayout.ColumnSplit? = nil) -> OnlineTimelineLayout {
        OnlineTimelineLayoutBuilder.build(items: items, family: [], events: [], query: OnlineTimelineQuery(),
                                          source: .brain, hasMore: hasMore, width: width, target: target, split: split)
    }

    private func cellRows(_ layout: OnlineTimelineLayout) -> [OnlineTimelineRow] {
        layout.rows.compactMap { row in
            if case .cells(let cells) = row.content { return cells }
            return nil
        }
    }

    private func used(_ cells: ArraySlice<(element: OnlineTimelineElement, width: CGFloat)>) -> CGFloat {
        cells.reduce(0) { $0 + $1.width } + OnlineTimelineLayoutBuilder.spacing * CGFloat(max(cells.count - 1, 0))
    }

    /// 内屏横拿半折：折痕在 463.5…487.5，阅读列 16…935。
    private var innerSplit: BubuLayout.ColumnSplit? {
        BubuLayout(size: CGSize(width: 951, height: 669), fold: CGRect(x: 463.5, y: 0, width: 24, height: 669))
            .columnSplit(minX: 16, width: 919, margin: 4, minPane: 120)
    }

    // MARK: 零宽 / 未测量

    @Test func zeroOrNegativeWidthStillLaysOutEveryPhoto() {
        let items = mixed(30)
        for width: CGFloat in [0, -20] {
            let rows = cellRows(build(items, width: width))
            #expect(!rows.isEmpty)
            for row in rows {
                #expect(row.height > 0)
                #expect(row.cells.allSatisfy { $0.width > 0 })
                #expect(used(row.cells[...]) <= 200.5)   // 未测量时按 200pt 的最小行宽排
            }
            #expect(rows.flatMap(\.cells).map(\.element.id) == items.map { "o-" + $0.id })
        }
        let skeleton = OnlineTimelineLayoutBuilder.placeholderRows(width: 0, target: 118, rows: 3)
        #expect(skeleton.count == 3)
        #expect(skeleton.allSatisfy { $0.count == 2 && abs($0.height - 98) < 0.01 })
    }

    @Test func degenerateSplitTerminatesAndKeepsOrder() {
        let elements = mixed(12).map { OnlineTimelineElement($0) }
        let rows = OnlineTimelineLayoutBuilder.justifySplit(
            elements, width: 0, split: BubuLayout.ColumnSplit(leading: 0, gutter: 0, trailing: 0), target: 118)
        #expect(rows.flatMap(\.cells).map(\.element.id) == elements.map(\.id))
        #expect(rows.allSatisfy { row in row.cells.allSatisfy { $0.width > 0 } })
    }

    @Test func emptyStreamHasNoRowsOrAnchors() {
        let layout = build([])
        #expect(layout.isEmpty)
        #expect(layout.rows.isEmpty)
        #expect(layout.monthRowID("2026-10") == nil)
        #expect(layout.anchor(forDay: "2026-10-01") == nil)
        #expect(layout.anchorID(forRow: "m-2026-10") == nil)
    }

    // MARK: 单张照片成行

    @Test func aLonePhotoKeepsItsShapeWithoutAFold() throws {
        for aspect in [0.3, 0.56, 1, 1.78, 2.2, 10] {
            let rows = cellRows(build([item(0, aspect: aspect)]))
            let row = try #require(rows.first)
            #expect(rows.count == 1)
            #expect(row.cells.count == 1)
            #expect(row.foldIndex == nil)
            // 没有完整行可参照：不超过目标高度的 0.85，按自己的比例，不撑满 402pt。
            #expect(abs(row.height - 118 * 0.85) < 0.01)
            #expect(row.cells[0].width < 402)
            #expect(abs(row.cells[0].width - CGFloat(min(max(aspect, 0.56), 2.2)) * row.height) < 0.01)
        }
    }

    @Test func aLonePhotoWaitsWhileMorePagesAreComing() {
        let layout = build([item(0)], hasMore: true)
        #expect(cellRows(layout).isEmpty)
        #expect(layout.rows.count == 1)      // 只有月份标题；下一页到了再排，不让已显示的行重排
        #expect(!layout.isEmpty)
    }

    @Test func aLonePhotoUnderAFoldStaysInTheLeadingHalf() throws {
        let split = try #require(innerSplit)
        for aspect in [0.56, 1, 2.2] {
            let rows = cellRows(build([item(0, aspect: aspect)], width: 919, target: 176, split: split))
            let row = try #require(rows.first)
            #expect(rows.count == 1)
            #expect(row.cells.count == 1)
            #expect(row.foldIndex == nil)
            #expect(row.cells[0].width <= split.leading)
            #expect(abs(row.height - 176 * 0.85) < 0.01)
        }
    }

    @Test func aLoneTrailingPhotoKeepsTheLeadingHeight() throws {
        let split = try #require(innerSplit)
        // 443.5pt 的半边放 3 张方图正好满一行（145.2pt），第 4 张独自落在折痕后面。
        let rows = cellRows(build((0..<4).map { item($0) }, width: 919, target: 176, split: split))
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.foldIndex == 3)
        #expect(row.foldGap == split.gutter)
        let leadingHeight = (split.leading - 2 * OnlineTimelineLayoutBuilder.spacing) / 3
        #expect(abs(row.height - leadingHeight) < 0.01)
        #expect(abs(row.cells[3].width - leadingHeight) < 0.01)
        #expect(used(row.cells[3...]) <= split.trailing)
    }

    // MARK: 没有折痕

    @Test func withoutAFoldRowsSpanTheWholeColumn() {
        let rows = cellRows(build(mixed(40), width: 919, target: 176))
        #expect(rows.count > 2)
        for (index, row) in rows.enumerated() {
            #expect(row.foldIndex == nil)
            #expect(row.foldGap == 0)
            if index < rows.count - 1 { #expect(abs(used(row.cells[...]) - 919) < 0.5) }
            #expect(used(row.cells[...]) <= 919.5)
        }
    }

    // MARK: 拖动条的边界

    private func months(_ count: Int) -> [OnlineTimelineMonthCount] {
        (0..<count).map { index in
            let date = BubuLearningDates.calendar.date(byAdding: .month, value: -index, to: BubuLearningDates.day("2026-10-01")!)!
            return OnlineTimelineMonthCount(month: BubuLearningDates.monthKey(date), count: 10)
        }
    }

    @Test func scrubberWithoutMonthsOrHeightIsInert() {
        let empty = OnlineTimelineScrubberScale(months: [], height: 0)
        #expect(empty.month(at: 0) == nil)
        #expect(empty.center(of: "2026-10") == nil)
        #expect(empty.trackSegments == [0...1])
        #expect(empty.yearMarks.isEmpty)
        // 未测量（高 0）时不除零，所有月份挤在 1pt 里。
        let list = months(12)
        let unmeasured = OnlineTimelineScrubberScale(months: list, height: 0)
        #expect(unmeasured.month(at: 0.5) != nil)
        for month in list {
            let center = unmeasured.center(of: month.month) ?? -1
            #expect(center >= 0 && center <= 1)
        }
    }

    @Test func foldAtTheTopOfTheScrubberPushesThumbsBelowIt() throws {
        let list = months(12)
        let scale = OnlineTimelineScrubberScale(months: list, height: 400, skipping: -10...20)
        #expect(scale.band == 0...20)
        #expect(scale.trackSegments == [20...400])
        for month in list {
            let center = try #require(scale.center(of: month.month, clearance: 22))
            #expect(center >= 42 - 0.01 && center <= 400)
        }
        #expect(scale.month(at: 5) == list[0].month)
        #expect(scale.month(at: 15) == list[0].month)
    }

    @Test func foldAtTheBottomOfTheScrubberKeepsThumbsAboveIt() throws {
        let list = months(12)
        let scale = OnlineTimelineScrubberScale(months: list, height: 400, skipping: 380...450)
        #expect(scale.band == 380...400)
        #expect(scale.trackSegments == [0...380])
        for month in list {
            let center = try #require(scale.center(of: month.month, clearance: 22))
            #expect(center >= 0 && center <= 358 + 0.01)
        }
        #expect(scale.month(at: 399) == list.last?.month)
    }
}
