import Foundation
import ImageIO
import UIKit

// MARK: - 首页「今天」的数据：今日精选 + 今天的回忆
/// 两路都来自家里的第二大脑：`online-timeline/highlights`（今日精选大图）和 `api/memories`（回忆轮播）。
/// - 同一天同一账号只取一次，切 Tab 回来不重复请求；下拉刷新才强制重取。
/// - 失败时保留上一次的结果，不把已经显示的卡片清空（避免整块消失、下方内容跳动）。
/// - 精选先用 `DailyPicksStore` 落在 App Group 里的 600px 小图秒开，再换服务端大图。
@Observable
@MainActor
final class HomeTodayModel {
    enum Phase: Equatable { case unavailable, loading, ready }

    private(set) var phase: Phase = .unavailable
    private(set) var memories: [MemoryCardDTO] = []
    private(set) var picks: [HomeTodayPick] = []

    private struct Snapshot {
        var memories: [MemoryCardDTO]?
        var picks: [HomeTodayPick]?
    }
    /// 进程内缓存，键为「账号 scope | 上海日期」。首页视图重建（换主题、回到前台）不丢。
    private static var cache: [String: Snapshot] = [:]

    var isLoading: Bool { phase == .loading }

    func load(client: BubuLearningClient?, consented: Bool, force: Bool = false) async {
        guard let client else {
            phase = .unavailable
            memories = []
            picks = []
            return
        }
        let day = BubuLearningDates.dayString(.now)
        let key = client.scope + "|" + day
        if let snapshot = Self.cache[key] {
            apply(snapshot)
            if !force, snapshot.memories != nil, snapshot.picks != nil || !consented {
                phase = .ready
                return
            }
        } else {
            // 换账号 / 跨天：旧的不属于今天。
            memories = []
            picks = consented ? Self.localPicks() : []
        }
        if memories.isEmpty { phase = .loading }

        async let memoriesResult = Self.fetchMemories(client: client, day: day)
        async let picksResult: [HomeTodayPick]? = consented
            ? Self.fetchPicks(client: client, day: day) : nil
        let (fetchedMemories, fetchedPicks) = await (memoriesResult, picksResult)
        guard !Task.isCancelled else { return }

        var snapshot = Self.cache[key] ?? Snapshot()
        if let fetchedMemories { snapshot.memories = fetchedMemories }
        if let fetchedPicks { snapshot.picks = fetchedPicks }
        if snapshot.memories != nil || snapshot.picks != nil { Self.cache[key] = snapshot }
        apply(snapshot)
        phase = .ready
    }

    private func apply(_ snapshot: Snapshot) {
        if let value = snapshot.memories { memories = value }
        if let value = snapshot.picks { picks = value }
    }

    // MARK: 网络（离开主线程）

    @concurrent
    nonisolated private static func fetchMemories(client: BubuLearningClient, day: String) async -> [MemoryCardDTO]? {
        try? await client.get("api/memories", query: [URLQueryItem(name: "date", value: day)],
                              as: MemoryCardList.self).items
    }

    /// nil = 请求失败（保留旧值）；空数组 = 今天确实没有精选。
    @concurrent
    nonisolated private static func fetchPicks(client: BubuLearningClient, day: String) async -> [HomeTodayPick]? {
        guard let response = try? await client.get(
            "api/online-timeline/highlights", query: [URLQueryItem(name: "date", value: day)],
            as: HomeHighlightsResponse.self) else { return nil }
        return merge(highlights: response, local: localPicks())
    }

    /// 服务端精选为准；同一张若已在 App Group 里有小图，带上它作为秒开占位。
    nonisolated static func merge(highlights: HomeHighlightsResponse, local: [HomeTodayPick]) -> [HomeTodayPick] {
        var seen = Set<String>()
        return highlights.items.compactMap { item in
            guard seen.insert(item.id).inserted else { return nil }
            let path = [item.largeUrl, item.previewUrl].compactMap { $0 }.first { !$0.isEmpty }
            let localFile = local.first { $0.id == item.id }?.localFileURL
            guard path != nil || localFile != nil else { return nil }
            return HomeTodayPick(id: item.id, remotePath: path, localFileURL: localFile,
                                 reason: highlights.reasonById?[item.id], caption: item.description)
        }
    }

    /// `DailyPicksStore` 写好的今日精选（过期自动为空）。
    nonisolated static func localPicks(now: Date = .now) -> [HomeTodayPick] {
        guard let dir = DailyPicksStore.directory else { return [] }
        return DailyPicksStore.load(now: now).map {
            HomeTodayPick(id: $0.id, remotePath: nil, localFileURL: dir.appendingPathComponent($0.file),
                          reason: $0.reason, caption: $0.description)
        }
    }
}

nonisolated struct HomeTodayPick: Hashable, Sendable, Identifiable {
    let id: String
    let remotePath: String?
    let localFileURL: URL?
    let reason: String?
    let caption: String?

    /// 大图上的标签：服务端给的理由（如「那年今天」），没有就叫「今日精选」。
    var chip: String {
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "今日精选" : trimmed
    }

    var displayCaption: String? {
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated struct HomeHighlightItem: Decodable, Sendable {
    let id: String
    let description: String?
    let previewUrl: String?
    let largeUrl: String?
}

nonisolated struct HomeHighlightsResponse: Decodable, Sendable {
    let items: [HomeHighlightItem]
    let reasonById: [String: String]?
}

// MARK: - 图片解码（后台）
nonisolated enum HomeImageDecoder {
    @concurrent
    static func decode(file url: URL, maxPixel: CGFloat) async -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(source, maxPixel: maxPixel)
    }

    @concurrent
    static func decode(data: Data, maxPixel: CGFloat) async -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(source, maxPixel: maxPixel)
    }

    private static func thumbnail(_ source: CGImageSource, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
