import Foundation
import SwiftUI
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

    static func load(_ item: PhotosPickerItem) async throws -> Self {
        do {
            if let file = try await item.loadTransferable(type: Self.self) { return file }
        } catch {
            try Task.checkCancellation()
            // Some image providers supply only data, not a usable file representation.
            guard item.supportedContentTypes.contains(where: { $0.conforms(to: .image) }),
                  !item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) else { throw error }
        }
        try Task.checkCancellation()
        guard item.supportedContentTypes.contains(where: { $0.conforms(to: .image) }),
              !item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }),
              let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadUnknown) }
        try Task.checkCancellation()
        return try await Task.detached(priority: .utility) {
            let ext = MediaStore.sniffImageExtension(data) ?? "image"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID()).\(ext)")
            try data.write(to: url, options: .atomic)
            return Self(url: url)
        }.value
    }
}

nonisolated enum JournalImport {
    struct Result: Sendable {
        let file: JournalMediaFile
        let recognizedText: String
        var schoolReport: SchoolDailyReport?
        var warning: String?
    }

    /// Runs on the utility executor; returns value types only. The caller owns the resulting files.
    static func prepare(url: URL, report: Bool, store: MediaStore,
                        recognize: @escaping @Sendable (CGImage) throws -> [SchoolOCRLine] = recognizeText) async throws -> Result {
        try await Task.detached(priority: .utility) {
            let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard metadata.isRegularFile == true, (metadata.fileSize ?? 0) > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            // Provider URLs may be extensionless or end in .tmp. Decode the content
            // before consulting the filename; a suffix is not proof of media type.
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)
            let isImage = source.map { CGImageSourceGetCount($0) > 0 } ?? false
            let video = !isImage
            if video {
                let asset = AVURLAsset(url: url)
                guard try await asset.load(.isPlayable),
                      !(try await asset.loadTracks(withMediaType: .video)).isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            }
            guard !report || isImage else { throw CocoaError(.fileReadCorruptFile) }
            let hash = try MediaStore.sha256Hex(at: url)
            let extensionIsMovie = UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true
            let storedExtension = video && !extensionIsMovie ? "mp4" : url.pathExtension
            let fileName = try store.importFile(from: url, preferredExtension: storedExtension,
                                                sniffImage: !video)
            var thumbnail: String?
            do {
                try Task.checkCancellation()
                var text = ""
                var dailyReport: SchoolDailyReport? = report ? SchoolDailyReport() : nil
                dailyReport?.sourceHash = hash
                var warning: String?
                if !video, let source,
                   let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: report ? 2000 : 600
                   ] as CFDictionary) {
                    thumbnail = store.makePhotoThumbnail(fromImage: UIImage(cgImage: image))
                    if report {
                        do {
                            let lines = try recognize(image)
                            dailyReport = SchoolDailyReport.recognize(lines) ?? SchoolDailyReport()
                            dailyReport?.sourceHash = hash
                            text = lines.map(\.text).joined(separator: "\n")
                            if lines.isEmpty { warning = "原图已保留，暂未读到文字；可以对照原图直接填写。" }
                        } catch {
                            // OCR is an optional aid, not permission to discard a valid original.
                            warning = "原图已保留，文字识别暂未完成；可以直接填写。\(error.localizedDescription)"
                        }
                    }
                } else if video {
                    thumbnail = await store.makeVideoThumbnail(fromVideo: fileName)
                }
                dailyReport?.adoptRecognizedValues()
                try Task.checkCancellation()
                return Result(file: .init(id: UUID(), fileName: fileName, thumbnail: thumbnail,
                                          hash: hash, isVideo: video, isSchoolReport: dailyReport != nil),
                              recognizedText: text, schoolReport: dailyReport, warning: warning)
            } catch {
                store.deleteLocalFiles(media: fileName, thumbnail: thumbnail)
                throw error
            }
        }.value
    }

    static func recognizeText(_ image: CGImage) throws -> [SchoolOCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.customWords = ["亲子桥", "上午点心", "中午午餐", "水果", "下午点心", "午睡", "睡眠"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-uitest-school-import") {
            let details: [[String: Any]] = (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return ["text": candidate.string, "scores": SchoolCheckboxReader.scores(in: candidate, image: image),
                        "x": observation.boundingBox.minX, "y": 1 - observation.boundingBox.maxY]
            }
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("school-ocr-detail.json")
            try? JSONSerialization.data(withJSONObject: details, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        }
        #endif
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return SchoolOCRLine(text: candidate.string, x: observation.boundingBox.minX,
                y: 1 - observation.boundingBox.maxY, confidence: candidate.confidence,
                checkedOptions: SchoolCheckboxReader.selected(in: candidate, image: image),
                width: observation.boundingBox.width, height: observation.boundingBox.height)
        }
    }
}
