import Foundation
import ImageIO
import CoreLocation
import MapKit
import Vision
import UIKit

// MARK: - 图片分析结果
struct PhotoAnalysis: Sendable {
    var captureDate: Date?            // EXIF 拍摄时间
    var latitude: Double?
    var longitude: Double?
    var locationName: String?        // 反向地理编码地名
    var tags: [String]               // Vision 场景/物体标签
    var faceCount: Int               // 人脸数量
}

// MARK: - 端侧图片分析器
/// 全部端侧、零后端、隐私至上：
/// - EXIF：拍摄时间 + GPS 坐标
    /// - MapKit：坐标 → 地名（如"上海市·静安区"）
/// - Vision：场景/物体分类 + 人脸计数 → 自动标签
/// 离线时 EXIF 与 Vision 仍可用；地名需联网（失败则跳过，不影响主流程）。
struct PhotoAnalyzer: Sendable {

    /// 分析一张图片的原始数据。
    func analyze(imageData: Data, includeLocation: Bool = true) async -> PhotoAnalysis {
        var result = PhotoAnalysis(captureDate: nil, latitude: nil, longitude: nil,
                                   locationName: nil, tags: [], faceCount: 0)

        // 1) EXIF：时间 + GPS
        if let source = CGImageSourceCreateWithData(imageData as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            result.captureDate = Self.exifDate(from: props)
            if includeLocation, let (lat, lon) = Self.gpsCoordinate(from: props) {
                result.latitude = lat
                result.longitude = lon
            }
        }

        // 2) Vision：标签 + 人脸（端侧）
        if let cgImage = UIImage(data: imageData)?.cgImage {
            async let tags = Self.classify(cgImage: cgImage)
            async let faces = Self.countFaces(cgImage: cgImage)
            result.tags = await tags
            result.faceCount = await faces
        }

        // 3) 反向地理编码（需联网，失败静默）
        if let lat = result.latitude, let lon = result.longitude {
            result.locationName = await Self.reverseGeocode(lat: lat, lon: lon)
        }

        // 人脸数转成温暖标签
        if result.faceCount == 1 { result.tags.append("独照") }
        else if result.faceCount >= 2 { result.tags.append("合影") }

        return result
    }

    // MARK: EXIF

    private static func exifDate(from props: [CFString: Any]) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let str = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
           let date = formatter.date(from: str) {
            return date
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let str = tiff[kCGImagePropertyTIFFDateTime] as? String,
           let date = formatter.date(from: str) {
            return date
        }
        return nil
    }

    private static func gpsCoordinate(from props: [CFString: Any]) -> (Double, Double)? {
        guard let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lon = gps[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
        let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
        let signedLat = latRef == "S" ? -lat : lat
        let signedLon = lonRef == "W" ? -lon : lon
        return (signedLat, signedLon)
    }

    // MARK: Vision

    private static func classify(cgImage: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                let observations = (request.results ?? [])
                    .filter { $0.confidence > 0.6 }
                    .prefix(4)
                    .map { Self.localizedTag($0.identifier) }
                continuation.resume(returning: Array(Set(observations)))
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    private static func countFaces(cgImage: CGImage) async -> Int {
        await withCheckedContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                continuation.resume(returning: request.results?.count ?? 0)
            } catch {
                continuation.resume(returning: 0)
            }
        }
    }

    /// 将 Vision 英文标识符映射为温暖中文标签（常见育儿场景）。
    private static func localizedTag(_ identifier: String) -> String {
        let map: [String: String] = [
            "baby": "宝宝", "child": "孩子", "people": "人物", "portrait": "人像",
            "smile": "笑容", "food": "美食", "meal": "吃饭", "fruit": "水果",
            "cake": "蛋糕", "toy": "玩具", "dog": "狗狗", "cat": "猫咪",
            "animal": "小动物", "flower": "花", "plant": "植物", "tree": "树",
            "beach": "海边", "sea": "大海", "water": "水", "snow": "雪",
            "park": "公园", "grass": "草地", "sky": "天空", "outdoor": "户外",
            "indoor": "室内", "room": "房间", "bed": "床上", "sleep": "睡觉",
            "book": "看书", "car": "汽车", "vehicle": "车", "sunset": "夕阳",
            "night": "夜晚", "birthday": "生日", "celebration": "庆祝",
            "clothing": "穿搭", "hat": "帽子", "festival": "节日",
        ]
        for (k, v) in map where identifier.lowercased().contains(k) {
            return v
        }
        return identifier
    }

    // MARK: 地理编码

    private static func reverseGeocode(lat: Double, lon: Double) async -> String? {
        let location = CLLocation(latitude: lat, longitude: lon)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        request.preferredLocale = Locale(identifier: "zh_Hans_CN")
        guard let item = try? await request.mapItems.first else { return nil }
        let representations = item.addressRepresentations
        let candidates = [
            item.address?.shortAddress,
            representations?.cityName,
            representations?.cityWithContext,
            item.name,
            item.address?.fullAddress,
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
