import Foundation
import SwiftData

// MARK: - 同步账本（不改 @Model schema 的本机同步事实）
/// 2.27 起同步引擎需要记住三件 SwiftData 模型里没有字段的事，全部放进本机 UserDefaults：
///
/// 1. **真实编辑时间**：里程碑、第一次、家庭成员、布布档案、健康记录、家人补充、记录语音、
///    成长之声、时间胶囊这 9 类模型没有 editedAt。以前推送时把 clientUpdatedAt 写成「推送时刻」，
///    于是离线很久的旧副本一上线就盖掉家人后来的新编辑（D9-02）。现在主上下文每次保存时，
///    凡是被标成 `.local`（=用户刚改过）的这几类对象都在这里打一个编辑时间点，推送时作为 LWW 版本号。
/// 2. **恢复重传（create-only）**：「全部重传」只把服务器缺的补上；服务器已有的以服务器为准，绝不覆盖。
/// 3. **需要处理的失败条目**：文件丢了这类永久失败不再每轮报红、不再拖慢退避，而是列进同步中心，
///    可重试、可放弃；以及因此被跳过的远端删除标记，修好后再补删。
///
/// 账本只是同步的辅助信息：丢了（换机/清数据）最坏退化成旧行为（推送时刻比对），不会丢用户数据。
@MainActor
final class SyncLedger {
    static let shared = SyncLedger(defaults: .standard)

    private let defaults: UserDefaults
    /// 引擎自己批量改状态（全部重传标脏）时置位，避免把「重传」误记成「用户刚编辑」。
    var suppressEditStamps = false

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static func key(_ collection: String, _ id: UUID) -> String { "\(collection):\(id.uuidString)" }

    // MARK: 1 · 编辑时间

    private static let editsKey = "bubu.sync.ledger.edits.v1"
    private static let recoveryKey = "bubu.sync.ledger.recovery.v1"
    private static let attentionKey = "bubu.sync.ledger.attention.v1"
    private static let failuresKey = "bubu.sync.ledger.failures.v1"
    private static let deferredKey = "bubu.sync.ledger.deferredTombstones.v1"

