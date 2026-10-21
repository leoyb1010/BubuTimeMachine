import Foundation

nonisolated struct MediaAnalysisDTO: Codable, Sendable {
    var mediaID: String
    let contentHash: String?
    let state: String
    let revision: Int?
    let provider: String?
    let descriptionText: String
    let ocr: String
    let tags: [String]
    let segments: [Segment]
    let warnings: [String]
    let updatedAt: String?

    nonisolated struct Segment: Codable, Sendable {
        let id: String?
        let start: Double?
        let end: Double?
        let text: String
        enum CodingKeys: String, CodingKey { case id, start, end, text }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id)
            start = try c.decodeIfPresent(Double.self, forKey: .start)
            end = try c.decodeIfPresent(Double.self, forKey: .end)
            text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        }
    }
    enum CodingKeys: String, CodingKey {
        case mediaID = "media_id", contentHash = "content_hash", state, revision, provider
        case descriptionText = "description", ocr, tags, segments, warnings, updatedAt = "updated_at"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mediaID = try c.decodeIfPresent(String.self, forKey: .mediaID) ?? ""
        contentHash = try c.decodeIfPresent(String.self, forKey: .contentHash)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "unavailable"
        revision = try c.decodeIfPresent(Int.self, forKey: .revision)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        descriptionText = try c.decodeIfPresent(String.self, forKey: .descriptionText) ?? ""
        ocr = try c.decodeIfPresent(String.self, forKey: .ocr) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        segments = try c.decodeIfPresent([Segment].self, forKey: .segments) ?? []
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}
