import Foundation
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import ImageIO
import Vision
import UIKit
import AVFoundation

/// PhotosPicker hands over a file, including for video: never load a whole movie as Data.
struct JournalPickedFile: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try copy(received.file)
        }
        FileRepresentation(importedContentType: .movie) { received in
            try copy(received.file)
        }
    }
    nonisolated private static func copy(_ source: URL) throws -> Self {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-\(UUID().uuidString)").appendingPathExtension(source.pathExtension)
        try FileManager.default.copyItem(at: source, to: url)
        return Self(url: url)
    }
}

nonisolated enum JournalImport {
    struct Result: Sendable { let file: JournalMediaFile; let recognizedText: String }

    /// Runs on the utility executor; returns value types only. The caller owns the resulting files.
    static func prepare(url: URL, report: Bool, store: MediaStore) async throws -> Result {
        try await Task.detached(priority: .utility) {
            let type = UTType(filenameExtension: url.pathExtension)
            let video = type?.conforms(to: .movie) == true
            guard video || type?.conforms(to: .image) == true else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard metadata.isRegularFile == true, (metadata.fileSize ?? 0) > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if video {
                guard try await AVURLAsset(url: url).load(.isPlayable) else { throw CocoaError(.fileReadCorruptFile) }
            } else {
                guard let image = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(image) > 0 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
            let hash = try MediaStore.sha256Hex(at: url)
            let fileName = try store.importFile(from: url, preferredExtension: url.pathExtension,
                                                sniffImage: !video)
            var thumbnail: String?
            do {
                try Task.checkCancellation()
                var text = ""
                if !video, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: report ? 2000 : 600
                   ] as CFDictionary) {
                    thumbnail = store.makePhotoThumbnail(fromImage: UIImage(cgImage: image))
                    if report {
                        let request = VNRecognizeTextRequest()
                        request.recognitionLevel = .accurate
                        request.recognitionLanguages = ["zh-Hans", "en-US"]
                        request.customWords = ["午餐", "早餐", "晚餐", "午饭", "加餐", "午睡", "入睡", "起床"]
                        request.usesLanguageCorrection = true
                        try VNImageRequestHandler(cgImage: image).perform([request])
                        text = (request.results ?? []).compactMap { observation in
                            // Confidence is not calibrated across languages: a fixed 0.5
                            // threshold silently removed a readable Chinese meal line. Keep
                            // the original candidate for explicit review, never auto-publish it.
                            guard let candidate = observation.topCandidates(1).first else { return nil }
                            return candidate.string
                        }.joined(separator: "\n")
                    }
                } else if video {
                    thumbnail = await store.makeVideoThumbnail(fromVideo: fileName)
                }
                try Task.checkCancellation()
                return Result(file: .init(id: UUID(), fileName: fileName, thumbnail: thumbnail,
                                          hash: hash, isVideo: video), recognizedText: text)
            } catch {
                store.deleteLocalFiles(media: fileName, thumbnail: thumbnail)
                throw error
            }
        }.value
    }
}