    private var edits: [String: Double] {
        get { defaults.dictionary(forKey: Self.editsKey) as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: Self.editsKey) }
    }

    func stampEdit(_ key: String, at date: Date = .now) {
        var all = edits
        all[key] = date.timeIntervalSince1970
        edits = all
    }

    func editedAt(_ key: String) -> Date? {
        edits[key].map { Date(timeIntervalSince1970: $0) }
    }

    /// 把这次保存里「用户刚改过」的对象记下编辑时间；同时让它们退出「需要处理」名单
    /// （用户动过它，说明想让它重新排队）。由 SyncEngine 监听主线程 ModelContext.willSave 调用。
    func recordEdits(in context: ModelContext, at date: Date = .now) {
        guard !suppressEditStamps else { return }
        let touched = context.insertedModelsArray + context.changedModelsArray
        guard !touched.isEmpty else { return }
        var all = edits
        var attention = attentionItems
        var failures = failureCounts
        var changed = false
        for model in touched {
            guard let identity = Self.dirtyIdentity(of: model) else { continue }
            let key = Self.key(identity.collection, identity.id)
            if Self.editTrackedCollections.contains(identity.collection) {
                all[key] = date.timeIntervalSince1970
                changed = true
            }
            if attention.contains(where: { $0.key == key }) {
                attention.removeAll { $0.key == key }
                failures[key] = nil
                attentionItems = attention
                failureCounts = failures
            }
        }
        if changed { edits = all }
    }

    /// 只有这 9 类靠账本记编辑时间；Entry 有 editedAt，疫苗/成长测量有 updatedAt，媒体不做内容 LWW。
    static let editTrackedCollections: Set<String> = [
        "milestones", "firsttimes", "members", "childprofile", "healthrecords",
        "comments", "voicenotes", "voicememos", "timecapsules",
    ]

    /// 处于 `.local`（用户刚改、待上传）的可同步对象 → (集合, localId)。
    static func dirtyIdentity(of model: any PersistentModel) -> (collection: String, id: UUID)? {
        switch model {
        case let m as Milestone where m.syncState == .local: return ("milestones", m.id)
        case let m as FirstTime where m.syncState == .local: return ("firsttimes", m.id)
        case let m as FamilyMember where m.syncState == .local: return ("members", m.id)
        case let m as ChildProfile where m.syncState == .local: return ("childprofile", m.id)
        case let m as HealthRecord where m.syncState == .local: return ("healthrecords", m.id)
        case let m as Comment where m.syncState == .local: return ("comments", m.id)
        case let m as VoiceNote where m.syncState == .local: return ("voicenotes", m.id)
        case let m as VoiceMemo where m.syncState == .local: return ("voicememos", m.id)
        case let m as TimeCapsule where m.syncState == .local: return ("timecapsules", m.id)
        case let m as Entry where m.syncState == .local: return ("entries", m.id)
        case let m as Media where m.syncState == .local: return ("media", m.id)
        case let m as VaccineRecord where m.syncState == .local: return ("vaccinerecords", m.id)
        case let m as GrowthMeasurement where m.syncState == .local: return ("growthmeasurements", m.id)
        default: return nil
        }
    }

    // MARK: 2 · 恢复重传（create-only）

    private var recovery: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.recoveryKey) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Self.recoveryKey) }
    }

    func markRecovery(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        recovery = recovery.union(keys)
    }

    func isRecovery(_ key: String) -> Bool { recovery.contains(key) }

    /// 推送确认成功（本地已 synced）后清掉这条的编辑时间、恢复标记与失败计数。
    func clearAfterPush(_ key: String) {
        var all = edits
        if all.removeValue(forKey: key) != nil { edits = all }
        var rec = recovery
        if rec.remove(key) != nil { recovery = rec }
        var failures = failureCounts
        if failures.removeValue(forKey: key) != nil { failureCounts = failures }
    }

    // MARK: 3 · 需要处理的失败条目

    struct AttentionItem: Codable, Identifiable, Hashable, Sendable {
        var key: String
        var collection: String
        var localId: UUID
        /// 人能看懂的条目名（「一张照片」「布布档案」）。
        var label: String
        /// 人能看懂的原因（「本地文件不见了」）。
        var reason: String
        var since: Date
        /// 用户选了「放弃上传」：仍不再排队，但从列表里收起。
        var skipped: Bool = false
        var id: String { key }
    }

    /// 非本地硬错误（例如服务器对单条持续 400）连续失败这么多轮才进「需要处理」，偶发抖动不算。
    static let attentionThreshold = 3

    private(set) var attentionItems: [AttentionItem] {
        get {
            guard let data = defaults.data(forKey: Self.attentionKey) else { return [] }
            return (try? JSONDecoder().decode([AttentionItem].self, from: data)) ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.attentionKey) }
    }

    private var failureCounts: [String: Int] {
        get { defaults.dictionary(forKey: Self.failuresKey) as? [String: Int] ?? [:] }
        set { defaults.set(newValue, forKey: Self.failuresKey) }
    }

    /// 记一次单条推送失败。返回 true 表示它已进入「需要处理」名单——调用方不再把它算作整轮失败。
    @discardableResult
    func noteFailure(collection: String, id: UUID, label: String, reason: String,
                     immediate: Bool, at date: Date = .now) -> Bool {
        let key = Self.key(collection, id)
        var failures = failureCounts
        let count = (failures[key] ?? 0) + 1
        guard immediate || count >= Self.attentionThreshold else {
            failures[key] = count
            failureCounts = failures
            return false
        }
        failures[key] = nil
        failureCounts = failures
        var items = attentionItems
        if !items.contains(where: { $0.key == key }) {
            items.append(AttentionItem(key: key, collection: collection, localId: id,
                                       label: label, reason: reason, since: date))
            attentionItems = items
        }
        return true
    }

    /// 某集合里不再自动排队的 localId（含已放弃的）。
    func excludedIDs(for collection: String) -> Set<UUID> {
        Set(attentionItems.filter { $0.collection == collection }.map(\.localId))
    }

    var excludedCount: Int { attentionItems.count }

    /// 「重试」：移出名单，下一轮重新排队。
    func resolveAttention(_ key: String) {
        attentionItems = attentionItems.filter { $0.key != key }
        var failures = failureCounts
        failures[key] = nil
        failureCounts = failures
    }

    /// 「放弃上传」：留在本机，不再排队，也不再出现在待处理列表。
    func skipAttention(_ key: String) {
        attentionItems = attentionItems.map { item in
            var item = item
            if item.key == key { item.skipped = true }
            return item
        }
    }

    /// 本地已不存在的条目（被删了）从名单里清掉。
    func pruneAttention(keeping exists: (AttentionItem) -> Bool) {
        let items = attentionItems
        let kept = items.filter(exists)
        if kept.count != items.count { attentionItems = kept }
    }

    // MARK: 4 · 被跳过的远端删除标记

    /// 远端删了、但本机这条还有没传上去的改动（或子媒体卡住）时，删除被跳过；
    /// 游标已越过那条墓碑，不记下来就永远补不回去。这里按集合记下 localId，每轮拉取后补删一次。
    private var deferred: [String: [String]] {
        get { defaults.dictionary(forKey: Self.deferredKey) as? [String: [String]] ?? [:] }
        set { defaults.set(newValue, forKey: Self.deferredKey) }
    }

    func deferTombstones(collection: String, localIds: [String]) {
        guard !localIds.isEmpty else { return }
        var all = deferred
        all[collection] = Array(Set(all[collection] ?? []).union(localIds)).sorted()
        deferred = all
    }

    func deferredTombstones() -> [String: [String]] { deferred }

    func replaceDeferredTombstones(collection: String, localIds: [String]) {
        var all = deferred
        all[collection] = localIds.isEmpty ? nil : localIds.sorted()
        deferred = all
    }
}
