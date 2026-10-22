import Foundation
import ImageIO
import UIKit
import WidgetKit
import os

// MARK: - 今日精选（小组件 / 手表共用）
/// 主 App 拉服务端 `online-timeline/highlights`，把 ≤6 张缩略图（JPEG，最长边 600）和
/// `picks.json` 写进 App Group `DailyPicks/`，再刷新小组件、推给手表。
/// 契约见 docs/upgrade-2.25-contracts.md §8。失败一律保留旧精选，不清空。
@MainActor
final class DailyPicksStore {
    static let shared = DailyPicksStore()

    nonisolated static let maxPicks = 6
    nonisolated static let maxPixel: CGFloat = 600
    private static let throttle: TimeInterval = 30 * 60
    private static let lastRefreshKey = "bubu.dailyPicks.lastRefreshAt"
    private static let lastDayKey = "bubu.dailyPicks.day"

    private let log = Logger(subsystem: "com.bubu.timemachine", category: "DailyPicks")
    private var running: Task<Void, Never>?

    /// 唯一入口：打开时光 / 回到前台时调用。未配置家庭服务时什么都不做。
    func refreshIfNeeded(env: AppEnvironment, force: Bool = false) {
        guard let client = BubuLearningClient(env: env) else {
            // Family service disconnected: second-brain photos must leave the widgets and Watch too.
            if let directory = Self.directory,
               let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path), !files.isEmpty {
                try? FileManager.default.removeItem(at: directory)
                WidgetCenter.shared.reloadAllTimelines()
                WatchConnectivityManager.shared.pushDailyPicks()
            }
            return
        }
        guard running == nil else { return }
        let today = BubuLearningDates.dayString(.now)
        let defaults = UserDefaults.standard
        if !force, defaults.string(forKey: Self.lastDayKey) == today,
           let last = defaults.object(forKey: Self.lastRefreshKey) as? Date,
           Date.now.timeIntervalSince(last) < Self.throttle {
            return
        }
        running = Task { [weak self] in
            await self?.refresh(client: client, day: today)
            self?.running = nil
        }
    }

    func refresh(client: BubuLearningClient) async {
        await refresh(client: client, day: BubuLearningDates.dayString(.now))
    }

    private func refresh(client: BubuLearningClient, day: String) async {
        do {
            let count = try await Self.fetchAndWrite(client: client, day: day)
            UserDefaults.standard.set(Date.now, forKey: Self.lastRefreshKey)
            UserDefaults.standard.set(day, forKey: Self.lastDayKey)
            WidgetCenter.shared.reloadAllTimelines()
            WatchConnectivityManager.shared.pushDailyPicks()
            log.notice("daily picks refreshed: \(count)")
        } catch {
            log.error("daily picks refresh failed: \(error.localizedDescription)")
        }
    }

    /// 已写好的精选所属日期（手表据此判断「新的一天的精选到了」）。
    static var currentDay: String? { UserDefaults.standard.string(forKey: lastDayKey) }

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
        var picks: [DailyPick] = []
        var seen = Set<String>()
        for item in response.items {
            guard picks.count < maxPicks else { break }
            let file = fileName(for: item.id)
            guard seen.insert(file).inserted else { continue }
            var jpeg: Data?
            for path in [item.largeUrl, item.previewUrl].compactMap({ $0 }).filter({ !$0.isEmpty }) {
                guard !Task.isCancelled else { return picks.count }
                if let data = try? await client.mediaData(path), let small = downscaledJPEG(data) {
                    jpeg = small
                    break
                }
            }
            guard let jpeg else { continue }
            try jpeg.write(to: dir.appendingPathComponent(file), options: .atomic)
            let reason = response.reasonById?[item.id]
            picks.append(DailyPick(id: item.id, file: file, capturedAt: item.capturedAt,
                                   reason: reason, description: item.description))
        }
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

    nonisolated static func load() -> [DailyPick] {
        guard let dir = directory,
              let data = try? Data(contentsOf: dir.appendingPathComponent(manifestName)) else { return [] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode([DailyPick].self, from: data)) ?? []
    }

    /// 只读精选目录里的 `pick-*.jpg`（已经是 ≤600px JPEG，直接发给手表）。
    nonisolated static func photoData(named name: String) -> Data? {
        guard name.hasPrefix(filePrefix), name == (name as NSString).lastPathComponent,
              let dir = directory else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(name))
    }

    /// 手表卡片：日期在手机侧格式化好，手表不做本地化计算。
    nonisolated static func watchCards() -> [WatchMemory] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy年M月d日"
        return load().map { pick in
            let note = (pick.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return WatchMemory(id: "pick-" + pick.id,
                               dateText: pick.capturedAt.flatMap(BubuLearningDates.parseISO)
                                   .map(formatter.string(from:)) ?? "",
                               note: note.count <= 24 ? note : String(note.prefix(23)) + "…",
                               ageText: "", isOnThisDay: pick.reason == "那年今天",
                               photoFileName: pick.file, reason: pick.reason)
        }
    }
}

/// `picks.json` 的一条（snake_case 落盘）。
nonisolated struct DailyPick: Codable, Sendable, Hashable {
    let id: String
    let file: String
    let capturedAt: String?
    let reason: String?
    let description: String?
}
