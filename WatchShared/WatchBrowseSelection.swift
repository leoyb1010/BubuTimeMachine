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

/// v1 phones only have recent records. Browse them without changing the wire contract.
public nonisolated enum WatchReadModel {
    public static func memories(from snapshot: WatchSnapshot?) -> [WatchMemory] {
        guard let snapshot else { return [] }
        let source: [WatchMemory]
        if let memories = snapshot.memories, !memories.isEmpty {
            source = memories
        } else {
            source = snapshot.recent.map {
                WatchMemory(id: $0.id, dateText: $0.dateText, note: $0.note, ageText: "",
                            moodEmoji: $0.moodEmoji, photoFileName: $0.photoFileName)
            }
        }
        var seen = Set<String>()
        return source.filter { seen.insert($0.id).inserted }
    }
}
