import Testing
import Foundation
import UIKit
import ImageIO
@testable import BubuTimeMachine

// MARK: - 桌面小组件照片链路回归测试
/// 钉死 v2.11.0 修掉的那条断链：同步的「预览秒出」通道把服务端小图落进 **Media/**，
/// 文件名却写进 `Media.thumbnailFileName`；而缩略图的两个读取方（主 App 的
/// `MediaStore.thumbnailURL` 与桌面小组件）都只查 **Thumbnails/** ——
/// 于是「更新过一次图片后桌面小组件不再显示照片」。
///
/// 这里把审计报告 1.3 表格里的每条根因固化成断言：
/// 1. 预览通道必须落缩略图目录（根因①）
/// 2. 存量脏数据必须能自愈搬回（根因①的存量部分）
/// 3. 小组件读图必须有 Thumbnails → legacy → Media(降采样) 三级兜底（根因③）
/// 4. 任何一级返回的数据都必须 ≤2MB 且像素受控（根因④⑤，WidgetKit 内存红线）
struct WidgetPhotoPipelineTests {

    // MARK: 工具

    /// 造一张指定尺寸的纯色 JPEG，写进临时文件，返回 URL。
    private func makeJPEG(width: CGFloat, height: CGFloat, color: UIColor = .systemPink) throws -> URL {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let data = try #require(image.jpegData(compressionQuality: 0.9))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bubu-test-\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }

    /// 读一段图片数据的真实像素尺寸（用来证明「确实降采样了」，而不只是字节数碰巧小）。
    private func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    private func cleanUp(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: 根因① —— 预览通道必须落缩略图目录

    @Test("同步预览小图落进 Thumbnails/，thumbnailURL 能解析出来")
    func importThumbnailLandsInThumbnailDirectory() throws {
        let store = MediaStore()
        let source = try makeJPEG(width: 600, height: 400)
        defer { cleanUp([source]) }

        let name = try store.importThumbnail(from: source)
        defer { store.deleteThumbnail(named: name) }

        #expect(name.hasPrefix("thumb_"), "预览小图应沿用 thumb_ 前缀，便于与原片区分")

        let resolved = store.thumbnailURL(for: name)
        #expect(FileManager.default.fileExists(atPath: resolved.path),
                "写进 thumbnailFileName 的文件名，必须能被 thumbnailURL 解析到实存文件")
        #expect(resolved.deletingLastPathComponent().lastPathComponent == "Thumbnails")

        // 关键回归：它绝不能只存在于 Media/ —— 那正是桌面照片消失的根因。
        #expect(!FileManager.default.fileExists(
            atPath: BubuStorage.mediaDirectory.appendingPathComponent(name).path))
    }

    @Test("小组件按缩略图文件名能读到数据")
    func widgetResolvesThumbnailName() throws {
        let store = MediaStore()
        let source = try makeJPEG(width: 600, height: 400)
        defer { cleanUp([source]) }
        let name = try store.importThumbnail(from: source)
        defer { store.deleteThumbnail(named: name) }

        let data = try #require(WidgetImageResolver.imageData(fileName: name),
                                "缩略图目录里的图，小组件必须读得到")
        #expect(data.count <= WidgetImageResolver.maxImageBytes)
    }

    // MARK: 根因① 存量部分 —— 自愈搬回

    @Test("误落在 Media/ 的缩略图能被自愈搬回 Thumbnails/")
    func strayThumbnailIsRelocated() throws {
        let store = MediaStore()
        let source = try makeJPEG(width: 600, height: 400)
        defer { cleanUp([source]) }

        // 复现脏数据：用 importFile 落到 Media/，把文件名当成缩略图名使用。
        let strayName = try store.importFile(from: source, preferredExtension: "jpg", sniffImage: true)
        defer {
            store.deleteMedia(named: strayName)
            store.deleteThumbnail(named: strayName)
        }
        #expect(WidgetImageResolver.boundedData(
            from: BubuStorage.thumbnailDirectory.appendingPathComponent(strayName)) == nil,
                "自愈前，缩略图目录里不该有这个文件")

        #expect(store.relocateStrayThumbnail(named: strayName), "第一次调用应真的搬了文件")
        #expect(FileManager.default.fileExists(
            atPath: BubuStorage.thumbnailDirectory.appendingPathComponent(strayName).path))
        #expect(!FileManager.default.fileExists(
            atPath: BubuStorage.mediaDirectory.appendingPathComponent(strayName).path),
                "默认是搬不是拷，不留占空间的副本")

        #expect(!store.relocateStrayThumbnail(named: strayName), "已在位就不该重复搬，保证幂等")
    }

    @Test("自愈时若缩略图名与原片同名，改为拷贝，绝不搬走原片")
    func relocateKeepsSourceWhenSharedWithOriginal() throws {
        let store = MediaStore()
        let source = try makeJPEG(width: 600, height: 400)
        defer { cleanUp([source]) }
        let name = try store.importFile(from: source, preferredExtension: "jpg", sniffImage: true)
        defer {
            store.deleteMedia(named: name)
            store.deleteThumbnail(named: name)
        }

        #expect(store.relocateStrayThumbnail(named: name, keepSource: true))
        #expect(FileManager.default.fileExists(
            atPath: BubuStorage.mediaDirectory.appendingPathComponent(name).path),
                "原片必须原地保留")
        #expect(FileManager.default.fileExists(
            atPath: BubuStorage.thumbnailDirectory.appendingPathComponent(name).path))
    }

    // MARK: 根因③④⑤ —— 三级兜底 + 内存红线

    @Test("只有原图时，小组件仍读得到，且一定是降采样后的小图")
    func widgetFallsBackToDownsampledOriginal() throws {
        let store = MediaStore()
        // 4000×3000：字节可能不大，但解码后约 48MB，直接回原始字节就会撞 WidgetKit 红线。
        let source = try makeJPEG(width: 4000, height: 3000)
        defer { cleanUp([source]) }
        let name = try store.importFile(from: source, preferredExtension: "jpg", sniffImage: true)
        defer { store.deleteMedia(named: name) }

        let data = try #require(WidgetImageResolver.imageData(fileName: name),
                                "只有原图时也必须有图，不能整墙空白")
        #expect(data.count <= WidgetImageResolver.maxImageBytes)

        let size = try #require(pixelSize(of: data))
        #expect(max(size.width, size.height) <= CGFloat(WidgetImageResolver.fallbackMaxPixel),
                "回退必须经 ImageIO 降采样到 600px，不能把原始像素直接丢给 WidgetKit")
    }

    @Test("缩略图优先于原图：两处都在时读的是缩略图")
    func thumbnailWinsOverOriginal() throws {
        let store = MediaStore()
        let big = try makeJPEG(width: 2000, height: 2000, color: .systemBlue)
        let small = try makeJPEG(width: 120, height: 120, color: .systemGreen)
        defer { cleanUp([big, small]) }

        // 同名文件分别落两个目录：Media/<name> 是大图，Thumbnails/<name> 是小图。
        let name = "bubu-test-\(UUID().uuidString).jpg"
        let mediaURL = BubuStorage.mediaDirectory.appendingPathComponent(name)
        let thumbURL = BubuStorage.thumbnailDirectory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: big, to: mediaURL)
        try FileManager.default.copyItem(at: small, to: thumbURL)
        defer { cleanUp([mediaURL, thumbURL]) }

        let data = try #require(WidgetImageResolver.imageData(fileName: name))
        let size = try #require(pixelSize(of: data))
        #expect(size == CGSize(width: 120, height: 120), "应命中缩略图目录那张，而不是原图")
    }

    @Test("文件名为空或找不到文件时安全返回 nil，不崩")
    func missingFileReturnsNil() {
        #expect(WidgetImageResolver.imageData(fileName: nil) == nil)
        #expect(WidgetImageResolver.imageData(fileName: "   ") == nil)
        #expect(WidgetImageResolver.imageData(fileName: "not-there-\(UUID().uuidString).jpg") == nil)
    }

    // MARK: 契约 —— 快照里的照片名必须全部可解析

    @Test("快照里的每个照片文件名都必须能解析出 ≤2MB 的数据")
    func everySnapshotPhotoNameResolves() throws {
        let store = MediaStore()
        var created: [String] = []
        defer { for n in created { store.deleteThumbnail(named: n) } }

        for _ in 0..<3 {
            let src = try makeJPEG(width: 800, height: 600)
            defer { cleanUp([src]) }
            created.append(try store.importThumbnail(from: src))
        }

        let snapshot = SharedWidgetSnapshot(
            name: "布布", birthday: .now,
            recentPhotoFileName: created.first,
            avatarFileName: created.first,
            photoFileNames: created,
            moments: created.map { SharedMoment(photoFileName: $0, date: .now) },
            updatedAt: .now)

        var names: [String] = snapshot.photoFileNames ?? []
        if let n = snapshot.recentPhotoFileName { names.append(n) }
        if let n = snapshot.avatarFileName { names.append(n) }
        names.append(contentsOf: (snapshot.moments ?? []).map(\.photoFileName))

        for name in Set(names) {
            let data = try #require(WidgetImageResolver.imageData(fileName: name),
                                    "快照引用了 \(name)，小组件却读不出来 —— 桌面会是空白")
            #expect(data.count <= WidgetImageResolver.maxImageBytes)
        }
    }
}
