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

/// Only the explicit photo deck is eligible. Legacy health/text feeds stay off screen.
public nonisolated enum WatchReadModel {
    public static func memories(from snapshot: WatchSnapshot?) -> [WatchMemory] {
        var ids = Set<String>(), names = Set<String>()
        return Array((snapshot?.photoCards ?? []).filter {
            guard let name = $0.photoFileName, !name.isEmpty,
                  name == (name as NSString).lastPathComponent,
                  name != ".", name != "..", !name.contains("\\"),
                  !ids.contains($0.id), !names.contains(name) else { return false }
            ids.insert($0.id); names.insert(name)
            return true
        }.prefix(5))
    }
}
