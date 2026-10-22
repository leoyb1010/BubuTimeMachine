import Foundation
import AVFoundation
import CoreGraphics
import CoreText
import ImageIO
import UIKit

/// One photo in the film: the downloaded large preview and its caption.
nonisolated struct FilmFrameInput: Sendable {
    let imageData: Data
    let caption: String
}

nonisolated enum BirthdayFilmError: LocalizedError {
    case writer
    var errorDescription: String? { "影片没有生成成功，请稍后再试。" }
}

/// Renders a silent 1080×1920 H.264 film on-device: opening title, one Ken Burns shot per
/// photo with a month caption, a soft cross-fade between shots, and a closing card.
/// Each frame is drawn with Core Graphics into a pooled pixel buffer; only the current and
/// next photos are decoded (downsampled to 1600 px) at any time.
nonisolated enum BirthdayFilmRenderer {
    static let width = 1080
    static let height = 1920
    static let fps: Int32 = 30
    static let titleSeconds = 3.2
    static let closingSeconds = 3.6
    static let fadeSeconds = 0.45

    private enum Shot { case title, photo(Int), closing }
    /// The photo, plus a 40 px copy that reads as a soft blur when stretched behind landscape shots.
    private struct Picture { let full: CGImage; let tiny: CGImage? }

    static func duration(photoCount: Int) -> Double {
        titleSeconds + closingSeconds + BirthdayFilmPlanner.photoSeconds(count: photoCount) * Double(photoCount)
    }

    @concurrent
    static func render(moments: [FilmFrameInput], title: String, subtitle: String, closing: String,
                       closingSubtitle: String, to url: URL,
                       progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 9_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw BirthdayFilmError.writer }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? BirthdayFilmError.writer }
        writer.startSession(atSourceTime: .zero)

        let photoSeconds = BirthdayFilmPlanner.photoSeconds(count: moments.count)
        var shots: [(shot: Shot, start: Double, length: Double)] = [(.title, 0, titleSeconds)]
        var clock = titleSeconds
        for index in moments.indices {
            shots.append((.photo(index), clock, photoSeconds))
            clock += photoSeconds
        }
        shots.append((.closing, clock, closingSeconds))
        let total = clock + closingSeconds
        let frameCount = Int((total * Double(fps)).rounded(.up))
        var decoded: [Int: Picture] = [:]

        func image(_ index: Int) -> Picture? {
            if let cached = decoded[index] { return cached }
            guard moments.indices.contains(index), let image = downsample(moments[index].imageData, maxPixel: 1600) else { return nil }
            let picture = Picture(full: image, tiny: downsample(moments[index].imageData, maxPixel: 40))
            decoded[index] = picture
            return picture
        }

        do {
            for frame in 0..<frameCount {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    // A failed writer never becomes ready again; leave instead of spinning forever.
                    guard writer.status == .writing else { throw writer.error ?? BirthdayFilmError.writer }
                    try await Task.sleep(for: .milliseconds(4))
                }
                guard let pool = adaptor.pixelBufferPool else { throw BirthdayFilmError.writer }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { throw BirthdayFilmError.writer }

                let time = Double(frame) / Double(fps)
                let current = shots.lastIndex { $0.start <= time } ?? 0
                // Keep only the photos near the playhead in memory.
                if case .photo(let index) = shots[current].shot {
                    for key in decoded.keys where key < index - 1 || key > index + 1 { decoded[key] = nil }
                }

                CVPixelBufferLockBaseAddress(buffer, [])
                if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                           bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                    context.interpolationQuality = .medium
                    let entry = shots[current]
                    draw(entry.shot, local: time - entry.start, length: entry.length, in: context,
                         moments: moments, image: image, title: title, subtitle: subtitle,
                         closing: closing, closingSubtitle: closingSubtitle)
                    let remaining = entry.start + entry.length - time
                    if remaining < fadeSeconds, current + 1 < shots.count {
                        let next = shots[current + 1]
                        context.saveGState()
                        context.setAlpha(CGFloat(1 - remaining / fadeSeconds))
                        draw(next.shot, local: 0, length: next.length, in: context, moments: moments, image: image,
                             title: title, subtitle: subtitle, closing: closing, closingSubtitle: closingSubtitle)
                        context.restoreGState()
                    }
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])

                guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps)) else {
                    throw writer.error ?? BirthdayFilmError.writer
                }
                if frame % 15 == 0 {
                    let value = Double(frame) / Double(frameCount)
                    await progress(value)
                }
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? BirthdayFilmError.writer }
            await progress(1)
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    // MARK: Drawing (bottom-left origin)

    private static let cream = CGColor(red: 1.0, green: 0.973, blue: 0.941, alpha: 1)
    private static let pink = CGColor(red: 1.0, green: 0.761, blue: 0.839, alpha: 1)
    private static let rose = CGColor(red: 0.851, green: 0.38, blue: 0.494, alpha: 1)
    private static let brown = CGColor(red: 0.353, green: 0.239, blue: 0.204, alpha: 1)

    private static func draw(_ shot: Shot, local: Double, length: Double, in context: CGContext,
                             moments: [FilmFrameInput], image: (Int) -> Picture?, title: String, subtitle: String,
                             closing: String, closingSubtitle: String) {
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        switch shot {
        case .title:
            card(in: context, canvas: canvas, progress: local / length)
            let rise = CGFloat(min(local / 0.8, 1))
            text(title, size: 104, weight: .heavy, color: brown, centerX: canvas.midX, baselineY: canvas.midY + 40 + 30 * (1 - rise), in: context)
            text(subtitle, size: 46, weight: .semibold, color: rose, centerX: canvas.midX, baselineY: canvas.midY - 70, in: context)
        case .closing:
            card(in: context, canvas: canvas, progress: local / length)
            text(closing, size: 92, weight: .heavy, color: brown, centerX: canvas.midX, baselineY: canvas.midY + 40, in: context)
            text(closingSubtitle, size: 44, weight: .semibold, color: rose, centerX: canvas.midX, baselineY: canvas.midY - 70, in: context)
        case .photo(let index):
            context.setFillColor(cream)
            context.fill(canvas)
            guard let shotImage = image(index) else { break }
            let picture = shotImage.full
            let p = smoothstep(local / length)
            let size = CGSize(width: picture.width, height: picture.height)
            let landscape = size.width > size.height * 1.05
            if landscape {
                // Soft backdrop: the same photo drawn tiny-then-huge reads as a blur, cheaply.
                if let tiny = shotImage.tiny {
                    context.saveGState()
                    context.interpolationQuality = .high
                    context.setAlpha(0.7)
                    context.draw(tiny, in: fill(size, in: canvas.insetBy(dx: -120, dy: -120)))
                    context.restoreGState()
                }
                context.setFillColor(cream.copy(alpha: 0.45) ?? cream)
                context.fill(canvas)
            }
            let zoomIn = index % 2 == 0
            let zoom = zoomIn ? 1.0 + 0.12 * p : 1.12 - 0.12 * p
            let base = landscape ? fit(size, in: canvas.insetBy(dx: 0, dy: 260)) : fill(size, in: canvas)
            var rect = base.applying(CGAffineTransform(scaleX: zoom, y: zoom))
            rect.origin.x = base.midX - rect.width / 2
            rect.origin.y = base.midY - rect.height / 2
            // Pan direction cycles so consecutive shots don't drift the same way.
            let slack = CGSize(width: max(0, rect.width - canvas.width) / 2, height: max(0, rect.height - canvas.height) / 2)
            let directions: [CGPoint] = [CGPoint(x: -1, y: 0.4), CGPoint(x: 1, y: -0.3), CGPoint(x: 0.3, y: 1), CGPoint(x: -0.4, y: -1)]
            let direction = directions[index % directions.count]
            rect.origin.x += direction.x * slack.width * CGFloat(p - 0.5) * 1.6
            rect.origin.y += direction.y * slack.height * CGFloat(p - 0.5) * 1.6
            if landscape {
                context.saveGState()
                context.addPath(CGPath(roundedRect: rect, cornerWidth: 36, cornerHeight: 36, transform: nil))
                context.clip()
                context.draw(picture, in: rect)
                context.restoreGState()
            } else {
                context.draw(picture, in: rect)
            }
            caption(moments[index].caption, in: context, canvas: canvas)
        }
    }

    private static func card(in context: CGContext, canvas: CGRect, progress: Double) {
        let colors = [pink, cream] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvas.maxY), end: CGPoint(x: canvas.maxX, y: 0), options: [])
        }
        // A few drifting bubbles for warmth.
        let bubbles: [(CGFloat, CGFloat, CGFloat)] = [(0.18, 0.78, 90), (0.82, 0.70, 60), (0.25, 0.22, 70), (0.78, 0.18, 110), (0.55, 0.88, 40)]
        for (index, bubble) in bubbles.enumerated() {
            let drift = CGFloat(sin(progress * .pi + Double(index))) * 24
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
            context.fillEllipse(in: CGRect(x: canvas.width * bubble.0 - bubble.2 / 2, y: canvas.height * bubble.1 - bubble.2 / 2 + drift,
                                           width: bubble.2, height: bubble.2))
        }
    }

    private static func caption(_ value: String, in context: CGContext, canvas: CGRect) {
        guard !value.isEmpty else { return }
        let line = makeLine(value, size: 48, weight: .bold, color: brown, maxWidth: canvas.width - 200)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let band = CGRect(x: canvas.midX - bounds.width / 2 - 44, y: 170, width: bounds.width + 88, height: 104)
        context.setFillColor(cream.copy(alpha: 0.92) ?? cream)
        context.addPath(CGPath(roundedRect: band, cornerWidth: 52, cornerHeight: 52, transform: nil))
        context.fillPath()
        context.setFillColor(rose)
        context.fillEllipse(in: CGRect(x: band.minX + 20, y: band.midY - 7, width: 14, height: 14))
        context.textPosition = CGPoint(x: canvas.midX - bounds.width / 2 + 8, y: band.midY - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, context)
    }

    private static func text(_ value: String, size: CGFloat, weight: UIFont.Weight, color: CGColor,
                             centerX: CGFloat, baselineY: CGFloat, in context: CGContext) {
        guard !value.isEmpty else { return }
        let line = makeLine(value, size: size, weight: weight, color: color, maxWidth: CGFloat(width) - 120)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.textPosition = CGPoint(x: centerX - bounds.width / 2 - bounds.minX, y: baselineY)
        CTLineDraw(line, context)
    }

    private static func makeLine(_ value: String, size: CGFloat, weight: UIFont.Weight, color: CGColor, maxWidth: CGFloat) -> CTLine {
        var pointSize = size
        while true {
            let system = UIFont.systemFont(ofSize: pointSize, weight: weight)
            let font = system.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: pointSize) } ?? system
            let attributed = NSAttributedString(string: value, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font as CTFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            if CTLineGetBoundsWithOptions(line, .useOpticalBounds).width <= maxWidth || pointSize <= 24 { return line }
            pointSize -= 4
        }
    }

    private static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func fill(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - target.width / 2, y: rect.midY - target.height / 2, width: target.width, height: target.height)
    }

    static func fit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - target.width / 2, y: rect.midY - target.height / 2, width: target.width, height: target.height)
    }

    static func downsample(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }
}
