import Testing
import Foundation
import CoreGraphics
@testable import BubuTimeMachine

// MARK: - 2.27 时光：排版不跳、孤行不放大、事件不重复、拖动条刻度、深链定位
@MainActor
struct Timeline2_27Tests {

    private func item(_ index: Int, day: String, aspect: Double = 1, prefix: String = "a") -> OnlineTimelineItem {
        let id = prefix + String(format: "%023d", index)
        return OnlineTimelineItem(id: id, contentHash: id, kind: "photo", capturedAt: day + "T10:00:00+08:00", localDay: day,
                                  description: "", ocr: "", tags: [], segments: [], labelProvenanceText: "",
                                  previewUrl: "/learning/api/online-timeline/\(id)/preview", largeUrl: "", mediaUrl: "",
                                  aspect: aspect, people: nil, place: "深圳市 · 潜龙·曼海宁", confirmedByFamily: nil,
                                  descriptionAdjusted: nil, transcriptHidden: nil)
    }

    private func days(_ count: Int, month: String = "2026-10", from start: Int = 28, prefix: String = "a") -> [OnlineTimelineItem] {
        (0..<count).map { item($0, day: String(format: "\(month)-%02d", max(1, start - $0 / 3)), prefix: prefix) }
    }

    private func build(_ items: [OnlineTimelineItem], events: [OnlineTimelineEvent] = [], hasMore: Bool,
                       width: CGFloat = 402, target: CGFloat = 118) -> OnlineTimelineLayout {
        OnlineTimelineLayoutBuilder.build(items: items, family: [], events: events, query: OnlineTimelineQuery(),
                                          source: .brain, hasMore: hasMore, width: width, target: target)
    }

    private func cellRows(_ layout: OnlineTimelineLayout) -> [OnlineTimelineRow] {
        layout.rows.compactMap { row in
            if case .cells(let cells) = row.content { return cells }
            return nil
        }
    }

    // MARK: Dates

    @Test func fastDateParseMatchesTheServerFormats() throws {
        let plain = try #require(OnlineTimelineDates.parse("2026-10-14T10:23:45+08:00"))
        #expect(plain == BubuLearningDates.parseISO("2026-10-14T10:23:45+08:00"))
        #expect(OnlineTimelineDates.parse("2026-10-14T10:23:45.123+08:00") != nil)
        #expect(OnlineTimelineDates.parse("2026-10-20T13:10:11Z") != nil)
        #expect(OnlineTimelineDates.parse("not a date") == nil)
        #expect(OnlineTimelineDates.parse(nil) == nil)
    }

    // MARK: Rows

    @Test func pagingNeverReflowsRowsAlreadyShown() {
        let first = days(60)
        let before = build(first, hasMore: true)
        let after = build(first + days(60, month: "2026-09", prefix: "b"), hasMore: true)
        // With more pages coming, the unfinished tail is held back, so every shown row survives as is.
        let shown = cellRows(before)
        let again = Dictionary(uniqueKeysWithValues: cellRows(after).map { ($0.id, $0) })
        for row in shown {
            let match = again[row.id]
            #expect(match != nil)
            #expect(match?.height == row.height)
            #expect(match?.cells.map(\.element.id) == row.cells.map(\.element.id))
        }
    }

    @Test func heldTailShowsOnceTheFeedEnds() {
        let items = days(9)   // 4 + 4 + 1 at 402pt
        let paging = build(items, hasMore: true)
        let done = build(items, hasMore: false)
        #expect(cellRows(paging).flatMap(\.cells).count == 8)
        #expect(cellRows(done).flatMap(\.cells).count == 9)
    }

    @Test func orphanRowIsNeverTallerThanTheRowsAbove() throws {
        let layout = build(days(9), hasMore: false)
        let rows = cellRows(layout)
        let tail = try #require(rows.last)
        let above = rows.dropLast().map(\.height)
        #expect(tail.cells.count == 1)
        #expect(tail.height <= above.reduce(0, +) / CGFloat(above.count) + 0.01)
        #expect(tail.height <= 118)
        // Left-aligned at its own width instead of stretched.
        #expect(tail.cells[0].width < 402)
    }

    @Test func fullRowsFillTheWidthAndStayUnderTarget() {
        let mixed = (0..<40).map { item($0, day: "2026-10-01", aspect: [0.75, 1.33, 1, 1.78][$0 % 4]) }
        for row in cellRows(build(mixed, hasMore: true)) {
            let used = row.cells.reduce(0) { $0 + $1.width } + OnlineTimelineLayoutBuilder.spacing * CGFloat(row.cells.count - 1)
            #expect(abs(used - 402) < 0.5)
            #expect(row.height <= 118)
        }
    }

    @Test func skeletonUsesTheRealRowBreaks() {
        let rows = OnlineTimelineLayoutBuilder.placeholderRows(width: 402, target: 118, rows: 5)
        #expect(rows.count == 5)
        let squares = cellRows(build((0..<20).map { item($0, day: "2026-10-01") }, hasMore: true))
        #expect(rows[0].count == squares[0].cells.count)
        #expect(abs(rows[0].height - squares[0].height) < 0.01)
        #expect(rows[0].count == 4)   // iPhone: four squares per row, not three
    }

    @Test func monthSubtitleKeepsOnePlace() {
        let layout = build(days(3), hasMore: false)
        guard case .header(_, _, let subtitle) = layout.rows.first?.content else { Issue.record("header"); return }
        #expect(subtitle == "照片 3 · 潜龙·曼海宁")
    }

    // MARK: Events

