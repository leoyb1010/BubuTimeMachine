import Testing
import Foundation
import CoreGraphics
@testable import BubuTimeMachine

// MARK: - 2.30 时光 × iPhone Duo：开合不跳位置、竖直折痕分半排行、事件卡前不留空、拖动条跳过水平折痕
@MainActor
struct TimelineDuo2_30Tests {

    private func item(_ index: Int, day: String, aspect: Double = 1, prefix: String = "a") -> OnlineTimelineItem {
        let id = prefix + String(format: "%023d", index)
        return OnlineTimelineItem(id: id, contentHash: id, kind: "photo", capturedAt: day + "T10:00:00+08:00", localDay: day,
                                  description: "", ocr: "", tags: [], segments: [], labelProvenanceText: "",
                                  previewUrl: "/learning/api/online-timeline/\(id)/preview", largeUrl: "", mediaUrl: "",
                                  aspect: aspect, people: nil, place: nil, confirmedByFamily: nil,
                                  descriptionAdjusted: nil, transcriptHidden: nil)
    }

    /// Three a day from 2026-10-28 down, mixed shapes.
    private func days(_ count: Int, month: String = "2026-10", prefix: String = "a") -> [OnlineTimelineItem] {
        (0..<count).map { index in
            item(index, day: String(format: "\(month)-%02d", max(1, 28 - index / 3)),
                 aspect: [0.75, 1.33, 1, 1.78, 0.56][index % 5], prefix: prefix)
        }
    }

