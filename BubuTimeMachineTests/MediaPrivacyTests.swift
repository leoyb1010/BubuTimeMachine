import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
@testable import BubuTimeMachine

// MARK: - 分享脱敏回归
/// 分享按钮以前直接把**原文件**推给微信 / AirDrop，而原片保留完整 EXIF
/// （`PhotoAnalyzer` 正是靠它读 GPS 生成地点标签），于是家里的经纬度跟着照片一起出门。
/// 这套测试钉住两件事：位置真的被抹掉了，以及拍摄时间这类无害元数据没被误删。
struct MediaPrivacyTests {

    /// 造一张带 GPS 与拍摄时间的真 JPEG。
    private func makeJPEGWithLocation() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("privacy-\(UUID().uuidString).jpg")
        let width = 8, height = 8
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = try #require(CGContext(data: nil, width: width, height: height,
                                         bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(red: 0.9, green: 0.6, blue: 0.7, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(ctx.makeImage())

        let dest = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let metadata: [CFString: Any] = [
            kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCCity: "北京",
                kCGImagePropertyIPTCCountryPrimaryLocationName: "中国",
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 39.9042,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 116.4074,
                kCGImagePropertyGPSLongitudeRef: "E",
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:09:04 10:30:00",
            ] as [CFString: Any],
        ]
        CGImageDestinationAddImage(dest, image, metadata as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    private func properties(of url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return [:] }
        return props
    }

    @Test("分享副本里的 GPS 被抹掉，拍摄时间保留")
    func stripsLocationKeepsTimestamp() throws {
        let original = try makeJPEGWithLocation()
        defer { try? FileManager.default.removeItem(at: original) }

        // 前提：原片确实带位置——否则这条测试等于什么都没验
        #expect(MediaPrivacy.hasLocation(original))

        let clean = try #require(MediaPrivacy.strippingLocation(of: original))
        defer { try? FileManager.default.removeItem(at: clean) }

        let cleanProps = properties(of: clean)
        #expect(cleanProps[kCGImagePropertyGPSDictionary] == nil, "位置没有被抹掉")
        // ImageIO 会从 EXIF 时间重新合成 IPTC 的 DateCreated/TimeCreated，所以字典本身可能仍在；
        // 要验的是位置类字段（城市/国家）确实没了。
        let iptc = cleanProps[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        #expect(iptc[kCGImagePropertyIPTCCity] == nil, "IPTC 城市同样暴露住址，必须抹掉")
        #expect(iptc[kCGImagePropertyIPTCCountryPrimaryLocationName] == nil, "IPTC 国家/地区必须抹掉")
        #expect(!MediaPrivacy.hasLocation(clean))

        // 拍摄时间不该被顺手删掉：它不暴露「家在哪」，而且是档案的一部分。
        let exif = cleanProps[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:09:04 10:30:00")

        // 原文件必须原封不动——原片是家庭档案，脱敏只发生在那份临时副本上。
        #expect(MediaPrivacy.hasLocation(original))

        // 画面还在，没有变成空文件
        #expect(properties(of: clean)[kCGImagePropertyPixelWidth] as? Int == 8)
    }

    @Test("视频不走图片脱敏路径")
    func videosAreNotTreatedAsImages() {
        let video = URL(fileURLWithPath: "/tmp/bubu.mov")
        #expect(!MediaPrivacy.isStrippableImage(video))
        let photo = URL(fileURLWithPath: "/tmp/bubu.jpg")
        #expect(MediaPrivacy.isStrippableImage(photo))
    }
}
