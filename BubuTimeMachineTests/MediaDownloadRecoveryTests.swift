import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

@MainActor
struct MediaDownloadRecoveryTests {
    @Test("最新一页都已下载，也能发现更早记录丢失的本地原件")
    func findsMissingOriginalBeyondFirstPage() throws {
        let container = try ModelContainer(for: SharedModelContainer.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        for index in 0..<505 {
            let media = Media(type: .photo, localFileName: "exists-\(index).jpg")
            media.remoteURL = "https://example.invalid/\(index).jpg"
            media.syncState = .synced
            media.createdAt = Date(timeIntervalSince1970: Double(index + 100))
            context.insert(media)
        }
        let missing = Media(type: .photo, localFileName: "missing.jpg")
        missing.createdAt = Date(timeIntervalSince1970: 1)
        missing.remoteURL = "https://example.invalid/missing.jpg"
        missing.syncState = .synced
        context.insert(missing)
        let unsynced = Media(type: .photo, localFileName: "unuploaded.jpg")
        unsynced.remoteURL = "https://example.invalid/previous.jpg"
        unsynced.syncState = .local
        context.insert(unsynced)
        try context.save()
        let candidates = try SyncEngine.mediaNeedingDownload(in: context, limit: 2,
            fileExists: { $0.hasPrefix("exists-") })
        #expect(candidates.map(\.id) == [missing.id])
        #expect(missing.localFileName == "missing.jpg") // Selection must not mutate before successful download.
    }
}
