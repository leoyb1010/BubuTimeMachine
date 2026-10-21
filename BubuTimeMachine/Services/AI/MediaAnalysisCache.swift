import Foundation
import CryptoKit

actor MediaAnalysisCache {
    static let shared = MediaAnalysisCache(directory: FileManager.default.urls(for: .cachesDirectory,
        in: .userDomainMask)[0].appendingPathComponent("BubuMediaAnalysis", isDirectory: true))

    nonisolated struct Key: Codable, Hashable, Sendable {
        let service: String
        let account: String
        let mediaID: String
        let contentHash: String?
    }
    nonisolated struct Entry: Codable, Sendable {
        let key: Key
        let analysis: MediaAnalysisDTO
        let fetchedAt: Date
    }
    private let directory: URL
    init(directory: URL) { self.directory = directory }

    func load(for key: Key) -> Entry? {
        guard let data = try? Data(contentsOf: file(for: key)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.key == key,
              entry.analysis.mediaID == key.mediaID else { return nil }
        if let expected = key.contentHash, !expected.isEmpty,
           let actual = entry.analysis.contentHash, !actual.isEmpty, expected != actual { return nil }
        return entry
    }

    func save(_ analysis: MediaAnalysisDTO, for key: Key, fetchedAt: Date = .now) throws {
        guard analysis.mediaID == key.mediaID else { throw LearningServiceError.invalidResponse }
        if let expected = key.contentHash, !expected.isEmpty,
           let actual = analysis.contentHash, !actual.isEmpty, expected != actual {
            throw LearningServiceError.invalidResponse
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(Entry(key: key, analysis: analysis, fetchedAt: fetchedAt))
            .write(to: file(for: key), options: .atomic)
    }

    func remove(for key: Key) { try? FileManager.default.removeItem(at: file(for: key)) }

    private func file(for key: Key) -> URL {
        // One version per scoped media: saving a new hash replaces the obsolete analysis rather than accumulating it.
        let identity = (try? JSONEncoder().encode([key.service, key.account, key.mediaID])) ?? Data()
        let name = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }
}
