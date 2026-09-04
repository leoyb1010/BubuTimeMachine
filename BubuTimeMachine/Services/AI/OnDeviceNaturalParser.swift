import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - 端上自然语言解析（iOS 26 Foundation Models，R4 E-7）
/// 断网/自托管 AI 不可用时的第二道防线：用系统端上大模型把一句话解析成结构化记录。
/// 全程不出设备、免费、无 Key。设备不支持（旧机型/未开 Apple Intelligence）时返回 nil，
/// 调用方降级为纯文本时光（绝不编造数值——所有端上解析结果一律 needsConfirmation）。
///
/// 【为什么用 @Generable 而不是「让模型吐 JSON 再自己解」】
/// 旧实现是在 prompt 里描述 JSON 格式，拿到文本后剥 ```json 围栏、JSONSerialization、
/// 逐字段 best-effort 映射，解不出就返回 nil——**模型多输出一个字，整条功能就静默失效**。
/// `@Generable` 走的是约束解码：schema 在解码层面就被强制满足，拿到的直接是类型化结果，
/// 不存在「格式跑偏」这个失败模式。`.anyOf` 还能把取值域焊死，比在 prompt 里写规则可靠得多。
/// 这也让这个文件从 ~90 行降到不需要任何手写解析。
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
        你把家长记录宝宝生活的一句话拆成若干条结构化记录。
        规则：
        1. 句子里没有出现的数值绝对不要填，宁可留空。
        2. 拿不准属于哪一类，就用 timeline，把原文放进 note。
        3. title 是给家长看的简短标题，不超过 12 个字。
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: request.text, generating: ParsedBatch.self)
            return Self.convert(response.content, sourceText: request.text)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(FoundationModels)

    /// 端上模型的输出契约。取值域用 `.anyOf` 焊死，不靠 prompt 自觉。
    @available(iOS 26.0, *)
    @Generable
    struct ParsedRecord {
        @Guide(description: "这条记录属于哪一类",
               .anyOf(["water", "meal", "sleep", "symptom", "growth", "vaccine", "first_time", "timeline"]))
        var domain: String

        @Guide(description: "给家长看的简短标题，不超过 12 个字")
        var title: String

        @Guide(description: "原文里与这条记录相关的部分；没有就留空")
        var note: String?

        @Guide(description: "喝水/喝奶的毫升数。句子里没有明确说就留空，不要估算")
        var amountML: Int?

        @Guide(description: "身高厘米数。句子里没有明确说就留空")
        var heightCM: Double?

        @Guide(description: "体重公斤数。句子里没有明确说就留空")
        var weightKG: Double?

        @Guide(description: "体温摄氏度。句子里没有明确说就留空")
        var temperatureCelsius: Double?

        @Guide(description: "吃了哪些食物；句子里没提就留空数组")
        var foodItems: [String]

        @Guide(description: "疫苗名称。句子里没有明确说就留空")
        var vaccineName: String?
    }

    @available(iOS 26.0, *)
    @Generable
    struct ParsedBatch {
        @Guide(description: "从这句话里拆出的记录，最多 5 条", .count(1...5))
        var items: [ParsedRecord]
    }

    /// 把类型化结果搬进产品自己的 DTO。没有解析、没有容错分支——
    /// 约束解码已经保证了结构，这里只是换个壳。
    @available(iOS 26.0, *)
    private static func convert(_ batch: ParsedBatch, sourceText: String) -> NaturalCaptureResult? {
        let items: [NaturalCaptureItem] = batch.items.compactMap { record in
            guard let domain = NaturalCaptureDomain(rawValue: record.domain) else { return nil }
            var fields: [String: JSONValue] = [:]
            if let ml = record.amountML { fields["amount_ml"] = .number(Double(ml)) }
            if let h = record.heightCM { fields["height_cm"] = .number(h) }
            if let w = record.weightKG { fields["weight_kg"] = .number(w) }
            if let t = record.temperatureCelsius { fields["temperature_celsius"] = .number(t) }
            if !record.foodItems.isEmpty {
                fields["food_items"] = .array(record.foodItems.map { .string($0) })
            }
            if let vaccine = record.vaccineName, !vaccine.isEmpty {
                fields["vaccine_name"] = .string(vaccine)
            }
            let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return NaturalCaptureItem(
                domain: domain,
                action: .create,
                title: title.isEmpty ? String(sourceText.prefix(12)) : title,
                note: record.note?.isEmpty == false ? record.note : sourceText,
                date: .now,
                fields: fields,
                tags: [],
                confidence: 0.7,
                // 端上解析一律让家长确认：数值错了改一下就好，写错事实是不可接受的。
                needsConfirmation: true,
                sourceText: sourceText)
        }
        guard !items.isEmpty else { return nil }
        return NaturalCaptureResult(confidence: 0.7, items: items, warnings: ["on_device_parse"])
    }
    #endif
}
