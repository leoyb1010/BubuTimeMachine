import AppIntents
import CoreSpotlight
import Foundation
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
        title = cleanTitle?.isEmpty == false
            ? cleanTitle!
            : (cleanNote.isEmpty ? "一条布布时光" : String(cleanNote.prefix(28)))
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
            let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
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
    private static var pendingTask: Task<Void, Never>?

    /// 写入/同步后的多次刷新合并成一次。最多索引最近 2,000 条；更老记录仍可在 App 内搜索，
    /// 后续 Xcode 27 的 HistoryObserver 会把这里替换成真正的事务增量，而不是扩大窗口。
    static func schedule(context: ModelContext) {
        pendingTask?.cancel()
        guard UserDefaults.standard.bool(forKey: enabledKey) else {
            pendingTask = Task { try? await CSSearchableIndex.default().deleteAppEntities(ofType: BubuMomentEntity.self) }
            return
        }
        var descriptor = FetchDescriptor<Entry>(
            sortBy: [SortDescriptor(\Entry.happenedAt, order: .reverse)])
        descriptor.fetchLimit = 2_000
        let entities = ((try? context.fetch(descriptor)) ?? []).map(BubuMomentEntity.init(entry:))

        pendingTask = Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            try? await CSSearchableIndex.default().indexAppEntities(entities)
        }
    }

    static func setEnabled(_ enabled: Bool, context: ModelContext) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        schedule(context: context)
    }
}
