import Foundation
import ImageIO
import Vision

nonisolated struct ChildIdentityMatch: Sendable, Equatable {
    let faceCount: Int
    let isLikelyChild: Bool
    let confidence: Double
    let nearestPositiveDistance: Float?
    let nearestNegativeDistance: Float?
}

nonisolated struct ChildIdentityModelStatus: Sendable, Equatable {
    let enabled: Bool
    let positiveSamples: Int
    let negativeSamples: Int

    var isReady: Bool { enabled && positiveSamples > 0 }
}

/// 只在本机保存与使用的布布身份模型。
///
/// Vision 人脸特征以安全归档后的二进制写入独立的 `PhotoIdentity.sqlite`；
/// 该文件不进入系统备份，也不进入 SwiftData、同步请求、PocketBase、日志或应用导出包。
/// 正负反馈都只用于本机近邻判定。
nonisolated struct ChildIdentityRecognizer: Sendable {
    private static let enabledKey = "bubu.photoIdentity.enabled"
    private static let defaultDistanceThreshold: Float = 0.46
    private static let negativeMargin: Float = 0.04
    private let store: PhotoIntakeStore

    init(store: PhotoIntakeStore = PhotoIntakeStore(
        databaseURL: BubuStorage.identityDatabaseURL,
        excludeFromBackup: true
    )) {
        self.store = store
    }

    var isEnabled: Bool {
        UserDefaults(suiteName: BubuStorage.appGroupID)?.bool(forKey: Self.enabledKey) ?? false
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults(suiteName: BubuStorage.appGroupID)?.set(enabled, forKey: Self.enabledKey)
    }

    func status() throws -> ChildIdentityModelStatus {
        let counts = try store.identitySampleCounts()
        return ChildIdentityModelStatus(
            enabled: isEnabled,
            positiveSamples: counts.positive,
            negativeSamples: counts.negative
        )
    }

    /// 用户明确反馈后才学习。正样本表示“这是布布”，负样本表示“不是布布”。
    /// 返回实际识别到并写入的脸数；没检测到脸时不会写空样本。
    @discardableResult
    func learn(imageData: Data, isChild: Bool) async throws -> Int {
        let prints = await Self.faceFeaturePrints(from: imageData)
        guard !prints.isEmpty else { return 0 }
        let positiveSamples = try store.identitySamples()
            .filter { $0.label == 1 }
            .map(\.featureData)
        let selected: [Data]
        if isChild {
            if positiveSamples.isEmpty {
                // 首次头像学习必须是单人照，防止把合影里的家人一起注册成布布。
                guard prints.count == 1 else { return 0 }
                selected = [prints[0]]
            } else {
                // 正反馈合影只学习最接近既有布布模型的那张脸。
                guard let nearest = prints.min(by: {
                    Self.nearestDistance($0, to: positiveSamples)
                        > Self.nearestDistance($1, to: positiveSamples)
                }) else { return 0 }
                selected = [nearest]
            }
        } else {
            guard !positiveSamples.isEmpty else { return 0 }
            // 负反馈合影中若仍有一张脸接近布布，不能把它写成负样本。
            selected = prints.filter {
                Self.nearestDistance($0, to: positiveSamples) > Self.defaultDistanceThreshold
            }
        }
        guard !selected.isEmpty else { return 0 }
        try store.addIdentitySamples(selected, label: isChild ? 1 : -1)
        return selected.count
    }

    func match(imageData: Data) async -> ChildIdentityMatch {
        guard isEnabled,
              let samples = try? store.identitySamples(),
              samples.contains(where: { $0.label == 1 }) else {
            return ChildIdentityMatch(faceCount: 0, isLikelyChild: false, confidence: 0,
                                      nearestPositiveDistance: nil, nearestNegativeDistance: nil)
        }

        let queryPrints = await Self.faceFeaturePrints(from: imageData)
        guard !queryPrints.isEmpty else {
            return ChildIdentityMatch(faceCount: 0, isLikelyChild: false, confidence: 0,
                                      nearestPositiveDistance: nil, nearestNegativeDistance: nil)
        }

        let positive = samples.filter { $0.label == 1 }.map(\.featureData)
        let negative = samples.filter { $0.label == -1 }.map(\.featureData)
        var bestPositive: Float?
        var bestNegative: Float?

        for query in queryPrints {
            for sample in positive {
                guard let distance = Self.distance(query, sample) else { continue }
                bestPositive = min(bestPositive ?? distance, distance)
            }
            for sample in negative {
                guard let distance = Self.distance(query, sample) else { continue }
                bestNegative = min(bestNegative ?? distance, distance)
            }
        }

        let positiveDistance = bestPositive
        let clearsPositiveThreshold = positiveDistance.map { $0 <= Self.defaultDistanceThreshold } ?? false
        let clearsNegativeMargin: Bool
        if let positiveDistance, let bestNegative {
            clearsNegativeMargin = positiveDistance + Self.negativeMargin < bestNegative
        } else {
            clearsNegativeMargin = true
        }
        let likely = clearsPositiveThreshold && clearsNegativeMargin
        let confidence = positiveDistance.map {
            max(0, min(1, 1 - Double($0 / Self.defaultDistanceThreshold)))
        } ?? 0
        return ChildIdentityMatch(
            faceCount: queryPrints.count,
            isLikelyChild: likely,
            confidence: confidence,
            nearestPositiveDistance: positiveDistance,
            nearestNegativeDistance: bestNegative
        )
    }

    func clearModel() throws {
        try store.clearIdentitySamples()
        setEnabled(false)
    }

    // MARK: - Vision

    private static func faceFeaturePrints(from imageData: Data) async -> [Data] {
        await withCheckedContinuation { continuation in
            let result: [Data] = autoreleasepool {
                guard let image = downsampledCGImage(from: imageData, maxPixel: 1_600) else { return [] }
                let faceRequest = VNDetectFaceRectanglesRequest()
                let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
                guard (try? handler.perform([faceRequest])) != nil else { return [] }
                return (faceRequest.results ?? []).prefix(6).compactMap { face in
                    guard let crop = cropFace(face.boundingBox, from: image) else { return nil }
                    let printRequest = VNGenerateImageFeaturePrintRequest()
                    let printHandler = VNImageRequestHandler(cgImage: crop, orientation: .up, options: [:])
                    guard (try? printHandler.perform([printRequest])) != nil,
                          let observation = printRequest.results?.first else { return nil }
                    return try? NSKeyedArchiver.archivedData(
                        withRootObject: observation, requiringSecureCoding: true)
                }
            }
            continuation.resume(returning: result)
        }
    }

    private static func distance(_ lhsData: Data, _ rhsData: Data) -> Float? {
        guard let lhs = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: VNFeaturePrintObservation.self, from: lhsData),
              let rhs = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: VNFeaturePrintObservation.self, from: rhsData) else { return nil }
        var distance: Float = 0
        guard (try? lhs.computeDistance(&distance, to: rhs)) != nil else { return nil }
        return distance
    }

    private static func nearestDistance(_ query: Data, to samples: [Data]) -> Float {
        samples.compactMap { distance(query, $0) }.min() ?? .greatestFiniteMagnitude
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

    /// Vision 的 boundingBox 原点在左下；CGImage cropping 原点在左上。
    private static func cropFace(_ box: CGRect, from image: CGImage) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let margin: CGFloat = 0.16
        let expanded = box.insetBy(dx: -box.width * margin, dy: -box.height * margin)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let rect = CGRect(
            x: expanded.minX * width,
            y: (1 - expanded.maxY) * height,
            width: expanded.width * width,
            height: expanded.height * height
        ).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width >= 32, rect.height >= 32 else { return nil }
        return image.cropping(to: rect)
    }
}
