import SwiftUI
import SwiftData

// MARK: - 时光合成流的排版
/// 把在线素材、家人记录和事件卡排成一维的行列表，交给 LazyVStack 逐行懒加载：
/// 月份标题、每一行照片、每张事件卡都是独立的一行。
/// 全部输入都是 Sendable 值，排版在后台线程算，算完回主线程一次赋值；滚动和拖动月份条不重算。

/// What the stream shows; also the key for paging and the offline cache.
nonisolated struct OnlineTimelineQuery: Hashable, Sendable {
    var text = ""
    var kind = OnlineTimelineKind.all
    var range = OnlineTimelineRange.all
    var newestFirst = true
    var person: String?
    /// Jump target the list ends at: "yyyy-MM" (end of that month) or "yyyy-MM-dd" (that day).
    var anchor: String?

    var isDefault: Bool { self == OnlineTimelineQuery() }
    /// Narrowed by something the family picked; order and anchor aren't filters.
    var isFiltered: Bool { !text.isEmpty || kind != .all || range != .all || person != nil }
    /// Last day the anchor keeps.
    var anchorEndDay: String? { anchor.map(Self.endDay) }

    /// "2025-07" → "2025-07-31"; a day stays as it is.
    static func endDay(_ anchor: String) -> String {
        guard anchor.count == 7, let first = BubuLearningDates.day(anchor + "-01"),
              let last = BubuLearningDates.calendar.date(byAdding: DateComponents(month: 1, day: -1), to: first)
        else { return anchor }
        return BubuLearningDates.dayString(last)
    }
}

nonisolated enum OnlineTimelineDates {
    /// About 1µs per value. The shared ISO8601DateFormatter tried fractional seconds first,
    /// which always failed on the server's format and cost about 80µs per item on every rebuild.
    static func parse(_ value: String?) -> Date? {
        value.flatMap { try? Date($0, strategy: .iso8601) }
    }
}

/// A family record reduced to what layout and filtering need, read once on the main actor.
nonisolated struct OnlineTimelineFamilyRef: Sendable, Hashable {
    let id: UUID
    let date: Date
    let day: String
    let hasCover: Bool
    let hasPhoto: Bool
    let hasVideo: Bool
    /// Lowercased title, note, first-person note and place.
    let searchText: String

    init(id: UUID, date: Date, hasCover: Bool = false, hasPhoto: Bool = false, hasVideo: Bool = false, searchText: String = "") {
        self.id = id
        self.date = date
        self.day = BubuLearningDates.dayString(date)
        self.hasCover = hasCover
        self.hasPhoto = hasPhoto
        self.hasVideo = hasVideo
        self.searchText = searchText
    }

    @MainActor
    init(_ entry: Entry) {
        self.init(id: entry.id, date: entry.happenedAt, hasCover: entry.coverMedia != nil,
                  hasPhoto: entry.media.contains { $0.type == .photo },
                  hasVideo: entry.media.contains { $0.type == .video },
                  searchText: [entry.title, entry.note, entry.firstPersonNote, entry.locationName]
                    .compactMap { $0 }.joined(separator: " ").lowercased())
    }
}

/// One cell of the merged stream; its date and Shanghai day are computed once when built.
nonisolated enum OnlineTimelineElement: Identifiable, Sendable {
    case online(OnlineTimelineItem, date: Date, day: String)
    case family(OnlineTimelineFamilyRef)

    init(_ item: OnlineTimelineItem) {
        let date = OnlineTimelineDates.parse(item.capturedAt)
        // The server already sends the Shanghai day; formatting it again per item is wasted work.
        let day = item.localDay.flatMap { $0.count == 10 ? $0 : nil } ?? date.map(BubuLearningDates.dayString) ?? ""
        self = .online(item, date: date ?? .distantPast, day: day)
    }

    init(_ family: OnlineTimelineFamilyRef) { self = .family(family) }

    var id: String {
        switch self {
        case .online(let item, _, _): "o-" + item.id
        case .family(let family): "f-" + family.id.uuidString
        }
    }
    var date: Date {
        switch self {
        case .online(_, let date, _): date
        case .family(let family): family.date
        }
    }
    /// "yyyy-MM-dd" in Asia/Shanghai; empty when the item has no capture time.
    var day: String {
        switch self {
        case .online(_, _, let day): day
        case .family(let family): family.day
        }
    }
    var monthKey: String { String(day.prefix(7)) }
    var aspect: Double {
        switch self {
        case .online(let item, _, _): item.layoutAspect
        case .family(let family): family.hasCover ? 1 : 1.25
        }
    }
    var onlineItem: OnlineTimelineItem? {
        if case .online(let item, _, _) = self { return item }
        return nil
    }
}

