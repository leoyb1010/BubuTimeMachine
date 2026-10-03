import Foundation

/// Eligibility belongs to the exact ZIP being shared, never to a previous export.
nonisolated struct ArchiveExportShare: Sendable {
    let url: URL
    let isComplete: Bool

    func recordCompletion(completed: Bool, error: Error?,
                          defaults: UserDefaults = .standard, at date: Date = .now) {
        guard isComplete, completed, error == nil else { return }
        defaults.set(date.timeIntervalSince1970, forKey: "bubu.lastExportAt")
    }
}
