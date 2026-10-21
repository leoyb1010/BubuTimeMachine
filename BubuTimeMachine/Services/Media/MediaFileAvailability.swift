import Foundation

/// A database filename is not proof that its bytes survived a restore or disk cleanup.
nonisolated enum MediaFileAvailability {
    static func localURL(fileName: String?, resolve: (String) -> URL,
                         exists: (URL) -> Bool) -> URL? {
        guard let fileName else { return nil }
        let url = resolve(fileName)
        return exists(url) ? url : nil
    }

    static func needsDownload(fileName: String?, remoteURL: String?, isSynced: Bool,
                              exists: (String) -> Bool) -> Bool {
        guard let remoteURL, !remoteURL.isEmpty else { return false }
        guard let fileName else { return true }
        return isSynced && !exists(fileName)
    }
}