nonisolated struct OnlineTimelineRow: Identifiable, Sendable {
    let id: String
    let cells: [(element: OnlineTimelineElement, width: CGFloat)]
    let height: CGFloat
    /// Under a vertical fold: how many cells sit before the crease; `foldGap` replaces the spacing after them.
    var foldIndex: Int? = nil
    var foldGap: CGFloat = 0
}

/// Where the photo rows sit (global coordinates; minus `BubuLayout.origin` for root ones). Measured on the scroll container,
/// never on a row that scrolls away (and unloads), so a rotation or fold deep in the list still rebuilds.
nonisolated struct OnlineTimelineColumn: Equatable, Sendable {
    var minX: CGFloat = 0
    var width: CGFloat = 360
}

/// One lazily built line of the stream.
nonisolated struct OnlineTimelineDisplayRow: Identifiable, Sendable {
    enum Content: Sendable {
        case header(key: String, title: String, subtitle: String)
        case cells(OnlineTimelineRow)
        /// `thumbs`: the event's photos already loaded, which the grid leaves out.
        case event(OnlineTimelineEvent, thumbs: [OnlineTimelineItem])
    }
    let id: String
    let index: Int
    let content: Content
}

nonisolated struct OnlineTimelineLayout: Sendable {
    var rows: [OnlineTimelineDisplayRow] = []
    /// Photos, videos and family records (events not counted), including those folded into event cards.
    var elementCount = 0
    /// Family records shown under the current filters.
    var familyCount = 0
    /// Row id → its index and month, for the scrubber and scroll targets.
    var rowIndex: [String: Int] = [:]
    var monthOfRow: [String: String] = [:]
    /// First row of each day in display order (the month header when the day opens the month).
    var dayAnchors: [(day: String, rowID: String)] = []
    var isEmpty: Bool { elementCount == 0 }

    /// Header row of `month`, or of the nearest older month shown (newer when nothing older is loaded).
    func monthRowID(_ month: String) -> String? {
        let headers = rows.compactMap { row -> String? in
            if case .header(let key, _, _) = row.content { return key }
            return nil
        }
        guard !headers.isEmpty else { return nil }
        if headers.contains(month) { return "m-" + month }
        let newestFirst = (headers.first ?? "") >= (headers.last ?? "")
        let pick = newestFirst ? (headers.first { $0 < month } ?? headers.last) : (headers.first { $0 > month } ?? headers.last)
        return pick.map { "m-" + $0 }
    }

    /// Row for a day, or for the closest day shown (ties go to the older day).
    func anchor(forDay day: String) -> (rowID: String, exact: Bool)? {
        if let hit = dayAnchors.first(where: { $0.day == day }) { return (hit.rowID, true) }
        guard let target = BubuLearningDates.day(day) else { return nil }
        var best: (rowID: String, distance: TimeInterval, date: Date)?
        for anchor in dayAnchors {
            guard let date = BubuLearningDates.day(anchor.day) else { continue }
            let distance = abs(date.timeIntervalSince(target))
            if best == nil || distance < best!.distance || (distance == best!.distance && date < best!.date) {
                best = (anchor.rowID, distance, date)
            }
        }
        return best.map { ($0.rowID, false) }
    }

    // MARK: Scroll anchor (fold / unfold / rotation)

    /// What marks `rowID` at the top of the screen across a rebuild: the first photo of a photo row
    /// (row ids change with the width), or the row itself for month titles and event cards (their ids never do).
    func anchorID(forRow rowID: String) -> String? {
        guard let index = rowIndex[rowID] else { return nil }
        if case .cells(let cells) = rows[index].content { return cells.cells.first?.element.id }
        return rowID
    }

    /// Row that now holds `anchor` (an element id, or a month / event row id).
    func rowID(holding anchor: String) -> String? {
        if rowIndex[anchor] != nil { return anchor }
        for row in rows {
            if case .cells(let cells) = row.content, cells.cells.contains(where: { $0.element.id == anchor }) { return row.id }
        }
        return nil
    }
}

