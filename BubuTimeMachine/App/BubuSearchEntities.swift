import AppIntents
import CoreSpotlight
import Foundation
import OSLog
import SwiftData
import UniformTypeIdentifiers

// MARK: - 系统搜索实体
/// 把家庭事实映射成只读系统实体。系统索引只保存文字摘要与本地 deep link，
/// 不保存照片、人脸特征、服务器地址或家庭账号。
struct BubuMomentEntity: IndexedEntity, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "布布时光")
    static let defaultQuery = BubuMomentEntityQuery()

    let id: UUID
    let title: String
    let note: String
    let happenedAt: Date
    let isArchived: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(BubuDateFormat.shortDate(happenedAt)) · \(note)")
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.contentDescription = note
        attributes.contentCreationDate = happenedAt
        attributes.contentURL = BubuRoute.momentURL(id: id)
        attributes.keywords = ["布布", "时光", BubuDateFormat.shortDate(happenedAt)]
        return attributes
    }

    var hideInSpotlight: Bool { isArchived }

    @MainActor
    init(entry: Entry) {
        id = entry.id
        let cleanTitle = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = (entry.firstPersonNote ?? entry.note ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanTitle, !cleanTitle.isEmpty {
            title = cleanTitle
        } else {
            title = cleanNote.isEmpty ? "一条布布时光" : String(cleanNote.prefix(28))
        }
        note = cleanNote.isEmpty ? "家人记录的成长瞬间" : String(cleanNote.prefix(120))
        happenedAt = entry.happenedAt
        isArchived = entry.isArchived
    }
}

struct BubuMomentEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [BubuMomentEntity] {
        guard let context = SharedModelContainer.sharedIfAvailable?.mainContext else { return [] }
        var result: [BubuMomentEntity] = []
        for id in identifiers {
            let descriptor = FetchDescriptor<Entry>(predicate: #Predicate {
                $0.id == id && !$0.isArchived
            })
            if let entry = try? context.fetch(descriptor).first {
                result.append(BubuMomentEntity(entry: entry))
            }
        }
        return result
    }

    @MainActor
    func entities(matching string: String) async throws -> [BubuMomentEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return try await suggestedEntities() }
        return recentEntries(limit: 800)
            .filter { entry in
                [entry.title, entry.note, entry.firstPersonNote, entry.locationName, entry.authorRole]
                    .compactMap { $0 }
                    .contains { $0.localizedCaseInsensitiveContains(needle) }
            }
            .prefix(80)
            .map(BubuMomentEntity.init(entry:))
    }

    @MainActor
    func suggestedEntities() async throws -> [BubuMomentEntity] {
        recentEntries(limit: 40).map(BubuMomentEntity.init(entry:))
    }

    @MainActor
    private func recentEntries(limit: Int) -> [Entry] {
        guard let context = SharedModelContainer.sharedIfAvailable?.mainContext else { return [] }
        var descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\Entry.happenedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }
}

// MARK: - 增量索引调度
@MainActor
enum BubuMomentSpotlightIndexer {
    static let enabledKey = "bubu.spotlight.enabled"
    private static let indexedIDsKey = "bubu.spotlight.indexedIDs"
    private static let clearedKey = "bubu.spotlight.cleared"
    private static let log = Logger(subsystem: "com.bubu.timemachine", category: "Spotlight")
    private static var pendingTask: Task<Void, Never>?

    /// 写入/同步后的多次刷新合并成一次。最多索引最近 2,000 条；更老记录仍可在 App 内搜索，
    /// 后续 Xcode 27 的 HistoryObserver 会把这里替换成真正的事务增量，而不是扩大窗口。
    static func schedule(context: ModelContext) {
        // CoreSpotlight 的系统调用不承诺响应 Swift Task cancellation。
        // 新任务必须先等旧任务真正返回，关闭索引的 delete 才不会被迟到的旧 index 覆盖。
        let previousTask = pendingTask
        previousTask?.cancel()
        guard UserDefaults.standard.bool(forKey: enabledKey) else {
            guard !UserDefaults.standard.bool(forKey: clearedKey) else { return }
            pendingTask = Task {
                await previousTask?.value
                guard !Task.isCancelled else { return }
                do {
                    try await CSSearchableIndex.default().deleteAppEntities(ofType: BubuMomentEntity.self)
                    UserDefaults.standard.removeObject(forKey: indexedIDsKey)
                    UserDefaults.standard.set(true, forKey: clearedKey)
                } catch {
                    log.error("清除 Spotlight 时光索引失败，将在下次刷新重试")
                }
            }
            return
        }
        // 一旦准备写入，就不能继续沿用上次“已清空”的状态。
        // 否则用户在本次 indexAppEntities 尚未返回时立刻关闭，关闭路径会误判无需删除。
        UserDefaults.standard.set(false, forKey: clearedKey)

        pendingTask = Task {
            await previousTask?.value
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            // 防抖结束后才读库：连续保存/同步不会在主线程反复拉 2,000 条。
            var descriptor = FetchDescriptor<Entry>(
                predicate: #Predicate { !$0.isArchived },
                sortBy: [SortDescriptor(\Entry.happenedAt, order: .reverse)])
            descriptor.fetchLimit = 2_000
            let entities = ((try? context.fetch(descriptor)) ?? []).map(BubuMomentEntity.init(entry:))
            let currentIDs = Set(entities.map(\.id))
            let previousIDs = Set(
                (UserDefaults.standard.stringArray(forKey: indexedIDsKey) ?? [])
                    .compactMap(UUID.init(uuidString:)))
            let staleIDs = staleIdentifiers(previous: previousIDs, current: currentIDs)

            do {
                if !staleIDs.isEmpty {
                    try await CSSearchableIndex.default().deleteAppEntities(
                        identifiedBy: staleIDs, ofType: BubuMomentEntity.self)
                }
                if !entities.isEmpty {
                    try await CSSearchableIndex.default().indexAppEntities(entities)
                }
                UserDefaults.standard.set(
                    currentIDs.map(\.uuidString).sorted(), forKey: indexedIDsKey)
                UserDefaults.standard.set(false, forKey: clearedKey)
            } catch {
                log.error("更新 Spotlight 时光索引失败，将在下次刷新重试")
            }
        }
    }

    static func setEnabled(_ enabled: Bool, context: ModelContext) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if !enabled { UserDefaults.standard.set(false, forKey: clearedKey) }
        schedule(context: context)
    }

    nonisolated static func staleIdentifiers(previous: Set<UUID>, current: Set<UUID>) -> [UUID] {
        Array(previous.subtracting(current)).sorted { $0.uuidString < $1.uuidString }
    }
}
