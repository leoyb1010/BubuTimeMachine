import Foundation
import UIKit
import AVFoundation

// MARK: - 媒体存储
/// 沙盒文件读写 + 缩略图生成。离线优先：媒体原文件落本地，永不丢失。
/// 目录结构：Documents/Media/<原文件>，Documents/Thumbnails/<缩略图>
/// nonisolated：缩略图解码在 Task.detached 后台执行，不绑定 MainActor。
nonisolated struct MediaStore: Sendable {

    private var mediaDir: URL {
        directory(named: "Media")
    }
    private var thumbnailDir: URL {
        directory(named: "Thumbnails")
    }

    private func directory(named name: String) -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(name, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: 写入

    /// 保存图片数据到沙盒，返回相对文件名。
    func savePhoto(_ data: Data, preferredExtension ext: String = "jpg") throws -> String {
        let name = "\(UUID().uuidString).\(ext)"
        let url = mediaDir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return name
    }

    /// 将外部文件（如 PhotosPicker 导出的视频）拷入沙盒，返回相对文件名。
    func importFile(from sourceURL: URL, preferredExtension ext: String) throws -> String {
        let fm = FileManager.default
        let name = "\(UUID().uuidString).\(ext)"
        let dest = mediaDir.appendingPathComponent(name)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: sourceURL, to: dest)
        return name
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

    /// 删除沙盒文件（媒体 / blob 通用）。
    func deleteMedia(named fileName: String) {
        try? FileManager.default.removeItem(at: mediaURL(for: fileName))
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
