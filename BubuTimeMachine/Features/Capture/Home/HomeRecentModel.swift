import Foundation

// MARK: - 首页「最近时光」
/// 和「时光」Tab 的默认流是同一份数据：第二大脑在线素材的第一页（默认查询，与时光共用离线缓存）
/// 并上本机家人记录，按时间倒序取前几条。先用缓存秒开，再安静地刷新（一分钟内不重复请求）。
/// 未连接家庭服务时只剩家人记录，和时光未连接时一致。
@Observable
@MainActor
final class HomeRecentModel {
    private(set) var items: [OnlineTimelineItem] = []
    private(set) var hasMore = false
    private var scope: String?
    private var lastFetch = Date.distantPast

    nonisolated private static let query = OnlineTimelineQuery()

    func load(client: BubuLearningClient?, force: Bool = false) async {
        guard let client else {
            items = []; hasMore = false; scope = nil; lastFetch = .distantPast
            return
        }
        let key = Self.query.cacheKey
        if scope != client.scope {
            // 换账号：旧账号的素材不能留在首页。
            scope = client.scope
            items = []; hasMore = false; lastFetch = .distantPast
            let account = client.scope
            let cached = await Task.detached(priority: .userInitiated) {
                OnlineTimelineFeedCache.load(scope: account, key: key)
            }.value
            guard scope == account else { return }
            if let cached, items.isEmpty { items = cached.page.items; hasMore = cached.page.hasMore }
        }
        guard force || Date.now.timeIntervalSince(lastFetch) > 60 else { return }
        let account = client.scope
        guard let page = try? await client.get("api/online-timeline", query: Self.query.parameters(page: 1),
                                               as: OnlineTimelinePage.self),
              !Task.isCancelled, scope == account else { return }
        lastFetch = .now
        items = page.items
        hasMore = page.hasMore
        // 同一个缓存键：时光 Tab 打开时也能直接用这一页秒开。
        Task.detached(priority: .utility) { OnlineTimelineFeedCache.save(page, scope: account, key: key) }
    }

    /// Marked "not Bubu" in the detail pager.
    func remove(_ id: String) {
        guard let scope, let item = items.first(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        let key = Self.query.cacheKey
        Task.detached(priority: .utility) { OnlineTimelineFeedCache.remove(id, isVideo: item.isVideo, scope: scope, key: key) }
    }

    /// The newest `limit` elements in 时光's default order: online items merged with family records when connected,
    /// otherwise family records only. `family` arrives newest first.
    nonisolated static func elements(items: [OnlineTimelineItem], family: [OnlineTimelineFamilyRef], connected: Bool,
                                     hasMore: Bool, limit: Int) -> [OnlineTimelineElement] {
        let merged = OnlineTimelineLayoutBuilder.elements(items: connected ? items : [], family: family, query: query,
                                                          source: connected ? .merged : .family, hasMore: hasMore)
        return Array(merged.elements.prefix(limit))
    }
}
