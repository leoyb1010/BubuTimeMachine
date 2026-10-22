import Foundation

/// Reading state is local and keyed by identity, never written back as a record.
public nonisolated struct WatchBrowseSelection: Sendable {
    public private(set) var selectedID: String?

    public init(selectedID: String? = nil) { self.selectedID = selectedID }

    public func index(in memories: [WatchMemory]) -> Int {
        memories.firstIndex(where: { $0.id == selectedID }) ?? 0
    }

    public mutating func reconcile(with memories: [WatchMemory]) {
        if !memories.contains(where: { $0.id == selectedID }) { selectedID = memories.first?.id }
    }

    public mutating func select(crownValue: Double, in memories: [WatchMemory]) {
        guard crownValue.isFinite else { return }
        guard !memories.isEmpty else { selectedID = nil; return }
        let bounded = min(max(crownValue.rounded(), 0), Double(memories.count - 1))
        selectedID = memories[Int(bounded)].id
    }

    public mutating func step(_ delta: Int, in memories: [WatchMemory]) {
        guard !memories.isEmpty else { selectedID = nil; return }
        let (next, overflow) = index(in: memories).addingReportingOverflow(delta)
        let bounded = overflow ? (delta > 0 ? memories.count - 1 : 0) : min(max(next, 0), memories.count - 1)
        selectedID = memories[bounded].id
    }
}

/// 今日精选的「所属日」规则（上海时间），手机 DailyPicksStore、手表、表盘共用一份。
/// iOS 小组件 `DailyPicksReader` 不编译本文件，按同一规则单独实现（两处改动必须同步）。
///
/// 精选当天原样展示；过了零点、新精选还没到时，昨天那批继续挂着但改标「昨日精选」
///（「那年今天」不能挂到别的日子上）；再往前一天就过期，回落到家人照片。
public nonisolated enum DailyPicksDay {
    public enum Freshness: Sendable, Equatable { case today, yesterday, expired }

    public static let onThisDayReason = "那年今天"
    public static let yesterdayReason = "昨日精选"

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    public static func string(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func freshness(of pickDay: String?, now: Date = .now) -> Freshness {
        guard let pickDay else { return .expired }
        if pickDay == string(now) { return .today }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return .expired }
        return pickDay == string(yesterday) ? .yesterday : .expired
    }

    /// 下一个上海零点：时间线在这里截断，零点后重建以改标签/换批。
    public static func nextMidnight(after date: Date) -> Date {
        calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0, second: 0),
                          matchingPolicy: .nextTime) ?? date.addingTimeInterval(3600)
    }

    public static func relabeled(_ card: WatchMemory, _ freshness: Freshness) -> WatchMemory {
        guard freshness == .yesterday else { return card }
        var card = card
        card.reason = yesterdayReason
        card.isOnThisDay = false
        return card
    }
}

/// Only the explicit photo deck is eligible. Legacy health/text feeds stay off screen.
public nonisolated enum WatchReadModel {
    /// 手表一屏最多翻几张（家人照片 + 精选合计）。
    public static let deckLimit = 8
    /// 合并时排在最前的家人近期照片张数。
    public static let leadingFamilyCount = 3

    public static func memories(from snapshot: WatchSnapshot?) -> [WatchMemory] {
        sanitized(snapshot?.photoCards, limit: 5)
    }

    /// 服务端精选（≤6）：当天原样；昨天的改标「昨日精选」；更早的不再展示。
    public static func dailyPicks(from snapshot: WatchSnapshot?, now: Date = .now) -> [WatchMemory] {
        let freshness = DailyPicksDay.freshness(of: snapshot?.dailyPicksDay, now: now)
        guard freshness != .expired else { return [] }
        return sanitized(snapshot?.dailyPicks, limit: 6).map { DailyPicksDay.relabeled($0, freshness) }
    }

    /// 手表与表盘实际展示的一组：先放家人近期照片（≤3），再接精选，余下的家人照片补在后面；
    /// 按 id 和文件名去重，总数 ≤ deckLimit。家人记录与精选并存，不再互相挤掉。
    public static func deck(from snapshot: WatchSnapshot?, now: Date = .now) -> [WatchMemory] {
        let family = memories(from: snapshot)
        let picks = dailyPicks(from: snapshot, now: now)
        let ordered = Array(family.prefix(leadingFamilyCount)) + picks + Array(family.dropFirst(leadingFamilyCount))
        return sanitized(ordered, limit: deckLimit)
    }

    /// 手表缓存里应该有的全部照片名（缺图补发 / LRU 保留都按它）。
    public static func photoNames(from snapshot: WatchSnapshot?, now: Date = .now) -> [String] {
        deck(from: snapshot, now: now).compactMap(\.photoFileName)
    }

    private static func sanitized(_ cards: [WatchMemory]?, limit: Int) -> [WatchMemory] {
        var ids = Set<String>(), names = Set<String>()
        return Array((cards ?? []).filter {
            guard let name = $0.photoFileName, !name.isEmpty,
                  name == (name as NSString).lastPathComponent,
                  name != ".", name != "..", !name.contains("\\"),
                  !ids.contains($0.id), !names.contains(name) else { return false }
            ids.insert($0.id); names.insert(name)
            return true
        }.prefix(limit))
    }
}
