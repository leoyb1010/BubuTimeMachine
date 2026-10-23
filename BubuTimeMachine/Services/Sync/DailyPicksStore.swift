import Foundation
import ImageIO
import UIKit
import os

// MARK: - 今日精选（小组件 / 手表共用）
/// 主 App 拉服务端 `online-timeline/highlights`，把 ≤6 张缩略图（JPEG，最长边 600）和
/// `picks.json` 写进 App Group `DailyPicks/`，再刷新小组件、推给手表。
/// 契约见 docs/upgrade-2.25-contracts.md §8。刷新失败保留旧精选；每条精选带上海日期：
/// 当天原样展示，过了零点、新精选还没到时昨天那批改标「昨日精选」继续挂着，再往前就过期
///（规则见 WatchShared `DailyPicksDay`，手表与表盘同一份）。
/// 只在用户同意第二大脑说明之后才拉取，每天最多成功刷新一次；前台和后台刷新（BGAppRefresh）都会触发。
@MainActor
final class DailyPicksStore {
    static let shared = DailyPicksStore()

    nonisolated static let maxPicks = 6
    nonisolated static let maxPixel: CGFloat = 600
    /// 与 SecondBrainConsent 的 @AppStorage 同一个键。
    nonisolated static let consentKey = SecondBrainConsentModifier.storageKey
    private static let lastRefreshKey = "bubu.dailyPicks.lastRefreshAt"
    // v2：2.26 起清单带日期；换键让升级当天也会重新拉一次。
    private static let lastDayKey = "bubu.dailyPicks.day.v2"

    private let log = Logger(subsystem: "com.bubu.timemachine", category: "DailyPicks")
    private var running: Task<Void, Never>?

