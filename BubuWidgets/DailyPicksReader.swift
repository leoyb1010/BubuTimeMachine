import Foundation

// MARK: - 今日精选（只读）
/// 主 App 的 DailyPicksStore 写入 App Group `DailyPicks/`：`picks.json` + `pick-*.jpg`（≤600px）。
/// 小组件优先展示它，读不到/为空/过期时回退本机照片。契约见 docs/upgrade-2.25-contracts.md §8。
nonisolated struct WidgetDailyPick: Decodable, Sendable, Hashable {
    let id: String
    let file: String
    let capturedAt: String?
    var reason: String?
    let description: String?
    /// 精选所属的上海日期（yyyy-MM-dd）；旧清单没有。
    let day: String?

    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private static let dateTextFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    var capturedDate: Date? {
        guard let capturedAt else { return nil }
        return Self.isoFractional.date(from: capturedAt) ?? Self.isoPlain.date(from: capturedAt)
    }

    var dateText: String? { capturedDate.map(Self.dateTextFormatter.string(from:)) }

    /// 深链由 RootTabView 处理：打开在线时光详情。
    var url: URL? {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return id.addingPercentEncoding(withAllowedCharacters: allowed).flatMap { URL(string: "bubu://online/\($0)") }
    }

    var isOnThisDay: Bool { reason == "那年今天" }

    var caption: String? {
        guard let text = description?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text.count <= 24 ? text : String(text.prefix(23)) + "…"
    }
}

nonisolated enum DailyPicksReader {
    static let yesterdayReason = "昨日精选"

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    private static func dayString(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 与 WatchShared `DailyPicksDay.freshness` 同一规则（小组件不编译那个文件，改动必须两边同步）：
    /// 当天原样；昨天的继续展示但改标「昨日精选」（新精选到达前不消失）；更早或没有日期的视为过期。
    enum Freshness { case today, yesterday, expired }

    static func freshness(pickDay: String?, now: Date = .now) -> Freshness {
        guard let pickDay else { return .expired }
        if pickDay == dayString(now) { return .today }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return .expired }
        return pickDay == dayString(yesterday) ? .yesterday : .expired
    }

    /// 下一个上海零点：精选时间线在这里截断，零点后重建以改标签或回落到本机照片。
    static func nextMidnight(after date: Date = .now) -> Date {
        calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0, second: 0),
                          matchingPolicy: .nextTime) ?? date.addingTimeInterval(3600)
    }

    private static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.bubu.timemachine")?
            .appendingPathComponent("DailyPicks", isDirectory: true)
    }

    /// 有图的精选（≤6）。任何异常或过期都返回空，调用方走原来的本机照片。
    static func load(now: Date = .now) -> [(pick: WidgetDailyPick, data: Data)] {
        guard let dir = directory else { return [] }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("picks.json")) else { return [] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let picks = try? decoder.decode([WidgetDailyPick].self, from: data) else { return [] }
        let state = freshness(pickDay: picks.first?.day, now: now)
        guard state != .expired else { return [] }
        return picks.prefix(6).compactMap { pick in
            let name = (pick.file as NSString).lastPathComponent
            guard name == pick.file, name.hasPrefix("pick-"),
                  let bytes = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
            var pick = pick
            if state == .yesterday { pick.reason = yesterdayReason }
            return (pick, bytes)
        }
    }
}
