import SwiftUI
import SwiftData

// MARK: - 时光合成流的排版
/// 把在线素材、家人记录和事件卡排成一维的行列表，交给 LazyVStack 逐行懒加载：
/// 月份标题、每一行照片、每张事件卡都是独立的一行。只在输入变化时重算，滚动和拖动月份条不重算。

/// One cell of the merged stream; its date and Shanghai day are computed once when built.
enum OnlineTimelineElement: Identifiable {
    case online(OnlineTimelineItem, date: Date, day: String)
    case family(Entry, day: String)

    init(_ item: OnlineTimelineItem) {
        let date = item.capturedDate
        self = .online(item, date: date ?? .distantPast, day: date.map(BubuLearningDates.dayString) ?? "")
    }

    init(_ entry: Entry) {
        self = .family(entry, day: BubuLearningDates.dayString(entry.happenedAt))
    }

    var id: String {
        switch self {
        case .online(let item, _, _): "o-" + item.id
        case .family(let entry, _): "f-" + entry.id.uuidString
        }
    }
    var date: Date {
        switch self {
        case .online(_, let date, _): date
        case .family(let entry, _): entry.happenedAt
        }
    }
    /// "yyyy-MM-dd" in Asia/Shanghai; empty when the item has no capture time.
    var day: String {
        switch self {
        case .online(_, _, let day), .family(_, let day): day
        }
    }
    var monthKey: String { String(day.prefix(7)) }
    var aspect: Double {
        switch self {
        case .online(let item, _, _): item.layoutAspect
        case .family(let entry, _): entry.coverMedia == nil ? 1.25 : 1
        }
    }
    var onlineItem: OnlineTimelineItem? {
        if case .online(let item, _, _) = self { return item }
        return nil
    }
}

struct OnlineTimelineRow: Identifiable {
    let id: String
    let cells: [(element: OnlineTimelineElement, width: CGFloat)]
    let height: CGFloat
}

/// One lazily built line of the stream.
struct OnlineTimelineDisplayRow: Identifiable {
    enum Content {
        case header(key: String, title: String, subtitle: String)
        case cells(OnlineTimelineRow)
        case event(OnlineTimelineEvent)
    }
    let id: String
    let index: Int
    let content: Content
}

struct OnlineTimelineLayout {
    var rows: [OnlineTimelineDisplayRow] = []
    /// Photos, videos and family records (events not counted).
    var elementCount = 0
    var isEmpty: Bool { elementCount == 0 }
}

/// Where an event card sits among the stream's elements.
enum OnlineTimelineSlot<Element> {
    case element(Element)
    case event(OnlineTimelineEvent)
}

enum OnlineTimelineLayoutBuilder {
    static let spacing: CGFloat = 4

    /// Places each event card right before the first element of its day (in display order).
    /// Only events inside the loaded span are kept, so paging never piles cards at the end;
    /// once everything is loaded, events beyond the far end follow the last element.
    static func interleave<Element>(_ elements: [Element], day: (Element) -> String, events: [OnlineTimelineEvent],
                                    newestFirst: Bool, hasMore: Bool) -> [OnlineTimelineSlot<Element>] {
        let days = elements.map(day).filter { !$0.isEmpty }
        guard let low = days.min(), let high = days.max() else { return elements.map { .element($0) } }
        let kept = events
            .filter { event in
                if event.day >= low && event.day <= high { return true }
                return !hasMore && (newestFirst ? event.day < low : event.day > high)
            }
            .sorted { newestFirst ? ($0.day, $0.id) > ($1.day, $1.id) : ($0.day, $0.id) < ($1.day, $1.id) }
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

    static func build(elements: [OnlineTimelineElement], events: [OnlineTimelineEvent], newestFirst: Bool,
                      hasMore: Bool, width: CGFloat, target: CGFloat) -> OnlineTimelineLayout {
        let slots = interleave(elements, day: \.day, events: events, newestFirst: newestFirst, hasMore: hasMore)
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
        var rows: [OnlineTimelineDisplayRow] = []
        func add(_ id: String, _ content: OnlineTimelineDisplayRow.Content) {
            rows.append(OnlineTimelineDisplayRow(id: id, index: rows.count, content: content))
        }
        for key in order {
            let group = grouped[key] ?? []
            let groupElements = group.compactMap { slot -> OnlineTimelineElement? in
                if case .element(let element) = slot { return element }
                return nil
            }
            add("m-" + key, .header(key: key, title: monthTitle(key), subtitle: subtitle(groupElements)))
            var pending: [OnlineTimelineElement] = []
            func flush() {
                for row in justify(pending, width: max(width, 200), target: target) { add(row.id, .cells(row)) }
                pending = []
            }
            for slot in group {
                switch slot {
                case .element(let element): pending.append(element)
                case .event(let event): flush(); add("e-" + event.id, .event(event))
                }
            }
            flush()
        }
        return OnlineTimelineLayout(rows: rows, elementCount: elements.count)
    }

    /// "照片 12 · 视频 2 · 家人记录 3 · 曼海宁"
    static func subtitle(_ group: [OnlineTimelineElement]) -> String {
        var photos = 0, videos = 0, family = 0
        var places: [String] = []
        for element in group {
            guard let item = element.onlineItem else { family += 1; continue }
            if item.isVideo { videos += 1 } else { photos += 1 }
            // "深圳市 · 潜龙 · 曼海宁" → "曼海宁": the month header stays one line.
            if places.count < 2, let place = item.place?.components(separatedBy: " · ").last?.trimmingCharacters(in: .whitespaces),
               !place.isEmpty, !places.contains(place) { places.append(place) }
        }
        var parts: [String] = []
        if photos > 0 { parts.append("照片 \(photos)") }
        if videos > 0 { parts.append("视频 \(videos)") }
        if family > 0 { parts.append("家人记录 \(family)") }
        if !places.isEmpty { parts.append(places.joined(separator: "、")) }
        return parts.joined(separator: " · ")
    }

    /// Justified rows (flickr/justified-layout idea): equal height per row, widths follow the photo's shape.
    /// Row ids come from their first element, so rows above a newly loaded page keep their identity.
    static func justify(_ elements: [OnlineTimelineElement], width: CGFloat, target: CGFloat) -> [OnlineTimelineRow] {
        var rows: [OnlineTimelineRow] = []
        var pending: [OnlineTimelineElement] = []
        var aspectSum = 0.0
        func flush(last: Bool) {
            guard !pending.isEmpty else { return }
            let usable = width - spacing * CGFloat(pending.count - 1)
            var height = usable / CGFloat(aspectSum)
            if last { height = min(height, target * 1.15) }
            let cells = pending.map { ($0, CGFloat($0.aspect) * height) }
            rows.append(OnlineTimelineRow(id: "r-" + pending[0].id, cells: cells, height: height))
            pending = []; aspectSum = 0
        }
        for element in elements {
            pending.append(element)
            aspectSum += element.aspect
            let height = (width - spacing * CGFloat(pending.count - 1)) / CGFloat(aspectSum)
            if height <= target { flush(last: false) }
        }
        flush(last: true)
        return rows
    }

    static func monthTitle(_ key: String) -> String {
        let parts = key.split(separator: "-")
        return parts.count == 2 ? "\(parts[0])年\(Int(parts[1]) ?? 0)月" : "未知日期"
    }
}