/// Where an event card sits among the stream's elements.
nonisolated enum OnlineTimelineSlot<Element> {
    case element(Element)
    case event(OnlineTimelineEvent)
}

nonisolated enum OnlineTimelineLayoutBuilder {
    static let spacing: CGFloat = 4

    // MARK: Merging

    /// Family records after the stream's search, date, kind and anchor filters.
    static func filteredFamily(_ family: [OnlineTimelineFamilyRef], query: OnlineTimelineQuery,
                               now: Date = .now) -> [OnlineTimelineFamilyRef] {
        let text = query.text.lowercased()
        let (start, end) = query.range.bounds(now: now)
        let anchorEnd = query.anchorEndDay
        return family.filter { record in
            if !text.isEmpty, !record.searchText.contains(text) { return false }
            if let start, record.day < start { return false }
            if let end, record.day > end { return false }
            if let anchorEnd, record.day > anchorEnd { return false }
            switch query.kind {
            case .all: return true
            case .photo: return record.hasPhoto
            case .video: return record.hasVideo
            }
        }
    }

    /// The stream's elements in display order. `family` arrives newest first.
    static func elements(items: [OnlineTimelineItem], family: [OnlineTimelineFamilyRef], query: OnlineTimelineQuery,
                         source: OnlineTimelineSource, hasMore: Bool, now: Date = .now)
        -> (elements: [OnlineTimelineElement], familyCount: Int) {
        let newestFirst = query.newestFirst
        func ordered(_ list: [OnlineTimelineElement]) -> [OnlineTimelineElement] {
            list.sorted { newestFirst ? $0.date > $1.date : $0.date < $1.date }
        }
        let records = source == .brain ? [] : filteredFamily(family, query: query, now: now)
        switch source {
        case .brain:
            // Search returns relevance first; the grid groups by month, so show it in date order.
            let list = items.map(OnlineTimelineElement.init)
            return (query.text.isEmpty ? list : ordered(list), 0)
        case .family:
            return ((newestFirst ? records : records.reversed()).map(OnlineTimelineElement.init), records.count)
        case .merged:
            let online = items.map(OnlineTimelineElement.init)
            guard query.person == nil else { return (online, 0) }
            // Only merge family records inside the time span already loaded, so paging stays in order.
            let loaded = online.compactMap { $0.onlineItem?.capturedAt == nil ? nil : $0.date }
            let boundary = hasMore ? (newestFirst ? loaded.min() : loaded.max()) : nil
            let kept = records.filter { record in
                guard let boundary else { return true }
                return newestFirst ? record.date >= boundary : record.date <= boundary
            }
            return (ordered(online + kept.map(OnlineTimelineElement.init)), records.count)
        }
    }

    /// Everything from raw inputs to rows; runs off the main actor.
    static func build(items: [OnlineTimelineItem], family: [OnlineTimelineFamilyRef], events: [OnlineTimelineEvent],
                      query: OnlineTimelineQuery, source: OnlineTimelineSource, hasMore: Bool,
                      width: CGFloat, target: CGFloat, split: BubuLayout.ColumnSplit? = nil) -> OnlineTimelineLayout {
        let merged = elements(items: items, family: family, query: query, source: source, hasMore: hasMore)
        var layout = build(elements: merged.elements, events: events, newestFirst: query.newestFirst, hasMore: hasMore,
                           width: width, target: target, foldEventItems: !events.isEmpty, split: split)
        layout.familyCount = merged.familyCount
        return layout
    }

    // MARK: Events

    /// Events inside the loaded span; once everything is loaded, also those beyond the far end.
    static func keptEvents(days: [String], events: [OnlineTimelineEvent], newestFirst: Bool, hasMore: Bool) -> [OnlineTimelineEvent] {
        let days = days.filter { !$0.isEmpty }
        guard let low = days.min(), let high = days.max() else { return [] }
        return events
            .filter { event in
                if event.day >= low && event.day <= high { return true }
                return !hasMore && (newestFirst ? event.day < low : event.day > high)
            }
            .sorted { newestFirst ? ($0.day, $0.id) > ($1.day, $1.id) : ($0.day, $0.id) < ($1.day, $1.id) }
    }

    /// Places each kept event right before the first element of its day (in display order).
    static func place<Element>(_ elements: [Element], day: (Element) -> String, events kept: [OnlineTimelineEvent],
                               newestFirst: Bool) -> [OnlineTimelineSlot<Element>] {
        var result: [OnlineTimelineSlot<Element>] = []
        result.reserveCapacity(elements.count + kept.count)
        var next = 0
        for element in elements {
            let elementDay = day(element)
            while next < kept.count, !elementDay.isEmpty,
                  newestFirst ? elementDay <= kept[next].day : elementDay >= kept[next].day {
                result.append(.event(kept[next]))
                next += 1
            }
            result.append(.element(element))
        }
        result.append(contentsOf: kept[next...].map { .event($0) })
        return result
    }

    /// Only events inside the loaded span are kept, so paging never piles cards at the end;
    /// once everything is loaded, events beyond the far end follow the last element.
    static func interleave<Element>(_ elements: [Element], day: (Element) -> String, events: [OnlineTimelineEvent],
                                    newestFirst: Bool, hasMore: Bool) -> [OnlineTimelineSlot<Element>] {
        let kept = keptEvents(days: elements.map(day), events: events, newestFirst: newestFirst, hasMore: hasMore)
        guard !kept.isEmpty else { return elements.map { .element($0) } }
        return place(elements, day: day, events: kept, newestFirst: newestFirst)
    }

    // MARK: Rows

    /// `foldEventItems`: photos that belong to a shown event card appear in the card, not again in the grid.
    /// `split`: a vertical fold crossing the column (row coordinates); every photo row breaks at it.
    static func build(elements: [OnlineTimelineElement], events: [OnlineTimelineEvent], newestFirst: Bool,
                      hasMore: Bool, width: CGFloat, target: CGFloat, foldEventItems: Bool = false,
                      split: BubuLayout.ColumnSplit? = nil) -> OnlineTimelineLayout {
        let kept = keptEvents(days: elements.map(\.day), events: events, newestFirst: newestFirst, hasMore: hasMore)
        var visible = elements
        var thumbs: [String: [OnlineTimelineItem]] = [:]
        if foldEventItems, !kept.isEmpty {
            var byID: [String: OnlineTimelineItem] = [:]
            for element in elements { if let item = element.onlineItem { byID[item.id] = item } }
            var folded = Set<String>()
            for event in kept {
                let loaded = event.itemIds.compactMap { byID[$0] }
                thumbs[event.id] = loaded
                folded.formUnion(loaded.map(\.id))
            }
            if !folded.isEmpty {
                visible = elements.filter { element in element.onlineItem.map { !folded.contains($0.id) } ?? true }
            }
        }
        let slots = kept.isEmpty ? visible.map { OnlineTimelineSlot.element($0) }
                                 : place(visible, day: \.day, events: kept, newestFirst: newestFirst)
        var order: [String] = []
        var grouped: [String: [OnlineTimelineSlot<OnlineTimelineElement>]] = [:]
        for slot in slots {
            let key: String
            switch slot {
            case .element(let element): key = element.monthKey
            case .event(let event): key = String(event.day.prefix(7))
            }
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(slot)
        }
        // Month counts include photos folded into cards.
        var monthElements: [String: [OnlineTimelineElement]] = [:]
        for element in elements { monthElements[element.monthKey, default: []].append(element) }

        var layout = OnlineTimelineLayout(elementCount: elements.count)
        var headerIndex = 0
        var seenDays = Set<String>()
        func add(_ id: String, month: String, _ content: OnlineTimelineDisplayRow.Content) {
            let index = layout.rows.count
            layout.rows.append(OnlineTimelineDisplayRow(id: id, index: index, content: content))
            layout.rowIndex[id] = index
            layout.monthOfRow[id] = month
        }
        func mark(_ day: String, rowID: String) {
            guard !day.isEmpty, seenDays.insert(day).inserted else { return }
            // A day that opens the month scrolls to the month title so the month stays readable.
            let target = layout.rows.count - 1 == headerIndex + 1 ? layout.rows[headerIndex].id : rowID
            layout.dayAnchors.append((day, target))
        }
        let rowWidth = max(width, 200)
        for (groupIndex, key) in order.enumerated() {
            let group = grouped[key] ?? []
            headerIndex = layout.rows.count
            add("m-" + key, month: key, .header(key: key, title: monthTitle(key), subtitle: subtitle(monthElements[key] ?? [])))
            let lastGroup = groupIndex == order.count - 1
            var fullHeights: [CGFloat] = []
            var pending: [OnlineTimelineElement] = []
            func flush(final: Bool) {
                defer { pending = [] }
                guard !pending.isEmpty else { return }
                let cap = fullHeights.isEmpty ? nil : fullHeights.reduce(0, +) / CGFloat(fullHeights.count)
                // A run cut short by an event card is complete: it stretches instead of leaving a gap above the card.
                let rows = justify(pending, width: rowWidth, target: target, holdTail: final && lastGroup && hasMore,
                                   tailCap: cap, fillTail: !final, split: split)
                for row in rows {
                    if row.id != rows.last?.id { fullHeights.append(row.height) }
                    add(row.id, month: key, .cells(row))
                    for cell in row.cells { mark(cell.element.day, rowID: row.id) }
                }
            }
            for (slotIndex, slot) in group.enumerated() {
                switch slot {
                case .element(let element):
                    pending.append(element)
                case .event(let event):
                    flush(final: false)
                    let id = "e-" + event.id
                    add(id, month: key, .event(event, thumbs: Array((thumbs[event.id] ?? []).prefix(4))))
                    mark(event.day, rowID: id)
                }
                if slotIndex == group.count - 1 { flush(final: true) }
            }
        }
        return layout
    }

    /// "照片 12 · 视频 2 · 家人记录 3 · 曼海宁": one place at most, so the month header stays one line.
    static func subtitle(_ group: [OnlineTimelineElement]) -> String {
        var photos = 0, videos = 0, family = 0
        var place: String?
        for element in group {
            guard let item = element.onlineItem else { family += 1; continue }
            if item.isVideo { videos += 1 } else { photos += 1 }
            // "深圳市 · 潜龙·曼海宁" → "潜龙·曼海宁".
            if place == nil, let last = item.place?.components(separatedBy: " · ").last?.trimmingCharacters(in: .whitespaces),
               !last.isEmpty { place = last }
        }
        var parts: [String] = []
        if photos > 0 { parts.append("照片 \(photos)") }
        if videos > 0 { parts.append("视频 \(videos)") }
        if family > 0 { parts.append("家人记录 \(family)") }
        if let place { parts.append(place) }
        return parts.joined(separator: " · ")
    }

    /// Greedy row breaks over aspect ratios (width / height). Full rows end as soon as their
    /// justified height drops to `target`; the last range is the unfinished tail (`full == false`).
    static func breaks(_ aspects: [Double], width: CGFloat, target: CGFloat) -> [(range: Range<Int>, height: CGFloat, full: Bool)] {
        var result: [(range: Range<Int>, height: CGFloat, full: Bool)] = []
        var start = 0
        var aspectSum = 0.0
        for (index, aspect) in aspects.enumerated() {
            aspectSum += aspect
            let count = index - start + 1
            let height = (width - spacing * CGFloat(count - 1)) / CGFloat(aspectSum)
            if height <= target {
                result.append((start..<index + 1, height, true))
                start = index + 1
                aspectSum = 0
            }
        }
        if start < aspects.count {
            let count = aspects.count - start
            result.append((start..<aspects.count, (width - spacing * CGFloat(count - 1)) / CGFloat(aspectSum), false))
        }
        return result
    }

    /// The first run starting at `start`: ends as soon as its justified height drops to `target` (`full`),
    /// otherwise takes everything left at its natural height.
    static func run(_ aspects: [Double], from start: Int, width: CGFloat, target: CGFloat) -> (count: Int, height: CGFloat, full: Bool) {
        var aspectSum = 0.0
        for index in aspects.indices.dropFirst(start) {
            aspectSum += aspects[index]
            let count = index - start + 1
            let height = (width - spacing * CGFloat(count - 1)) / CGFloat(aspectSum)
            if height <= target { return (count, height, true) }
        }
        let count = aspects.count - start
        guard count > 0 else { return (0, 0, false) }
        return (count, (width - spacing * CGFloat(count - 1)) / CGFloat(aspectSum), false)
    }

    /// Justified rows (flickr/justified-layout idea): equal height per row, widths follow the photo's shape.
    /// Row ids come from their first element, so rows above a newly loaded page keep their identity.
    /// The unfinished tail never grows past the rows above it and stays left-aligned; with `holdTail`
    /// (more pages coming) it is left out, so rows already on screen never re-justify when a page lands.
    /// `fillTail`: the tail is complete (an event card follows), so two or more photos stretch across the row.
    /// `split`: a vertical fold crosses the row; see `justifySplit`.
    static func justify(_ elements: [OnlineTimelineElement], width: CGFloat, target: CGFloat,
                        holdTail: Bool = false, tailCap: CGFloat? = nil, fillTail: Bool = false,
                        split: BubuLayout.ColumnSplit? = nil) -> [OnlineTimelineRow] {
        if let split {
            return justifySplit(elements, width: width, split: split, target: target,
                                holdTail: holdTail, tailCap: tailCap, fillTail: fillTail)
        }
        let pieces = breaks(elements.map(\.aspect), width: width, target: target)
        let fullHeights = pieces.filter(\.full).map(\.height)
        let average = fullHeights.isEmpty ? nil : fullHeights.reduce(0, +) / CGFloat(fullHeights.count)
        var rows: [OnlineTimelineRow] = []
        for piece in pieces {
            let slice = elements[piece.range]
            let id = "r-" + slice[slice.startIndex].id
            if piece.full {
                rows.append(OnlineTimelineRow(id: id, cells: slice.map { ($0, CGFloat($0.aspect) * piece.height) }, height: piece.height))
            } else {
                if holdTail { break }
                let tail = tailCells(slice, natural: piece.height, cap: tailCap ?? average ?? target * 0.85,
                                     target: target, fill: fillTail)
                rows.append(OnlineTimelineRow(id: id, cells: tail.cells, height: tail.height))
            }
        }
        return rows
    }

    /// An unfinished tail at `natural` height (the height that would fill its width). Left-aligned at its own
    /// shape and never taller than `cap` or `target`; with `fill`, two or more photos keep the widths that fill
    /// the row and crop down to at most 1.5 × target, so no big empty area is left beside them.
    static func tailCells(_ slice: ArraySlice<OnlineTimelineElement>, natural: CGFloat, cap: CGFloat, target: CGFloat,
                          fill: Bool) -> (cells: [(element: OnlineTimelineElement, width: CGFloat)], height: CGFloat) {
        if fill, slice.count >= 2 {
            return (slice.map { ($0, CGFloat($0.aspect) * natural) }, min(natural, target * 1.5))
        }
        let height = min(natural, cap, target)
        return (slice.map { ($0, CGFloat($0.aspect) * height) }, height)
    }

    /// Rows for a column a vertical fold splits in two: each row breaks at the fold, so the crease falls in the gap
    /// between its halves and no photo straddles it. Order is kept — the leading half takes the next photos, the
    /// trailing half the ones after. Each half is justified on its own; the trailing half takes the count whose
    /// height is closest to the leading half's and both share their mean height (cells crop-fill, so the small
    /// change of shape doesn't show). Tails follow the same hold / cap / fill rules as `justify`.
    static func justifySplit(_ elements: [OnlineTimelineElement], width: CGFloat, split: BubuLayout.ColumnSplit,
                             target: CGFloat, holdTail: Bool = false, tailCap: CGFloat? = nil,
                             fillTail: Bool = false) -> [OnlineTimelineRow] {
        let aspects = elements.map(\.aspect)
        let leadingWidth = max(split.leading, 1)
        let trailingWidth = max(width - split.leading - split.gutter, 1)
        var rows: [OnlineTimelineRow] = []
        var fullHeights: [CGFloat] = []
        func cells(_ range: Range<Int>, height: CGFloat) -> [(element: OnlineTimelineElement, width: CGFloat)] {
            elements[range].map { ($0, CGFloat($0.aspect) * height) }
        }
        var start = 0
        while start < elements.count {
            let id = "r-" + elements[start].id
            let leading = run(aspects, from: start, width: leadingWidth, target: target)
            guard leading.full else {
                // The tail ends inside the leading half.
                if !holdTail {
                    let average = fullHeights.isEmpty ? nil : fullHeights.reduce(0, +) / CGFloat(fullHeights.count)
                    let tail = tailCells(elements[start...], natural: leading.height,
                                         cap: tailCap ?? average ?? target * 0.85, target: target, fill: fillTail)
                    rows.append(OnlineTimelineRow(id: id, cells: tail.cells, height: tail.height))
                }
                break
            }
            let middle = start + leading.count
            let trailing = middle < elements.count
                ? closestRun(aspects, from: middle, width: trailingWidth, target: target, near: leading.height) : nil
            guard let trailing, trailing.full else {
                // The trailing half is unfinished: with more pages coming the whole row waits, since a later photo
                // would change its height.
                if !holdTail {
                    var row = cells(start..<middle, height: leading.height)
                    if let trailing {
                        // Fill the half when the crop stays mild, else keep the photos' own shape, left-aligned.
                        let fills = fillTail && trailing.count >= 2 && trailing.height <= leading.height * 1.5
                        row += cells(middle..<elements.count, height: fills ? trailing.height : leading.height)
                    }
                    rows.append(OnlineTimelineRow(id: id, cells: row, height: leading.height,
                                                  foldIndex: trailing == nil ? nil : leading.count, foldGap: split.gutter))
                }
                break
            }
            let height = (leading.height + trailing.height) / 2
            let end = middle + trailing.count
            rows.append(OnlineTimelineRow(id: id, cells: cells(start..<middle, height: leading.height)
                                                       + cells(middle..<end, height: trailing.height),
                                          height: height, foldIndex: leading.count, foldGap: split.gutter))
            fullHeights.append(height)
            start = end
        }
        return rows
    }

    /// The trailing half's run whose height is closest to `height`: the greedy run, or one photo fewer.
    static func closestRun(_ aspects: [Double], from start: Int, width: CGFloat, target: CGFloat,
                           near height: CGFloat) -> (count: Int, height: CGFloat, full: Bool) {
        let greedy = run(aspects, from: start, width: width, target: target)
        guard greedy.full, greedy.count > 1 else { return greedy }
        let count = greedy.count - 1
        let fewer = (width - spacing * CGFloat(count - 1)) / CGFloat(aspects[start..<start + count].reduce(0, +))
        return abs(fewer - height) < abs(greedy.height - height) ? (count, fewer, true) : greedy
    }

    /// Skeleton rows cut by the same row-break rule as square photos, so loading → loaded doesn't reflow.
    static func placeholderRows(width: CGFloat, target: CGFloat, rows: Int) -> [(count: Int, height: CGFloat)] {
        breaks(Array(repeating: 1, count: 64), width: max(width, 200), target: target)
            .filter(\.full).prefix(rows).map { ($0.range.count, $0.height) }
    }

    static func monthTitle(_ key: String) -> String {
        let parts = key.split(separator: "-")
        return parts.count == 2 ? "\(parts[0])年\(Int(parts[1]) ?? 0)月" : "未知日期"
    }

    /// "2025-10-22" → "2025年10月22日"; a month key gets the month title.
    static func anchorTitle(_ anchor: String) -> String {
        let parts = anchor.split(separator: "-")
        guard parts.count == 3 else { return monthTitle(anchor) }
        return "\(parts[0])年\(Int(parts[1]) ?? 0)月\(Int(parts[2]) ?? 0)日"
    }
}

