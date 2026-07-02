import Foundation
import UIKit
import AVFoundation

// MARK: - 媒体存储
/// 沙盒文件读写 + 缩略图生成。离线优先：媒体原文件落本地，永不丢失。
/// 目录结构：Documents/Media/<原文件>，Documents/Thumbnails/<缩略图>
/// nonisolated：缩略图解码在 Task.detached 后台执行，不绑定 MainActor。
nonisolated struct MediaStore: Sendable {
    static let publicUploadSoftLimitBytes: Int64 = 96 * 1_048_576

    // 媒体目录改读 App Group 共享容器（BubuStorage），让 Widget/extension 也能显示照片缩略图。
    // App Group 未就绪时 BubuStorage 自动回退到私有 Documents，与旧行为一致、不崩。
    private var mediaDir: URL {
        BubuStorage.mediaDirectory
    }
    private var thumbnailDir: URL {
        BubuStorage.thumbnailDirectory
    }

    // MARK: 写入

    /// 保存图片数据到沙盒，返回相对文件名。
    /// 扩展名按数据真实格式嗅探（HEIC/PNG/GIF/JPEG）——相册选出的 HEIC 不再被存成说谎的 .jpg，
    /// 30 年后脱离本 App 的通用读取（HTML 档案、其它看图软件）才不会踩坑。
    func savePhoto(_ data: Data, preferredExtension ext: String = "jpg") throws -> String {
        let name = "\(UUID().uuidString).\(Self.sniffImageExtension(data) ?? ext)"
        let url = mediaDir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return name
    }

    /// 按文件头识别常见图片格式；识别不出返回 nil（用调用方给的默认值）。
    static func sniffImageExtension(_ data: Data) -> String? {
        guard data.count >= 12 else { return nil }
        let bytes = [UInt8](data.prefix(12))
        if bytes[0] == 0xFF, bytes[1] == 0xD8 { return "jpg" }
        if bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 { return "png" }
        if bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 { return "gif" }
        // ISO BMFF：offset 4 起为 "ftyp"，再看 brand
        if bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
            let brand = String(bytes: bytes[8...11], encoding: .ascii) ?? ""
            if brand.hasPrefix("heic") || brand.hasPrefix("heix") || brand.hasPrefix("mif1") { return "heic" }
            if brand.hasPrefix("avif") { return "avif" }
        }
        return nil
    }

    /// 将外部文件（如 PhotosPicker 导出的视频）拷入沙盒，返回相对文件名。
    func importFile(from sourceURL: URL, preferredExtension ext: String, sniffImage: Bool = false) throws -> String {
        let fm = FileManager.default
        let resolvedExt = sniffImage
            ? (Self.sniffImageExtension(at: sourceURL) ?? Self.cleanExtension(ext, fallback: "jpg"))
            : Self.cleanExtension(ext, fallback: "bin")
        let name = "\(UUID().uuidString).\(resolvedExt)"
        let dest = mediaDir.appendingPathComponent(name)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: sourceURL, to: dest)
        return name
    }

    static func sniffImageExtension(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 32)) ?? Data()
        return sniffImageExtension(data)
    }

    private static func cleanExtension(_ ext: String, fallback: String) -> String {
        let allowed = ext.lowercased().filter { $0.isLetter || $0.isNumber }
        return allowed.isEmpty ? fallback : String(allowed.prefix(12))
    }

    func importVideoForSync(from sourceURL: URL,
                            targetMaxBytes: Int64 = Self.publicUploadSoftLimitBytes) async throws -> ImportedVideo {
        let originalBytes = fileSize(at: sourceURL) ?? 0
        let originalExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        guard originalBytes > targetMaxBytes else {
            let fileName = try importFile(from: sourceURL, preferredExtension: originalExtension)
            return ImportedVideo(fileName: fileName, originalBytes: originalBytes,
                                 storedBytes: fileSize(forMedia: fileName) ?? originalBytes,
                                 wasCompressed: false)
        }

        let presets = [AVAssetExportPresetMediumQuality, AVAssetExportPresetLowQuality]
        for preset in presets {
            guard let exported = try? await exportVideo(sourceURL, presetName: preset) else { continue }
            defer { try? FileManager.default.removeItem(at: exported) }
            let exportedBytes = fileSize(at: exported) ?? 0
            guard exportedBytes > 0, exportedBytes < originalBytes else { continue }
            let fileName = try importFile(from: exported, preferredExtension: "mp4")
            return ImportedVideo(fileName: fileName, originalBytes: originalBytes,
                                 storedBytes: fileSize(forMedia: fileName) ?? exportedBytes,
                                 wasCompressed: true)
        }

        let fileName = try importFile(from: sourceURL, preferredExtension: originalExtension)
        return ImportedVideo(fileName: fileName, originalBytes: originalBytes,
                             storedBytes: fileSize(forMedia: fileName) ?? originalBytes,
                             wasCompressed: false)
    }

    /// 将录音临时文件移入沙盒，返回相对文件名（.m4a）。
    func importAudio(from sourceURL: URL) throws -> String {
        let fm = FileManager.default
        let name = "voice_\(UUID().uuidString).m4a"
        let dest = mediaDir.appendingPathComponent(name)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: sourceURL, to: dest)
        return name
    }

    // MARK: 读取

    /// 由相对文件名解析为沙盒绝对 URL。
    func mediaURL(for fileName: String) -> URL {
        mediaDir.appendingPathComponent(fileName)
    }

    func thumbnailURL(for fileName: String) -> URL {
        thumbnailDir.appendingPathComponent(fileName)
    }

    func data(forMedia fileName: String) -> Data? {
        try? Data(contentsOf: mediaURL(for: fileName))
    }

    // MARK: 加密 blob（时间胶囊）

    /// 保存任意二进制（如时间胶囊加密载荷）到沙盒，返回相对文件名。
    func saveBlob(_ data: Data, preferredExtension ext: String = "capsule") throws -> String {
        let name = "\(UUID().uuidString).\(ext)"
        let url = mediaDir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return name
    }

    /// 读取沙盒中的二进制 blob。
    func blob(named fileName: String) -> Data? {
        try? Data(contentsOf: mediaURL(for: fileName))
    }

    func fileExists(forMedia fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: mediaURL(for: fileName).path)
    }

    func fileSize(forMedia fileName: String) -> Int64? {
        fileSize(at: mediaURL(for: fileName))
    }

    func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return nil }
        return Int64(size)
    }

    /// 删除沙盒文件（媒体 / blob 通用）。
    func deleteMedia(named fileName: String) {
        try? FileManager.default.removeItem(at: mediaURL(for: fileName))
    }

    /// 删除缩略图文件。
    func deleteThumbnail(named fileName: String) {
        try? FileManager.default.removeItem(at: thumbnailURL(for: fileName))
    }

    /// 删除一组本地文件，忽略不存在的文件，保证 UI 删除不会被 IO 失败阻塞。
    func deleteLocalFiles(media fileName: String?, thumbnail thumbnailName: String? = nil) {
        if let fileName { deleteMedia(named: fileName) }
        if let thumbnailName { deleteThumbnail(named: thumbnailName) }
    }

    // MARK: 缩略图

    /// 为图片生成并保存缩略图，返回缩略图相对文件名。
    func makePhotoThumbnail(fromImage image: UIImage, maxPixel: CGFloat = 600) -> String? {
        guard let thumb = image.bubu_resized(maxPixel: maxPixel),
              let data = thumb.jpegData(compressionQuality: 0.7) else { return nil }
        let name = "thumb_\(UUID().uuidString).jpg"
        let url = thumbnailDir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// 为视频在首帧生成缩略图。
    func makeVideoThumbnail(fromVideo fileName: String, maxPixel: CGFloat = 600) async -> String? {
        let asset = AVURLAsset(url: mediaURL(for: fileName))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        do {
            let cgImage = try await generator.image(at: .zero).image
            let image = UIImage(cgImage: cgImage)
            return makePhotoThumbnail(fromImage: image, maxPixel: maxPixel)
        } catch {
            return nil
        }
    }

    private func exportVideo(_ sourceURL: URL, presetName: String) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bubu-compressed-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: outputURL, as: .mp4)
        return outputURL
    }
}

struct ImportedVideo: Sendable {
    let fileName: String
    let originalBytes: Int64
    let storedBytes: Int64
    let wasCompressed: Bool
}

// MARK: - UIImage 缩放工具
nonisolated extension UIImage {
    /// 等比缩放，使长边不超过 maxPixel。
    func bubu_resized(maxPixel: CGFloat) -> UIImage? {
        let longSide = max(size.width, size.height)
        guard longSide > maxPixel else { return self }
        let scale = maxPixel / longSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
