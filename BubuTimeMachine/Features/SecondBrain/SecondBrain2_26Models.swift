import Foundation

// MARK: - DTOs（docs/upgrade-2.26-contracts.md）

// 布布问答
nonisolated struct AskRequestBody: Encodable, Sendable { let question: String }
nonisolated struct AskCitationDTO: Decodable, Sendable, Hashable { let id: String; let note: String? }
nonisolated struct AskResponseDTO: Decodable, Sendable, Hashable {
    let answer: String?
    let citations: [AskCitationDTO]
    let items: [OnlineTimelineItem]
    let semantic: Bool?
    let modelUsed: Bool
}

// 语言成长线
nonisolated struct WordsMonthDTO: Decodable, Sendable, Hashable, Identifiable {
    let month: String
    let newWords: [String]
    let total: Int
    var id: String { month }
    var date: Date? { SecondBrainMonths.date(month) }
}
nonisolated struct WordFirstDTO: Decodable, Sendable, Hashable, Identifiable {
    let word: String
    let itemId: String?
    let voiceId: String?
    let capturedAt: String?
    let text: String?
    var id: String { word + "|" + (itemId ?? "") }
    var date: Date? {
        guard let capturedAt, !capturedAt.isEmpty else { return nil }
        return BubuLearningDates.parseISO(capturedAt) ?? BubuLearningDates.day(String(capturedAt.prefix(10)))
    }
}
nonisolated struct WordsResponseDTO: Decodable, Sendable {
    let months: [WordsMonthDTO]
    let firsts: [WordFirstDTO]
    let sourceCount: Int?
    let pending: Int?
}

// 去过的地方
nonisolated struct PlaceDTO: Decodable, Sendable, Hashable, Identifiable {
    let name: String
    let short: String
    let city: String?
    let count: Int
    let coverUrl: String?
    let itemIds: [String]
    let firstDay: String?
    let lastDay: String?
    var id: String { name }
    var displayName: String { short.isEmpty ? name : short }
}
nonisolated struct PlaceListDTO: Decodable, Sendable { let items: [PlaceDTO] }

// 认一认 批量 / 历史
nonisolated struct RecognitionBatchBody: Encodable, Sendable {
    struct Entry: Encodable, Sendable { let id: String; let decision: String }
    let decisions: [Entry]
}
nonisolated struct RecognitionBatchResult: Decodable, Sendable { let applied: Int }
nonisolated struct RecognitionHistoryDTO: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let decision: String
    let decidedAt: String?
    let previewUrl: String?
}
nonisolated struct RecognitionHistoryList: Decodable, Sendable { let items: [RecognitionHistoryDTO] }

// 家人互动（2.27）
nonisolated struct TimelineCommentDTO: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let author: String
    let text: String
    let createdAt: String?
    let mine: Bool?
    var isMine: Bool { mine == true }
}
nonisolated struct TimelineSocialDTO: Decodable, Sendable, Hashable {
    var comments: [TimelineCommentDTO]
    var hearts: Int
    var hearted: Bool
}
nonisolated struct TimelineHeartDTO: Decodable, Sendable { let hearts: Int; let hearted: Bool }
nonisolated struct TimelineCommentBody: Encodable, Sendable { let text: String }
nonisolated struct TimelineHeartBody: Encodable, Sendable { let on: Bool }

/// Empty-object replies (`{}`) for writes whose body we don't need.
nonisolated struct SecondBrainAck: Decodable, Sendable {}

// MARK: - Months

nonisolated enum SecondBrainMonths {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    /// "2026-03" → first day of that month (Shanghai).
    static func date(_ month: String) -> Date? { BubuLearningDates.day(String(month.prefix(7)) + "-01") }

    /// "2025-07" → "2025 年 7 月"
    static func caption(_ month: String) -> String {
        let parts = month.prefix(7).split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let value = Int(parts[1]) else { return month }
        return "\(year) 年 \(value) 月"
    }

    /// The `count` months ending with the month containing `now`, oldest first ("yyyy-MM").
    static func trailing(_ count: Int, endingAt now: Date) -> [String] {
        let calendar = calendar
        return (0..<count).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .month, value: -back, to: now) else { return nil }
            let parts = calendar.dateComponents([.year, .month], from: date)
            guard let year = parts.year, let month = parts.month else { return nil }
            return String(format: "%04d-%02d", year, month)
        }
    }
}

// MARK: - 布布问答：答案里的引用标记

nonisolated enum AskAnswerPart: Sendable, Hashable {
    case text(String)
    /// `number` is the 1-based marker shown to the reader.
    case cite(number: Int, id: String)
}

