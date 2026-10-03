import Foundation

/// Transport failure releases only its batch, never the rate limit or other batches.
/// Keep the original FIFO-eight / strictly-over-one-minute power budget.
public nonisolated struct WatchPhotoRequestGate: Sendable {
    private var requested: [String] = []
    private var lastRequestAt: Date = .distantPast
    public init() {}

    public mutating func begin(fingerprint: String, at date: Date) -> Bool {
        guard !requested.contains(fingerprint), date.timeIntervalSince(lastRequestAt) > 60 else { return false }
        requested.append(fingerprint)
        if requested.count > 8 { requested.removeFirst() }
        lastRequestAt = date
        return true
    }

    public mutating func failed(fingerprint: String) {
        requested.removeAll { $0 == fingerprint }
    }
}
