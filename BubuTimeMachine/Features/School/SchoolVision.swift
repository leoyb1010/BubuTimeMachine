import Foundation
import ImageIO
import UIKit

nonisolated final class SchoolVisionRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

nonisolated enum SchoolVisionError: LocalizedError {
    case invalidResponse, invalidImage
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "识别结果不完整，原图仍保留，可以重试。"
        case .invalidImage: "无法读取这张图片，请选择清晰完整的亲子桥原图。"
        }
    }
}

nonisolated struct SchoolVisionResult: Decodable, Sendable {
    let isSchoolReport: Bool
    let date: String?
    let fields: [String: String]
    let uncertainFields: [String]
    let model: String
    enum CodingKeys: String, CodingKey {
        case isSchoolReport = "is_school_report", uncertainFields = "uncertain_fields"
        case date, fields, model
    }
    func report(sourceHash: String) throws -> SchoolDailyReport {
        let allowed = Set(SchoolReportField.allCases.map(\.rawValue))
        guard isSchoolReport, model == "deepseek-flash", fields.count <= allowed.count,
              uncertainFields.count <= allowed.count + 1,
              uncertainFields.allSatisfy({ allowed.contains($0) || $0 == "日期" }),
              fields.allSatisfy({ allowed.contains($0.key) && $0.value.count <= 1000 && !$0.value.contains("【亲子桥") }) else {
            throw SchoolVisionError.invalidResponse
        }
        var report = SchoolDailyReport()
        report.sourceHash = sourceHash
        report.recognitionModel = model
        report.candidates = fields.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for field in SchoolReportField.meals {
            if let value = report.candidates[field.rawValue] { report.candidates[field.rawValue] = SchoolMeal(value).text }
        }
        report.reviewNotes = uncertainFields.isEmpty ? nil : uncertainFields.map { $0 + "识别不确定，可稍后修改" }
        if let date {
            guard date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { throw SchoolVisionError.invalidResponse }
            let pieces = date.split(separator: "-")
            guard let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]),
                  (1...12).contains(month), (1...31).contains(day) else { throw SchoolVisionError.invalidResponse }
            report.dateEvidence = "\(year)年\(month)月\(day)日"
        }
        report.adoptRecognizedValues()
        return report
    }
}

nonisolated enum SchoolVisionImage {
    /// Only the explicitly selected report is sent; a fresh JPEG drops location/EXIF metadata.
    static func data(from url: URL) async throws -> Data {
        try await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2400
                  ] as CFDictionary),
                  let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.94), data.count <= 8 * 1024 * 1024 else {
                throw SchoolVisionError.invalidImage
            }
            return data
        }.value
    }
}

/// A non-secret, one-shot setup receipt installed only on the owner's authorized devices.
/// It never contains a provider key or changes where authenticated requests are sent.
nonisolated enum SchoolVisionSetup {
    private struct Receipt: Decodable { let version: Int; let enabled: Bool; let service: String }
    static func enabled(in data: Data, expectedService: String) -> Bool? {
        guard data.count <= 4096, let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
              receipt.version == 1, let actual = URL(string: receipt.service), let expected = URL(string: expectedService),
              actual.scheme == "https", actual == expected else { return nil }
        return receipt.enabled
    }
}