// MARK: - 月份拖动条的刻度

/// Track geometry for the month scrubber. Segment length follows how many items a month holds
/// (like Immich), but every month gets at least `minSegment` so small months stay hittable.
/// A horizontal fold crossing the track (`band`, track coordinates) is skipped: months share the track
/// above and below it, and neither the thumb nor a month ever sits on the crease.
nonisolated struct OnlineTimelineScrubberScale {
    let months: [OnlineTimelineMonthCount]
    /// Segment starts and lengths along the track with the band taken out; `trackY` maps them onto the track.
    private(set) var starts: [CGFloat] = []
    private(set) var lengths: [CGFloat] = []
    let height: CGFloat
    private(set) var band: ClosedRange<CGFloat>?

    init(months: [OnlineTimelineMonthCount], height: CGFloat, minSegment: CGFloat = 14, skipping band: ClosedRange<CGFloat>? = nil) {
        self.months = months
        self.height = max(height, 1)
        if let band {
            let lower = max(0, band.lowerBound), upper = min(self.height, band.upperBound)
            self.band = upper - lower >= 1 ? lower...upper : nil
        }
        guard !months.isEmpty else { return }
        let usable = max(self.height - bandLength, 1)
        let count = CGFloat(months.count)
        let floor = min(minSegment, usable / count)
        let spare = usable - floor * count
        let total = CGFloat(max(1, months.reduce(0) { $0 + max(0, $1.count) }))
        var cursor: CGFloat = 0
        for month in months {
            let length = floor + spare * CGFloat(max(0, month.count)) / total
            starts.append(cursor)
            lengths.append(length)
            cursor += length
        }
    }

    private var bandLength: CGFloat { band.map { $0.upperBound - $0.lowerBound } ?? 0 }

    /// Band-free offset → track offset: everything from the band's top on moves below it.
    func trackY(_ y: CGFloat) -> CGFloat {
        guard let band, y >= band.lowerBound else { return y }
        return y + bandLength
    }

    /// Track offset → band-free offset; a point on the band counts for the nearer side.
    func scaleY(_ y: CGFloat) -> CGFloat {
        guard let band, y >= band.lowerBound else { return y }
        if y >= band.upperBound { return y - bandLength }
        return y - band.lowerBound < band.upperBound - y ? band.lowerBound.nextDown : band.lowerBound
    }

    /// `y` moved off the band by at least `clearance` (half the thumb), to the nearer side.
    func clear(_ y: CGFloat, clearance: CGFloat) -> CGFloat {
        guard let band, y > band.lowerBound - clearance, y < band.upperBound + clearance else { return y }
        let above = band.lowerBound - clearance, below = band.upperBound + clearance
        let pick = (y - above < below - y && above >= 0) || below > height ? above : below
        return min(max(pick, 0), height)
    }

    /// The track's visible pieces (one, or two around the band).
    var trackSegments: [ClosedRange<CGFloat>] {
        guard let band else { return [0...height] }
        return [0...band.lowerBound, band.upperBound...height].filter { $0.upperBound - $0.lowerBound >= 1 }
    }

    func month(at y: CGFloat) -> String? {
        guard !months.isEmpty else { return nil }
        let y = scaleY(y)
        for index in months.indices where y < starts[index] + lengths[index] { return months[index].month }
        return months.last?.month
    }

    /// Middle of a month's segment on the track; a month the server didn't list snaps to the next older one.
    /// `clearance` keeps a thumb of twice that height off the band.
    func center(of month: String, clearance: CGFloat = 0) -> CGFloat? {
        guard !months.isEmpty else { return nil }
        let index = months.firstIndex { $0.month <= month } ?? months.count - 1
        return clear(trackY(starts[index] + lengths[index] / 2), clearance: clearance)
    }

    /// Year labels (track offsets) where the year changes, skipping ones that would overlap.
    var yearMarks: [(year: String, offset: CGFloat)] {
        var marks: [(year: String, offset: CGFloat)] = []
        var previous = ""
        for (index, month) in months.enumerated() {
            let year = String(month.month.prefix(4))
            guard year != previous else { continue }
            previous = year
            let offset = trackY(starts[index])
            if let last = marks.last, offset - last.offset < 18 { continue }
            marks.append((year, offset))
        }
        return marks
    }
}
