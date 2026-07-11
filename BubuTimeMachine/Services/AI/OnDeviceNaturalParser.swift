import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - 端上自然语言解析（iOS 26 Foundation Models，R4 E-7）
/// 断网/自托管 AI 不可用时的第二道防线：用系统端上大模型把一句话解析成结构化记录。
/// 全程不出设备、免费、无 Key。设备不支持（旧机型/未开 Apple Intelligence）时返回 nil，
/// 调用方降级为纯文本时光（绝不编造数值——所有端上解析结果一律 needsConfirmation）。
@MainActor
enum OnDeviceNaturalParser {

    /// 端上模型是否可用。
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// 解析一句话。失败/不可用返回 nil。
    static func parse(_ request: NaturalCaptureRequest) async -> NaturalCaptureResult? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), isAvailable else { return nil }
        let instructions = """
        你把家长记录宝宝生活的一句话解析成 JSON 数组。只输出 JSON，不要任何其他文字。
        每个元素：{"domain":"water|meal|sleep|symptom|growth|vaccine|first_time|timeline",
        "title":"简短标题","note":"原文相关部分或null",
        "fields":{可选，仅当句子明确给出数值：amount_ml(数字),height_cm(数字),weight_kg(数字),
        temperature_celsius(数字),food_items(字符串数组),vaccine_name(字符串)}}
        规则：句子里没有的数值绝不编造；拿不准就用 domain=timeline 原文保底。
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: request.text)
            return Self.decode(response.content, sourceText: request.text)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// 宽容解码：剥掉 ```json 围栏，逐项 best-effort 映射；解不出返回 nil。
    private static func decode(_ raw: String, sourceText: String) -> NaturalCaptureResult? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]") {
            text = String(text[start...end])
        }
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !array.isEmpty else { return nil }

        var items: [NaturalCaptureItem] = []
        for obj in array {
            guard let domainRaw = obj["domain"] as? String,
                  let domain = NaturalCaptureDomain(rawValue: domainRaw) else { continue }
            var fields: [String: JSONValue] = [:]
            if let f = obj["fields"] as? [String: Any] {
                for (k, v) in f {
                    if let n = v as? Double { fields[k] = .number(n) }
                    else if let n = v as? Int { fields[k] = .number(Double(n)) }
                    else if let s = v as? String { fields[k] = .string(s) }
                    else if let a = v as? [String] { fields[k] = .array(a.map { .string($0) }) }
                }
            }
            let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespaces)
            items.append(NaturalCaptureItem(
                domain: domain, action: .create,
                title: (title?.isEmpty == false ? title! : String(sourceText.prefix(12))),
                note: obj["note"] as? String ?? sourceText,
                date: .now, fields: fields, tags: [],
                confidence: 0.7,
                needsConfirmation: true,   // 端上解析一律让家长确认，数值错了改一下就好
                sourceText: sourceText))
        }
        guard !items.isEmpty else { return nil }
        return NaturalCaptureResult(confidence: 0.7, items: items, warnings: ["on_device_parse"])
    }
}
