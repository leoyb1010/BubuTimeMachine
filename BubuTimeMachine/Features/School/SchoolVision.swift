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
    /// Server-side readers whose output counts as a full cloud reading. "deepseek-flash" stays
    /// valid for records read before 2.31, when 亲子桥 moved to the second brain's Gemini.
    static func cloudName(_ model: String?) -> String? {
        switch model {
        case "gemini-3.8-flash": "Gemini"
        case "deepseek-flash": "DeepSeek"
        default: nil
        }
    }
    func report(sourceHash: String) throws -> SchoolDailyReport {
        let allowed = Set(SchoolReportField.allCases.map(\.rawValue))
        guard isSchoolReport, Self.cloudName(model) != nil, fields.count <= allowed.count,
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

/// One-shot owner provisioning. Version 2 carries only a report-scoped family-server token,
/// never the provider key or a credential granting access to family memories.
nonisolated enum SchoolVisionSetup {
    static let credentialKey = "bubu.school.vision.credential"
    private struct Receipt: Decodable { let version: Int; let enabled: Bool; let service: String; let token: String? }
    static func canUseCredential(_ token: String, service: URL, expectedService: String) -> Bool {
        !token.isEmpty && service.scheme == "https" && service == URL(string: expectedService)
    }
    static func credential(in data: Data, expectedService: String) -> String? {
        guard enabled(in: data, expectedService: expectedService) == true,
              let receipt = try? JSONDecoder().decode(Receipt.self, from: data), receipt.version == 2,
              let token = receipt.token, (32...256).contains(token.count),
              token.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { return nil }
        return token
    }
    static func enabled(in data: Data, expectedService: String) -> Bool? {
        guard data.count <= 4096, let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
              [1, 2].contains(receipt.version), let actual = URL(string: receipt.service), let expected = URL(string: expectedService),
              actual.scheme == "https", actual == expected else { return nil }
        return receipt.enabled
    }
}

extension SchoolDailyReport {
    /// Recognition may fill gaps, never erase a parent's correction or another section.
    /// Exception: in an unreviewed on-device OCR reading, cells the cloud read are overwritten (except
    /// fields a parent edited), since OCR misreads would otherwise win forever. Returns whether that happened,
    /// so the caller can also take the cloud-read date.
    @discardableResult
    nonisolated mutating func mergeMissing(from incoming: SchoolDailyReport) -> Bool {
        let wasConfirmed = confirmed
        let priorValues = values
        let replacesOCR = !confirmed && SchoolVisionResult.cloudName(recognitionModel) == nil
            && SchoolVisionResult.cloudName(incoming.recognitionModel) != nil
        if replacesOCR {
            // Cloud wins where it read something; a cell it left blank keeps the OCR value.
            let kept = Set(manuallyEditedFields ?? [])
            values = values.filter { kept.contains($0.key) || incoming.values[$0.key]?.isEmpty != false }
        }
        candidates = incoming.values
        adoptRecognizedValues()
        recognitionModel = incoming.recognitionModel
        reviewNotes = incoming.reviewNotes
        if sourceHash == nil { sourceHash = incoming.sourceHash }
        if dateEvidence.isEmpty { dateEvidence = incoming.dateEvidence }
        confirmed = wasConfirmed && values == priorValues
        return replacesOCR
    }
}