    private func build(_ items: [OnlineTimelineItem], events: [OnlineTimelineEvent] = [], hasMore: Bool,
                       width: CGFloat = 402, target: CGFloat = 118, split: BubuLayout.ColumnSplit? = nil) -> OnlineTimelineLayout {
        OnlineTimelineLayoutBuilder.build(items: items, family: [], events: events, query: OnlineTimelineQuery(),
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

    /// Inner display in landscape, half open like a book: 24pt crease in the middle, 16pt margins.
    private let innerFold = BubuLayout(size: CGSize(width: 951, height: 669), fold: CGRect(x: 463.5, y: 0, width: 24, height: 669))
    private var innerSplit: BubuLayout.ColumnSplit? { innerFold.columnSplit(minX: 16, width: 919, margin: 4, minPane: 120) }

    // MARK: Anchor across fold / unfold / rotation

    @Test func topPhotoSurvivesAWidthChange() throws {
        let items = days(90)
        let narrow = build(items, hasMore: false, width: 434)   // outer display
        let rows = cellRows(narrow)
        let top = rows[7]
        let anchor = try #require(narrow.anchorID(forRow: top.id))
        #expect(anchor == top.cells.first?.element.id)
        for wide in [build(items, hasMore: false, width: 919, target: 176),
                     build(items, hasMore: false, width: 919, target: 176, split: innerSplit),
                     build(items, hasMore: false, width: 646, target: 96)] {
            let rowID = try #require(wide.rowID(holding: anchor))
            let index = try #require(wide.rowIndex[rowID])
            guard case .cells(let cells) = wide.rows[index].content else { Issue.record("photo row"); continue }
            #expect(cells.cells.contains { $0.element.id == anchor })
        }
    }

    @Test func monthTitlesAndEventCardsAnchorToThemselves() {
        let items = days(12)
        let event = OnlineTimelineEvent(id: "park", title: "公园", story: nil, day: "2026-10-27", place: nil,
                                        count: 3, coverUrl: nil, itemIds: items[3..<6].map(\.id))
        let layout = build(items, events: [event], hasMore: false)
        #expect(layout.anchorID(forRow: "m-2026-10") == "m-2026-10")
        #expect(layout.anchorID(forRow: "e-park") == "e-park")
        #expect(layout.rowID(holding: "m-2026-10") == "m-2026-10")
        #expect(layout.rowID(holding: "e-park") == "e-park")
        #expect(layout.anchorID(forRow: "missing") == nil)
        #expect(layout.rowID(holding: "o-missing") == nil)
    }

    // MARK: Vertical fold: rows break at the crease

    @Test func onlyAVerticalFoldSplitsTheRows() throws {
        let split = try #require(innerSplit)
        #expect(abs(split.leading + split.gutter + split.trailing - 919) < 0.01)
        #expect(split.gutter == 32)
        let tabletop = BubuLayout(size: CGSize(width: 669, height: 951), fold: CGRect(x: 0, y: 463.5, width: 669, height: 24))
        #expect(tabletop.columnSplit(minX: 16, width: 637, margin: 4, minPane: 120) == nil)
        #expect(BubuLayout(size: CGSize(width: 951, height: 669)).columnSplit(minX: 16, width: 919, margin: 4, minPane: 120) == nil)
    }

    @Test func noPhotoStraddlesTheFold() throws {
        let split = try #require(innerSplit)
        let items = days(80)
        let layout = build(items, hasMore: false, width: 919, target: 176, split: split)
        let rows = cellRows(layout)
        #expect(!rows.isEmpty)
        for (index, row) in rows.enumerated() {
            let fold = row.foldIndex ?? row.cells.count
            let leading = row.cells[..<fold], trailing = row.cells[fold...]
            #expect(!leading.isEmpty)
            // The leading half ends at the crease, the trailing half starts past it.
            #expect(used(leading) <= split.leading + 0.5)
            #expect(used(trailing) <= split.trailing + 0.5)
            if index < rows.count - 1 {
                #expect(row.foldIndex != nil)
                #expect(abs(used(leading) - split.leading) < 0.5)
                #expect(abs(used(trailing) - split.trailing) < 0.5)
                #expect(row.foldGap == split.gutter)
                #expect(row.height <= 176 * 1.5)
            }
        }
        // A small adjustment, not a reordering: every photo, in order.
        #expect(rows.flatMap(\.cells).map(\.element.id) == items.map { "o-" + $0.id })
    }

    @Test func halvesShareAHeightCloseToBoth() throws {
        let split = try #require(innerSplit)
        let squares = (0..<30).map { item($0, day: "2026-10-01") }
        let rows = cellRows(build(squares, hasMore: false, width: 919, target: 176, split: split))
        // 443pt halves of squares: three per half at (443 − 8) / 3 = 145pt.
        let first = try #require(rows.first)
        #expect(first.foldIndex == 3)
        #expect(first.cells.count == 6)
        #expect(abs(first.height - 145) < 1)
    }

    @Test func pagingUnderAFoldNeverReflowsShownRows() throws {
        let split = try #require(innerSplit)
        let first = days(60)
        let before = build(first, hasMore: true, width: 919, target: 176, split: split)
        let after = build(first + days(60, month: "2026-09", prefix: "b"), hasMore: true, width: 919, target: 176, split: split)
        let again = Dictionary(uniqueKeysWithValues: cellRows(after).map { ($0.id, $0) })
        for row in cellRows(before) {
            let match = try #require(again[row.id])
            #expect(match.height == row.height)
            #expect(match.foldIndex == row.foldIndex)
            #expect(match.cells.map(\.element.id) == row.cells.map(\.element.id))
        }
    }

    // MARK: Event cards don't leave a gap above them

    @Test func runCutShortByAnEventCardFillsTheRow() throws {
        let items = days(12).map { item(Int($0.id.dropFirst())!, day: $0.localDay!) }   // squares
        let event = OnlineTimelineEvent(id: "park", title: "公园", story: nil, day: "2026-10-27", place: nil,
                                        count: 6, coverUrl: nil, itemIds: items[3..<9].map(\.id))
        let layout = build(items, events: [event], hasMore: false)
        let eventIndex = try #require(layout.rowIndex["e-park"])
        guard case .cells(let before) = layout.rows[eventIndex - 1].content else { Issue.record("row before the card"); return }
        #expect(before.cells.count == 3)
        #expect(abs(used(before.cells[...]) - 402) < 0.5)     // fills the width instead of 3 photos + empty space
        #expect(before.height <= 118 * 1.5)
    }

    @Test func aLonePhotoBeforeAnEventCardStaysItsOwnShape() throws {
        let items = (0..<5).map { item($0, day: "2026-10-28") } + (5..<8).map { item($0, day: "2026-10-26") }
        let event = OnlineTimelineEvent(id: "beach", title: "海边", story: nil, day: "2026-10-27", place: nil,
                                        count: 3, coverUrl: nil, itemIds: [])
        let layout = build(items, events: [event], hasMore: false)
        let eventIndex = try #require(layout.rowIndex["e-beach"])
        guard case .cells(let tail) = layout.rows[eventIndex - 1].content else { Issue.record("row before the card"); return }
        #expect(tail.cells.count == 1)
        #expect(tail.cells[0].width < 402)    // never a 402pt crop of one photo
        #expect(tail.height <= 118)
    }

    // MARK: Scrubber skips a horizontal fold

    private func months(_ count: Int) -> [OnlineTimelineMonthCount] {
        (0..<count).map { index in
            let date = BubuLearningDates.calendar.date(byAdding: .month, value: -index, to: BubuLearningDates.day("2026-10-01")!)!
            return OnlineTimelineMonthCount(month: BubuLearningDates.monthKey(date), count: 10)
        }
    }

    @Test func scrubberSharesTheTrackAroundTheFold() throws {
        let list = months(12)
        let scale = OnlineTimelineScrubberScale(months: list, height: 400, skipping: 180...220)
        #expect(scale.trackSegments == [0...180, 220...400])
        #expect(abs(scale.lengths.reduce(0, +) - 360) < 0.5)
        // Month 6 starts right where the band ends.
        #expect(abs(scale.trackY(scale.starts[6]) - 220) < 0.01)
        for month in list {
            let center = try #require(scale.center(of: month.month, clearance: 22))
            #expect(center <= 158 + 0.01 || center >= 242 - 0.01)
            #expect(center >= 0 && center <= 400)
        }
        // A finger on the crease counts for the nearer side.
        #expect(scale.month(at: 185) == list[5].month)
        #expect(scale.month(at: 215) == list[6].month)
        #expect(scale.month(at: 179) == list[5].month)
        #expect(scale.month(at: 221) == list[6].month)
        #expect(scale.clear(195, clearance: 22) == 158)
        #expect(scale.clear(210, clearance: 22) == 242)
    }

    @Test func scrubberWithoutAFoldIsUnchanged() throws {
        let list = months(12)
        let plain = OnlineTimelineScrubberScale(months: list, height: 400)
        let outside = OnlineTimelineScrubberScale(months: list, height: 400, skipping: 500...520)
        #expect(plain.band == nil)
        #expect(outside.band == nil)
        #expect(plain.trackSegments == [0...400])
        for (index, month) in list.enumerated() {
            #expect(plain.center(of: month.month, clearance: 22) == plain.starts[index] + plain.lengths[index] / 2)
            #expect(outside.center(of: month.month) == plain.center(of: month.month))
        }
    }
}
