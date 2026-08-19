import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - 桌面小组件图片解析（主 App 与 Widget 共用同一份规则）
/// 「快照里的文件名 → 一份能安全交给 WidgetKit 渲染的图片字节」这条规则，
/// 以前只存在于 Widget 进程里，主 App 无从校验，于是一次目录写错（预览小图落进 Media/）
/// 就能让桌面照片整体消失且长期没人发现。
/// 现在规则收在这里，两个 target 共用，主 App 侧的单元测试也能直接钉住它。
///
/// 规则：
/// 1. 共享容器 `Thumbnails/`
/// 2. 旧沙盒 `Thumbnails/`（App Group 媒体迁移窗口内，主 App 有图桌面不能没图）
/// 3. `Media/` 原图 —— **一律经 ImageIO 降采样**，绝不回原始字节。
///    文件小 ≠ 像素少：一张 1.5MB 的 4000×3000 JPEG 解码后是 48MB，
///    照样撞 WidgetKit ~30MB 的渲染预算，表现就是整张小组件空白。
nonisolated enum WidgetImageResolver {
    /// 单张图片进内存的上限。大尺寸时光款会同时读 3 张，必须压得足够小。
    static let maxImageBytes = 2 * 1_048_576
    /// 回退降采样的目标边长，与主 App 落盘缩略图同口径。
    static let fallbackMaxPixel = 600

    /// 查找顺序中的缩略图目录。
    static var thumbnailDirectories: [URL] {
        [BubuStorage.thumbnailDirectory, BubuStorage.legacyThumbnailDirectory]
    }

    /// 查找顺序中的原图目录。
    static var mediaDirectories: [URL] {
        [BubuStorage.mediaDirectory, BubuStorage.legacyMediaDirectory]
    }

    static func imageData(fileName: String?) -> Data? {
        guard let fileName,
              !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        for dir in thumbnailDirectories {
            if let data = boundedData(from: dir.appendingPathComponent(fileName)) {
                return data
            }
        }
        for dir in mediaDirectories {
            let url = dir.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let shrunk = downsampledJPEG(from: url), shrunk.count <= maxImageBytes { return shrunk }
        }
        return nil
    }

    /// 直接读取（仅用于已知是小图的缩略图目录）；超限返回 nil。
    static func boundedData(from url: URL) -> Data? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let byteCount = values.fileSize,
           byteCount > maxImageBytes {
            return nil
        }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    /// 用 ImageIO 直接产出降采样缩略图（不解码全图），再编码成 JPEG。
    static func downsampledJPEG(from url: URL, maxPixel: Int? = nil, quality: CGFloat = 0.7) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel ?? fallbackMaxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