/// The answer may mark sources as `[1]` / `[^1]` / `【1】` (1-based index into `citations`)
/// or `[<24hex id>]`. Markers that don't resolve to a returned item stay as plain text.
nonisolated enum AskCitationParser {
    static func parse(_ answer: String, citations: [AskCitationDTO], itemIDs: Set<String>) -> [AskAnswerPart] {
        guard let regex = try? Regex(#"\[\^?(\d{1,2})\]|【(\d{1,2})】|\[([0-9a-fA-F]{24})\]"#) else { return [.text(answer)] }
        var parts: [AskAnswerPart] = []
        var cursor = answer.startIndex
        func appendText(_ text: Substring) {
            guard !text.isEmpty else { return }
            if case .text(let previous)? = parts.last {
                parts[parts.count - 1] = .text(previous + text)
            } else {
                parts.append(.text(String(text)))
            }
        }
        for match in answer.matches(of: regex) {
            appendText(answer[cursor..<match.range.lowerBound])
            cursor = match.range.upperBound
            let number = (match.output[1].substring ?? match.output[2].substring).flatMap { Int($0) }
            if let number, citations.indices.contains(number - 1), itemIDs.contains(citations[number - 1].id) {
                parts.append(.cite(number: number, id: citations[number - 1].id))
            } else if let hex = match.output[3].substring.map({ String($0).lowercased() }), itemIDs.contains(hex) {
                let index = citations.firstIndex { $0.id.lowercased() == hex }
                parts.append(.cite(number: (index ?? citations.count) + 1, id: hex))
            } else {
                appendText(answer[match.range])
            }
        }
        appendText(answer[cursor...])
        return parts
    }

    static func hasCitations(_ parts: [AskAnswerPart]) -> Bool {
        parts.contains { if case .cite = $0 { true } else { false } }
    }
}

// MARK: - 生日影片：每月挑最好的瞬间

nonisolated struct FilmMomentPlan: Sendable, Hashable, Identifiable {
    let itemId: String
    let month: String
    let caption: String
    var id: String { itemId }
}

nonisolated enum BirthdayFilmPlanner {
    /// Per month: confirmed “第一次” photos first, then the monthly report highlights.
    /// At most `perMonth` per month, no repeats, months oldest → newest.
    static func select(months: [String], reports: [MonthlyReportDTO], firsts: [GrowthFirstDTO],
                       perMonth: Int = 2) -> [FilmMomentPlan] {
        var used: Set<String> = []
        var plans: [FilmMomentPlan] = []
        let reportByMonth = Dictionary(reports.map { ($0.month.prefix(7).description, $0) }, uniquingKeysWith: { first, _ in first })
        let confirmed = firsts.filter { $0.status == "confirmed" && $0.itemId?.isEmpty == false }
        for month in months.sorted() {
            let caption = SecondBrainMonths.caption(month)
            var picked: [FilmMomentPlan] = []
            let monthFirsts = confirmed
                .filter { ($0.date ?? "").hasPrefix(month) }
                .sorted { ($0.date ?? "") < ($1.date ?? "") }
            for first in monthFirsts where picked.count < perMonth {
                guard let id = first.itemId, !used.contains(id) else { continue }
                used.insert(id)
                picked.append(FilmMomentPlan(itemId: id, month: month, caption: caption + " · " + firstTitle(first.displayTitle)))
            }
            if let report = reportByMonth[month] {
                for id in report.highlightIds where picked.count < perMonth && !used.contains(id) {
                    used.insert(id)
                    let title = report.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let text = picked.isEmpty && !title.isEmpty ? caption + " · " + title : caption
                    picked.append(FilmMomentPlan(itemId: id, month: month, caption: text))
                }
            }
            plans += picked
        }
        return plans
    }

    static func firstTitle(_ title: String) -> String {
        title.hasPrefix("第一次") ? title : "第一次" + title
    }

    /// Seconds each photo stays on screen so the film lands in roughly 60–90 s.
    static func photoSeconds(count: Int) -> Double {
        guard count > 0 else { return 2.5 }
        return min(max(66 / Double(count), 2.5), 4.0)
    }
}

// MARK: - 地点地理编码缓存（Application Support 里的小 JSON）

nonisolated struct PlaceGeocodeCache: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        let latitude: Double?
        let longitude: Double?
        static let notFound = Entry(latitude: nil, longitude: nil)
        var found: Bool { latitude != nil && longitude != nil }
    }
    var entries: [String: Entry] = [:]

    static var defaultURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent("BubuPlaces", isDirectory: true).appendingPathComponent("geocode.json")
    }

    static func load(from url: URL?) -> PlaceGeocodeCache {
        guard let url, let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(PlaceGeocodeCache.self, from: data) else { return PlaceGeocodeCache() }
        return cache
    }

    func save(to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// "上海市·世纪公园" reads better to the geocoder as "上海市 世纪公园".
    static func query(for name: String) -> String {
        name.replacingOccurrences(of: "·", with: " ").replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Loading items by id

extension BubuLearningClient {
    /// `api/online-timeline/items?ids=` in chunks of 60, keeping the requested order.
    nonisolated func timelineItems(ids: [String]) async throws -> [OnlineTimelineItem] {
        var found: [String: OnlineTimelineItem] = [:]
        var start = 0
        while start < ids.count {
            let chunk = ids[start..<min(start + 60, ids.count)]
            let page = try await get("api/online-timeline/items",
                                     query: [URLQueryItem(name: "ids", value: chunk.joined(separator: ","))],
                                     as: OnlineTimelineItems.self)
            for item in page.items { found[item.id] = item }
            start += 60
        }
        return ids.compactMap { found[$0] }
    }
}
