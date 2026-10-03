import Foundation
import ImageIO

nonisolated enum YearbookExportError: LocalizedError, Equatable {
    case unavailablePhotos(Int)
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .unavailablePhotos(let count):
            return "有 \(count) 张照片的原片尚未下载或无法读取，年册尚未生成。请到「同步与备份」补齐原片；如果仍无法读取，请重新导入该照片后再试。"
        case .renderFailed:
            return "年册排版未能完成，没有导出不完整文件。请稍后再试。"
        }
    }
}

/// Validate real originals, not thumbnails. Nil is an undownloaded reference,
/// while an empty list is a valid text-only entry/book.
nonisolated enum YearbookPhotoPreflight {
    static let photosPerPage = 4

    static func requireAvailable(pages: [[URL?]], cover: URL?) throws {
        var selected = pages.flatMap { $0.prefix(photosPerPage) }
        if let cover { selected.append(cover) }
        try requireAvailable(selected)
    }

    static func requireAvailable(_ urls: [URL?]) throws {
        let unavailable = urls.reduce(into: 0) { count, url in
            let readable = autoreleasepool {
                guard let url,
                      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      CGImageSourceGetStatus(source) == .statusComplete else { return false }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1200,
                    kCGImageSourceShouldCacheImmediately: true
                ]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil
            }
            if !readable { count += 1 }
        }
        guard unavailable == 0 else { throw YearbookExportError.unavailablePhotos(unavailable) }
    }
}
