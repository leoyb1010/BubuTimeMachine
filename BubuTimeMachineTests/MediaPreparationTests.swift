import Foundation
import SwiftData
import UIKit
import Testing
@testable import BubuTimeMachine

@MainActor
struct MediaPreparationTests {
    @Test("视频准备从实际保存的文件回填方向、时长与内容哈希")
    func videoPreparationPreservesMetadata() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("prepare-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: source) }
        try await VideoMetadataTests.makeVideo(at: source, rotated: true)
        let store = MediaStore()
        let prepared = try await MediaPreparation.video(from: source, store: store)
        defer { store.deleteLocalFiles(media: prepared.fileName, thumbnail: prepared.thumbnailFileName) }
        let media = prepared.makeMedia()
        #expect(media.width == 16 && media.height == 32)
        #expect((media.durationSeconds ?? 0) >= 1)
        #expect(media.contentHash == (try MediaStore.sha256Hex(at: store.mediaURL(for: prepared.fileName))))
        #expect(media.thumbnailFileName != nil)
    }

    @Test("新建与追加共用照片准备结果，哈希、像素尺寸、分析标签都写进媒体")
    func photoPreparationPreservesMetadata() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 48), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
        }
        let data = try #require(image.pngData())
        let store = MediaStore()
        let prepared = try await MediaPreparation.photo(data: data, store: store, analyzer: PhotoAnalyzer(),
                                                        includeLocation: false)
        defer { store.deleteLocalFiles(media: prepared.fileName, thumbnail: prepared.thumbnailFileName) }
        let media = prepared.makeMedia()
        #expect(media.width == 32 && media.height == 48)
        #expect(media.contentHash == MediaStore.sha256Hex(data))
        #expect(media.aiTags == prepared.analysis?.tags)
        #expect(media.thumbnailFileName != nil)
        #expect(store.data(forMedia: prepared.fileName) == data)
        #expect(prepared.analysis?.latitude == nil && prepared.analysis?.longitude == nil)
    }

    @Test("追加带拍摄日期的准备结果不改写记录日期或家长文字")
    func appendPreservesEntryFacts() throws {
        let container = try ModelContainer(for: SharedModelContainer.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let entry = Entry(authorRole: "妈妈", note: "家长原文")
        entry.happenedAt = Date(timeIntervalSince1970: 100)
        context.insert(entry)
        try context.save()
        let prepared = PreparedMedia(type: .photo, fileName: "prepared.jpg", thumbnailFileName: nil,
            contentHash: "hash", width: 32, height: 48, duration: nil,
            analysis: PhotoAnalysis(captureDate: .now, latitude: nil, longitude: nil,
                                    locationName: nil, tags: ["食物"], faceCount: 0), tags: ["食物"])
        try EntryMediaAppendCommit.save([prepared.makeMedia()], to: entry.id, in: context,
                                        removeFiles: { _, _ in Issue.record("成功追加不可清理文件") })
        let freshContext = ModelContext(container)
        let persisted = try #require(freshContext.fetch(FetchDescriptor<Entry>()).first)
        #expect(persisted.happenedAt == Date(timeIntervalSince1970: 100))
        #expect(persisted.note == "家长原文")
        #expect(persisted.media.first?.aiTags == ["食物"])
        #expect(persisted.media.first?.contentHash == "hash")
    }
}