    @Test func eventPhotosMoveIntoTheCardInsteadOfRepeating() {
        let items = days(12)
        let inEvent = Array(items[3..<9]).map(\.id)
        let event = OnlineTimelineEvent(id: "park", title: "公园", story: nil, day: "2026-10-27", place: nil,
                                        count: inEvent.count, coverUrl: nil, itemIds: inEvent)
        let layout = build(items, events: [event], hasMore: false)
        let gridIDs = cellRows(layout).flatMap(\.cells).compactMap { $0.element.onlineItem?.id }
        #expect(Set(gridIDs).isDisjoint(with: inEvent))
        #expect(gridIDs.count == 6)
        #expect(layout.elementCount == 12)
        let thumbs = layout.rows.compactMap { row -> [OnlineTimelineItem]? in
            if case .event(_, let thumbs) = row.content { return thumbs }
            return nil
        }.first
        #expect(thumbs?.map(\.id) == Array(inEvent.prefix(4)))
        // The month still counts every photo.
        guard case .header(_, _, let subtitle) = layout.rows.first?.content else { Issue.record("header"); return }
        #expect(subtitle.hasPrefix("照片 12"))
    }

    // MARK: Deep link

    @Test func dayAnchorsFindTheDayOrTheClosestOne() throws {
        let items = days(30)   // 2026-10-28 … 2026-10-19, three a day
        let layout = build(items, hasMore: false)
        let exact = try #require(layout.anchor(forDay: "2026-10-25"))
        #expect(exact.exact)
        #expect(layout.rowIndex[exact.rowID] != nil)
        let first = try #require(layout.anchor(forDay: "2026-10-28"))
        #expect(first.rowID == "m-2026-10")   // the day opening the month scrolls to the month title
        let near = try #require(layout.anchor(forDay: "2026-10-10"))
        #expect(!near.exact)
        #expect(near.rowID == layout.dayAnchors.last?.rowID)
        #expect(layout.monthRowID("2026-10") == "m-2026-10")
        #expect(layout.monthRowID("2026-08") == "m-2026-10")
    }

    @Test func anchorEndDayCoversMonthsAndDays() {
        #expect(OnlineTimelineQuery.endDay("2025-02") == "2025-02-28")
        #expect(OnlineTimelineQuery.endDay("2024-02") == "2024-02-29")
        #expect(OnlineTimelineQuery.endDay("2025-10-22") == "2025-10-22")
        #expect(OnlineTimelineLayoutBuilder.anchorTitle("2025-10-22") == "2025年10月22日")
        #expect(OnlineTimelineLayoutBuilder.anchorTitle("2025-07") == "2025年7月")
    }

    @Test func familyRecordsRespectTheAnchor() {
        let calendar = BubuLearningDates.calendar
        let october = calendar.date(from: DateComponents(year: 2025, month: 10, day: 22, hour: 12))!
        let november = calendar.date(from: DateComponents(year: 2025, month: 11, day: 3, hour: 12))!
        let family = [OnlineTimelineFamilyRef(id: UUID(), date: november, searchText: "秋千"),
                      OnlineTimelineFamilyRef(id: UUID(), date: october, searchText: "海边")]
        var query = OnlineTimelineQuery()
        query.anchor = "2025-10"
        #expect(OnlineTimelineLayoutBuilder.filteredFamily(family, query: query).map(\.day) == ["2025-10-22"])
        query.anchor = nil
        query.text = "秋千"
        #expect(OnlineTimelineLayoutBuilder.filteredFamily(family, query: query).map(\.day) == ["2025-11-03"])
    }

    // MARK: Scrubber

    private func months(_ counts: [Int]) -> [OnlineTimelineMonthCount] {
        counts.enumerated().map { index, count in
            let date = BubuLearningDates.calendar.date(byAdding: .month, value: -index, to: BubuLearningDates.day("2026-10-01")!)!
            return OnlineTimelineMonthCount(month: BubuLearningDates.monthKey(date), count: count)
        }
    }

    @Test func everyMonthGetsAHittableSegment() {
        let list = months([241, 3, 180, 1, 90, 60, 2, 120, 40, 5, 300, 7] + Array(repeating: 30, count: 18))
        let scale = OnlineTimelineScrubberScale(months: list, height: 560)
        #expect(scale.lengths.allSatisfy { $0 >= 14 - 0.001 })
        #expect(abs(scale.lengths.reduce(0, +) - 560) < 0.5)
        // Every month can be reached by putting a finger in the middle of its segment.
        for (index, month) in list.enumerated() {
            #expect(scale.month(at: scale.starts[index] + scale.lengths[index] / 2) == month.month)
        }
        #expect(scale.month(at: -10) == list.first?.month)
        #expect(scale.month(at: 9999) == list.last?.month)
    }

    @Test func tooManyMonthsShareTheTrackEvenly() {
        let scale = OnlineTimelineScrubberScale(months: months(Array(repeating: 10, count: 50)), height: 400)
        #expect(scale.lengths.allSatisfy { abs($0 - 8) < 0.001 })
    }

    @Test func thumbFollowsTheMonthOrTheNextOlderOne() throws {
        let list = months([10, 10, 10])
        let scale = OnlineTimelineScrubberScale(months: list, height: 300)
        let middle = try #require(scale.center(of: list[1].month))
        #expect(abs(middle - 150) < 0.5)
        #expect(scale.center(of: "2099-01") == scale.center(of: list[0].month))
        #expect(scale.center(of: "1999-01") == scale.center(of: list[2].month))
    }

    @Test func yearMarksSitAtTheFirstMonthOfEachYear() {
        let scale = OnlineTimelineScrubberScale(months: months(Array(repeating: 20, count: 24)), height: 600)
        #expect(scale.yearMarks.map(\.year) == ["2026", "2025", "2024"])
        #expect(scale.yearMarks.first?.offset == 0)
    }
}
