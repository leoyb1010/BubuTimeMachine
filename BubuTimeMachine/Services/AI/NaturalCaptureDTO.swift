import Foundation

// MARK: - 自然语言记录 解析 DTO
// 与 server/ai 的 /parse-natural-capture 对齐。写法与 DTOs.swift 保持一致（plain struct + Codable + Sendable）。

struct NaturalCaptureRequest: Codable, Sendable {
    let text: String
    let childName: String
    let timezone: String
    let referenceDate: Date
}

struct NaturalCaptureResult: Codable, Sendable {
    var confidence: Double
    var items: [NaturalCaptureItem]
    var warnings: [String]
}

struct NaturalCaptureItem: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var domain: NaturalCaptureDomain
    var action: NaturalCaptureAction
    var title: String
    var note: String?
    var date: Date?
    var fields: [String: JSONValue]
    var tags: [String]
    var confidence: Double
    var needsConfirmation: Bool
    var sourceText: String

    enum CodingKeys: String, CodingKey {
        case domain, action, title, note, date, fields, tags, confidence
        case needsConfirmation = "needs_confirmation"
        case sourceText = "source_text"
    }
}

extension NaturalCaptureItem {
    /// App 端兜底：不完全相信 LLM。敏感 domain / 低置信度必须人工确认后才能入库。
    var requiresHardConfirmation: Bool {
        if needsConfirmation { return true }
        if confidence < 0.82 { return true }
        switch domain {
        case .vaccine, .symptom, .supplement:
            return true
        default:
            return false
        }
    }
}

enum NaturalCaptureDomain: String, Codable, Sendable, CaseIterable {
    case vaccine
    case growth
    case meal
    case snack
    case supplement
    case water
    case sleep
    case symptom
    case checkup
    case timeline
    case milestone
    case firstTime = "first_time"
    case unknown

    /// 解析失败/未知值时落到 unknown，不让一条坏数据毁掉整次解析。
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NaturalCaptureDomain(rawValue: raw) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .vaccine: return "疫苗"
        case .growth: return "身高体重"
        case .meal: return "餐食"
        case .snack: return "零食"
        case .supplement: return "营养补充"
        case .water: return "喝水"
        case .sleep: return "睡眠"
        case .symptom: return "不舒服"
        case .checkup: return "体检护理"
        case .timeline: return "时光记录"
        case .milestone: return "里程碑"
        case .firstTime: return "第一次"
        case .unknown: return "待分类"
        }
    }

    var icon: String {
        switch self {
        case .vaccine: return "syringe"
        case .growth: return "ruler"
        case .meal: return "fork.knife"
        case .snack: return "takeoutbag.and.cup.and.straw"
        case .supplement: return "pills"
        case .water: return "drop.fill"
        case .sleep: return "moon.zzz.fill"
        case .symptom: return "cross.case.fill"
        case .checkup: return "stethoscope"
        case .timeline: return "sparkles"
        case .milestone: return "star.fill"
        case .firstTime: return "party.popper"
        case .unknown: return "questionmark.circle"
        }
    }
}

enum NaturalCaptureAction: String, Codable, Sendable {
    case create
    case update
    case complete

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NaturalCaptureAction(rawValue: raw) ?? .create
    }
}

enum JSONValue: Codable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) -> String? {
        if case .string(let value)? = self[key] { return value }
        return nil
    }

    func double(_ key: String) -> Double? {
        if case .number(let value)? = self[key] { return value }
        if case .string(let value)? = self[key] { return Double(value) }
        return nil
    }

    func stringArray(_ key: String) -> [String] {
        guard case .array(let values)? = self[key] else { return [] }
        return values.compactMap {
            if case .string(let value) = $0 { return value }
            return nil
        }
    }

    func isoDate(_ key: String) -> Date? {
        guard let raw = string(key) else { return nil }
        return NaturalCaptureCoding.parseDate(raw)
    }
}

// MARK: - 容错编解码
enum NaturalCaptureCoding {
    /// ISO8601 容错解析：先标准互联网时间，再带小数秒重试。
    /// 服务端 pydantic 序列化偶发带微秒时，客户端不再整包解析失败。
    static func parseDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }

    /// /parse-natural-capture 响应解码器（日期容错）。
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parseDate(raw) else {
                throw DecodingError.dataCorruptedError(in: container,
                                                       debugDescription: "无法解析日期：\(raw)")
            }
            return date
        }
        return decoder
    }
}
