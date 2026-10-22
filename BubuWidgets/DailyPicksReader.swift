import Foundation

// MARK: - 今日精选（只读）
/// 主 App 的 DailyPicksStore 写入 App Group `DailyPicks/`：`picks.json` + `pick-*.jpg`（≤600px）。
/// 小组件优先展示它，读不到/为空/过期时回退本机照片。契约见 docs/upgrade-2.25-contracts.md §8。
nonisolated struct WidgetDailyPick: Decodable, Sendable, Hashable {
    let id: String
    let file: String
    let capturedAt: String?
    let reason: String?
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

    var caption: String? {
        guard let text = description?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text.count <= 24 ? text : String(text.prefix(23)) + "…"
    }
}

nonisolated enum DailyPicksReader {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// 精选只属于写入它的那一天（上海时间）：「那年今天」的标签不能挂到别的日子上。
    /// 与主 App `DailyPicksStore.isStale` 规则一致；没有日期的旧清单视为过期。
    static func isStale(pickDay: String?, now: Date = .now) -> Bool {
        guard let pickDay else { return true }
        return pickDay != dayFormatter.string(from: now)
    }

    private static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.bubu.timemachine")?
            .appendingPathComponent("DailyPicks", isDirectory: true)
    }

    /// 有图的精选（≤6）。任何异常都返回空，调用方走原来的本机照片。
    static func load() -> [(pick: WidgetDailyPick, data: Data)] {
        guard let dir = directory else { return [] }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("picks.json")) else { return [] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let picks = try? decoder.decode([WidgetDailyPick].self, from: data),
              !isStale(pickDay: picks.first?.day) else { return [] }
        return picks.prefix(6).compactMap { pick in
            let name = (pick.file as NSString).lastPathComponent
            guard name == pick.file, name.hasPrefix("pick-"),
                  let bytes = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
            return (pick, bytes)
        }
    }
}
