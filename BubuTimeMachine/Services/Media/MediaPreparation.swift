import Foundation
import ImageIO

/// Files and metadata are prepared away from SwiftData; each caller keeps its existing commit boundary.
nonisolated struct PreparedMedia: Sendable {
    let type: MediaType
    let fileName: String
    let thumbnailFileName: String?
    let contentHash: String
    let width: Int?
    let height: Int?
    let duration: Double?
    var analysis: PhotoAnalysis?
    let tags: [String]

    @MainActor func makeMedia() -> Media {
        let media = Media(type: type, localFileName: fileName)
        media.thumbnailFileName = thumbnailFileName
        media.contentHash = contentHash
        media.width = width
        media.height = height
        media.durationSeconds = duration
        media.aiTags = tags
        return media
    }
}

nonisolated enum MediaPreparation {
    @concurrent
    static func photo(data: Data, store: MediaStore, analyzer: PhotoAnalyzer,
                      includeLocation: Bool) async throws -> PreparedMedia {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let fileName = try store.savePhoto(data)
        var thumbnail: String?
        var prepared = false
        defer { if !prepared { store.deleteLocalFiles(media: fileName, thumbnail: thumbnail) } }
        guard let image = ThumbnailProvider.downsample(url: store.mediaURL(for: fileName), maxPixel: 600) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        thumbnail = store.makePhotoThumbnail(fromImage: image)
        let analysis = await analyzer.analyze(imageData: data, includeLocation: includeLocation,
                                            resolveLocationName: false)
        try Task.checkCancellation()
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let swapsAxes = (5...8).contains(orientation)
        let result = PreparedMedia(type: .photo, fileName: fileName, thumbnailFileName: thumbnail,
            contentHash: MediaStore.sha256Hex(data), width: swapsAxes ? pixelHeight : pixelWidth,
            height: swapsAxes ? pixelWidth : pixelHeight, duration: nil, analysis: analysis, tags: analysis.tags)
        prepared = true
        return result
    }

    @concurrent
    static func video(from url: URL, store: MediaStore) async throws -> PreparedMedia {
        try Task.checkCancellation()
        let imported = try await store.importVideoForSync(from: url)
        let fileName = imported.fileName
        var thumbnail: String?
        var prepared = false
        defer { if !prepared { store.deleteLocalFiles(media: fileName, thumbnail: thumbnail) } }
        let storedURL = store.mediaURL(for: fileName)
        let metadata = await VideoMetadata.read(from: storedURL)
        let hash = try MediaStore.sha256Hex(at: storedURL)
        thumbnail = await store.makeVideoThumbnail(fromVideo: fileName)
        try Task.checkCancellation()
        let result = PreparedMedia(type: .video, fileName: fileName, thumbnailFileName: thumbnail,
            contentHash: hash, width: metadata.width, height: metadata.height, duration: metadata.duration,
            analysis: nil, tags: imported.wasCompressed ? ["已压缩", "视频"] : [])
        prepared = true
        return result
    }
}
