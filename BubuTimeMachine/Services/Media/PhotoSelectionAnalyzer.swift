import CoreGraphics
import Foundation
import ImageIO
import Vision

nonisolated struct PhotoSelectionSignals: Sendable, Equatable {
    let perceptualHash: UInt64
    let sharpness: Double
    let exposure: Double
    let qualityScore: Double
    let shouldSuppress: Bool
    let suppressionReason: String?
}

nonisolated struct PhotoSelectionItem: Sendable, Equatable {
    let identifier: String
    let signals: PhotoSelectionSignals
}

nonisolated struct PhotoSimilarityGroup: Sendable, Equatable {
    let representativeIdentifier: String
    let memberIdentifiers: [String]
}

/// 端侧精选的可解释信号：近似照只折叠、低分照只降序，绝不删除原片。
nonisolated enum PhotoSelectionAnalyzer {
    static func analyze(imageData: Data, isScreenshot: Bool) -> PhotoSelectionSignals? {
        guard let image = downsampledCGImage(from: imageData, maxPixel: 512),
              let pixels = grayscalePixels(from: image, width: 64, height: 64),
              let hashPixels = grayscalePixels(from: image, width: 9, height: 8) else { return nil }

        let mean = pixels.reduce(0.0) { $0 + Double($1) } / Double(pixels.count) / 255
        let exposure = max(0, 1 - abs(mean - 0.5) * 2)
        let sharpness = normalizedEdgeEnergy(pixels, width: 64, height: 64)
        let quality = min(1, sharpness * 0.68 + exposure * 0.32)
        let contentSuppression = suppressionReason(in: image)
        let reason = isScreenshot ? "截图或录屏默认不推荐" : contentSuppression
        return PhotoSelectionSignals(
            perceptualHash: differenceHash(hashPixels, width: 9, height: 8),
            sharpness: sharpness,
            exposure: exposure,
            qualityScore: quality,
            shouldSuppress: reason != nil,
            suppressionReason: reason
        )
    }

    /// 贪心近邻分组足够覆盖连拍/近似照；每组以质量分最高者作代表。
    /// 输入通常已在一个时间事件内，避免把跨年份构图相似的照片误折叠。
    static func groupSimilar(
        _ items: [PhotoSelectionItem],
        maximumHammingDistance: Int = 7
    ) -> [PhotoSimilarityGroup] {
        let eligible = items.filter { !$0.signals.shouldSuppress }
        var used = Set<String>()
        var groups: [PhotoSimilarityGroup] = []
        for anchor in eligible {
            guard !used.contains(anchor.identifier) else { continue }
            let members = eligible.filter {
                !used.contains($0.identifier)
                    && hammingDistance(anchor.signals.perceptualHash, $0.signals.perceptualHash)
                        <= maximumHammingDistance
            }
            members.forEach { used.insert($0.identifier) }
            let representative = members.max {
                if $0.signals.qualityScore != $1.signals.qualityScore {
                    return $0.signals.qualityScore < $1.signals.qualityScore
                }
                return $0.identifier > $1.identifier
            } ?? anchor
            groups.append(PhotoSimilarityGroup(
                representativeIdentifier: representative.identifier,
                memberIdentifiers: members.map(\.identifier)
            ))
        }
        return groups
    }

    static func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }

    static func differenceHash(_ pixels: [UInt8], width: Int, height: Int) -> UInt64 {
        guard width == 9, height == 8, pixels.count >= width * height else { return 0 }
        var result: UInt64 = 0
        var bit = 0
        for row in 0..<height {
            for column in 0..<(width - 1) {
                if pixels[row * width + column] > pixels[row * width + column + 1] {
                    result |= UInt64(1) << UInt64(bit)
                }
                bit += 1
            }
        }
        return result
    }

    private static func normalizedEdgeEnergy(_ pixels: [UInt8], width: Int, height: Int) -> Double {
        guard pixels.count >= width * height, width > 1, height > 1 else { return 0 }
        var total = 0.0
        var comparisons = 0
        for y in 0..<height {
            for x in 0..<width {
                let value = Int(pixels[y * width + x])
                if x + 1 < width {
                    total += Double(abs(value - Int(pixels[y * width + x + 1])))
                    comparisons += 1
                }
                if y + 1 < height {
                    total += Double(abs(value - Int(pixels[(y + 1) * width + x])))
                    comparisons += 1
                }
            }
        }
        guard comparisons > 0 else { return 0 }
        // 家庭照片的平均相邻像素差约 0...64；压到 0...1，极端噪声也不会越界。
        return min(1, total / Double(comparisons) / 64)
    }

    /// 二维码、票据和文档只做“默认不推荐”信号，仍保留在列表供用户手动选择。
    private static func suppressionReason(in image: CGImage) -> String? {
        let barcode = VNDetectBarcodesRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .fast
        text.usesLanguageCorrection = false
        text.minimumTextHeight = 0.035
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        guard (try? handler.perform([barcode, text])) != nil else { return nil }
        if !(barcode.results ?? []).isEmpty { return "二维码默认不推荐" }
        if (text.results ?? []).count >= 6 { return "文档或票据默认不推荐" }
        return nil
    }

    private static func downsampledCGImage(from data: Data, maxPixel: CGFloat) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    private static func grayscalePixels(from image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}
