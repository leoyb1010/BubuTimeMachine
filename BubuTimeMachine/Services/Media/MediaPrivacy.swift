import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - 对外分享前的元数据脱敏
/// `MediaStore.savePhoto` 是 `data.write(to:)` 原样落盘，**EXIF 一个字节都没动**——
/// 这是刻意的（`PhotoAnalyzer` 正是靠这份 EXIF 读拍摄时间和 GPS，端侧生成地点标签）。
///
/// 代价是：查看器里那个分享按钮直接把原文件推给微信 / AirDrop / 系统相册，
/// **家里的经纬度跟着一起出门**。对比之下分享卡走的是 `ImageRenderer` 重绘，
/// 天然没有 EXIF，那条路径一直是安全的。
///
/// 这里只做一件事：拷一份、抹掉位置相关的字段、其它原样保留。
/// 不动原文件——原片是家庭档案的一部分，EXIF 里的时间和相机信息以后还有用。
// 纯 ImageIO 工具，导出器在后台线程调用：显式 nonisolated，不能跟着默认 MainActor 隔离。
nonisolated enum MediaPrivacy {

    /// 会被抹掉的字段：GPS 字典，以及 TIFF/IPTC 里同样会泄漏位置的几项。
    /// 拍摄时间、相机型号、方向等一律保留——它们不暴露「家在哪」。
    static func strippingLocation(of url: URL) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source),
              CGImageSourceGetCount(source) > 0 else { return nil }

        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-\(UUID().uuidString)-\(url.lastPathComponent)")
        guard let destination = CGImageDestinationCreateWithURL(
            destURL as CFURL, type, CGImageSourceGetCount(source), nil) else { return nil }

        // kCFNull 表示「删掉这一项」，只传 nil 是「不修改」。
        // IPTC 的 City/ProvinceState/Country* 同样是"家在哪"，整组一起抹掉（标题/关键词
        // 这类文案对分享出去的照片没有保留价值）；EXIF/TIFF 的时间与相机信息保留。
        let removals: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: kCFNull as Any,
            kCGImagePropertyIPTCDictionary: kCFNull as Any,
        ]
        for index in 0..<CGImageSourceGetCount(source) {
            CGImageDestinationAddImageFromSource(destination, source, index, removals as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: destURL)
            return nil
        }
        return destURL
    }

    /// 这个文件是不是「抹得掉位置」的静态图片。
    /// 视频的位置元数据要重封装容器才能去掉，成本高得多，暂不在分享路径上做——
    /// 调用方据此如实告诉用户这一次分享的是原文件。
    static func isStrippableImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// 这张图里到底有没有位置信息。没有就不用多此一举拷一份。
    static func hasLocation(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }
        return props[kCGImagePropertyGPSDictionary] != nil
    }
}