    /// 唯一入口：打开时光 / 回到前台时调用。未配置家庭服务或未同意第二大脑说明时什么都不做。
    func refreshIfNeeded(env: AppEnvironment, force: Bool = false) {
        guard let client = BubuLearningClient(env: env) else {
            // Family service disconnected: second-brain photos must leave the widgets and Watch too.
            if let directory = Self.directory,
               let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path), !files.isEmpty {
                try? FileManager.default.removeItem(at: directory)
                WidgetRefresher.reload()
                WatchConnectivityManager.shared.pushDailyPicks()
            }
            return
        }
        let defaults = UserDefaults.standard
        guard running == nil, defaults.bool(forKey: Self.consentKey) else { return }
        let today = BubuLearningDates.dayString(.now)
        // 今天已经成功刷新过就不再下载；跨天（上海时间）后第一次回到前台再拉。
        if !force, defaults.string(forKey: Self.lastDayKey) == today { return }
        running = Task { [weak self] in
            await self?.refresh(client: client, day: today)
            self?.running = nil
        }
    }

    /// 后台刷新（BGAppRefresh）入口：不依赖 AppEnvironment，凭本机 ServerConfig 构造一次性客户端。
    /// 规则与前台一致：未同意说明 / 未配置服务 / 今天已刷新过都直接返回；前台那一轮还在跑就等它。
    func refreshInBackground(config: ServerConfig = ServerConfig()) async {
        if let running {
            await running.value
            return
        }
        let defaults = UserDefaults.standard
        let today = BubuLearningDates.dayString(.now)
        guard defaults.bool(forKey: Self.consentKey), defaults.string(forKey: Self.lastDayKey) != today,
              let client = Self.backgroundClient(config: config) else { return }
        let task = Task { [weak self] in
            await self?.refresh(client: client, day: today)
            self?.running = nil
        }
        running = task
        await task.value
    }

    private static func backgroundClient(config: ServerConfig) -> BubuLearningClient? {
        guard let access = LearningServiceAccess(trustedServiceURL: config.aiBaseURL, serverURL: config.baseURL,
                                                 accountEmail: config.accountEmail, revision: 0,
                                                 serverConfigured: config.isConfigured, aiEnabled: config.aiEnabled,
                                                 requiresAIEnabled: false),
              let serverURL = config.baseURL else { return nil }
        let api = PocketBaseClient(baseURL: serverURL, identity: config.accountEmail,
                                   password: config.accountPassword, lanBaseURL: config.lanBaseURL)
        return BubuLearningClient(baseURL: access.baseURL, scope: access.account + "\n" + access.baseURL.absoluteString,
                                  token: { try await api.authenticate(role: "ai").token })
    }

    func refresh(client: BubuLearningClient) async {
        await refresh(client: client, day: BubuLearningDates.dayString(.now))
    }

    private func refresh(client: BubuLearningClient, day: String) async {
        do {
            let count = try await Self.fetchAndWrite(client: client, day: day)
            UserDefaults.standard.set(Date.now, forKey: Self.lastRefreshKey)
            UserDefaults.standard.set(day, forKey: Self.lastDayKey)
            WidgetRefresher.reload()
            WatchConnectivityManager.shared.pushDailyPicks()
            log.notice("daily picks refreshed: \(count)")
        } catch {
            log.error("daily picks refresh failed: \(error.localizedDescription)")
        }
    }


    // MARK: 网络 + 落盘（离开主线程）

    private nonisolated struct HighlightItem: Decodable, Sendable {
        let id: String
        let kind: String?
        let capturedAt: String?
        let description: String?
        let previewUrl: String?
        let largeUrl: String?
    }

    private nonisolated struct HighlightsResponse: Decodable, Sendable {
        let items: [HighlightItem]
        let reasonById: [String: String]?
    }

    @concurrent
    private nonisolated static func fetchAndWrite(client: BubuLearningClient, day: String) async throws -> Int {
        let response = try await client.get("api/online-timeline/highlights",
                                            query: [URLQueryItem(name: "date", value: day)],
                                            as: HighlightsResponse.self)
        guard let dir = directory else { throw CocoaError(.fileNoSuchFile) }
        // 去重后按服务端顺序取候选（多留几张给失败兜底），4 路并发下载，再按原顺序取前 6 张成功的。
        var seen = Set<String>()
        let candidates = Array(response.items.filter { seen.insert(fileName(for: $0.id)).inserted }
            .prefix(maxPicks + 4))
        let downloaded = await withTaskGroup(of: (Int, Data?).self) { group -> [Int: Data] in
            var results = [Int: Data]()
            var next = 0
            func enqueue() {
                guard next < candidates.count else { return }
                let index = next, item = candidates[index]
                next += 1
                group.addTask { (index, await previewJPEG(for: item, client: client)) }
            }
            for _ in 0..<4 { enqueue() }
            while let (index, data) = await group.next() {
                if let data { results[index] = data }
                if !Task.isCancelled { enqueue() }
            }
            return results
        }
        var picks: [DailyPick] = []
        for (index, item) in candidates.enumerated() where picks.count < maxPicks {
            guard let jpeg = downloaded[index] else { continue }
            let file = fileName(for: item.id)
            try jpeg.write(to: dir.appendingPathComponent(file), options: .atomic)
            picks.append(DailyPick(id: item.id, file: file, capturedAt: item.capturedAt,
                                   reason: response.reasonById?[item.id], description: item.description, day: day))
        }
        if Task.isCancelled && picks.isEmpty { throw CancellationError() }
        // 服务端成功返回但一张都没下到（全部失败）时保留旧精选；服务端明确返回空则清空。
        if picks.isEmpty && !response.items.isEmpty { throw URLError(.cannotDecodeContentData) }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        try encoder.encode(picks).write(to: dir.appendingPathComponent(manifestName), options: .atomic)
        let keep = Set(picks.map(\.file) + [manifestName])
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where !keep.contains(name) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        return picks.count
    }

    /// 预览图（服务端 thumb，约 480px）已经够 600px 的小组件用；大图只做兜底。
    private nonisolated static func previewJPEG(for item: HighlightItem, client: BubuLearningClient) async -> Data? {
        for path in [item.previewUrl, item.largeUrl].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            guard !Task.isCancelled else { return nil }
            if let data = try? await client.mediaData(path, background: true), let small = downscaledJPEG(data) { return small }
        }
        return nil
    }

    nonisolated static func downscaledJPEG(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
    }

    // MARK: 共享目录（App / Widget 同读）

    nonisolated static let manifestName = "picks.json"
    nonisolated static let filePrefix = "pick-"

    nonisolated static var directory: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: BubuStorage.appGroupID) else { return nil }
        let dir = container.appendingPathComponent("DailyPicks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 文件名只保留安全字符；手表缓存与小组件都按它取图。
    nonisolated static func fileName(for id: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let safe = String(id.filter { allowed.contains($0) }.prefix(80))
        return filePrefix + (safe.isEmpty ? WatchPhotoBundle.fingerprint([id]) : safe) + ".jpg"
    }

    /// 还能展示的精选（未过期的原始清单）与其所属日期。读不到或已过期时为空。
    nonisolated static func manifest(now: Date = .now) -> (day: String?, picks: [DailyPick]) {
        guard let dir = directory,
              let data = try? Data(contentsOf: dir.appendingPathComponent(manifestName)) else { return (nil, []) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let picks = (try? decoder.decode([DailyPick].self, from: data)) ?? []
        let day = picks.first?.day
        return DailyPicksDay.freshness(of: day, now: now) == .expired ? (nil, []) : (day, picks)
    }

    /// 可展示的精选：当天原样；昨天的改标「昨日精选」（新精选到达前不消失）；更早的为空。
    nonisolated static func load(now: Date = .now) -> [DailyPick] {
        let (day, picks) = manifest(now: now)
        guard DailyPicksDay.freshness(of: day, now: now) == .yesterday else { return picks }
        return picks.map { pick in
            var pick = pick
            pick.reason = DailyPicksDay.yesterdayReason
            return pick
        }
    }

    /// 是否需要换新：只有当天（上海时间）写的清单才算新鲜。没有日期的旧清单一律视为过期。
    /// 小组件 `DailyPicksReader` 用同样的日期规则（小组件不编译本文件）。
    nonisolated static func isStale(pickDay: String?, now: Date) -> Bool {
        DailyPicksDay.freshness(of: pickDay, now: now) != .today
    }

    /// 只读精选目录里的 `pick-*.jpg`（已经是 ≤600px JPEG，直接发给手表）。
    nonisolated static func photoData(named name: String) -> Data? {
        guard name.hasPrefix(filePrefix), name == (name as NSString).lastPathComponent,
              let dir = directory else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(name))
    }

    /// 手表卡片 + 所属日期：日期在手机侧格式化好；标签保持原样，由手表按 `dailyPicksDay`
    /// 和它自己的时钟改标（手机推送之后才跨零点也能及时改）。
    nonisolated static func watchCards(now: Date = .now) -> (cards: [WatchMemory], day: String?) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy年M月d日"
        let (day, picks) = manifest(now: now)
        let cards = picks.map { pick in
            let note = (pick.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return WatchMemory(id: "pick-" + pick.id,
                               dateText: pick.capturedAt.flatMap(BubuLearningDates.parseISO)
                                   .map(formatter.string(from:)) ?? "",
                               note: note.count <= 24 ? note : String(note.prefix(23)) + "…",
                               ageText: "", isOnThisDay: pick.reason == DailyPicksDay.onThisDayReason,
                               photoFileName: pick.file, reason: pick.reason)
        }
        return (cards, day)
    }
}

/// `picks.json` 的一条（snake_case 落盘）。
nonisolated struct DailyPick: Codable, Sendable, Hashable {
    let id: String
    let file: String
    let capturedAt: String?
    var reason: String?
    let description: String?
    /// 精选所属的上海日期（yyyy-MM-dd）；2.26 之前写的清单没有。
    var day: String? = nil
}
