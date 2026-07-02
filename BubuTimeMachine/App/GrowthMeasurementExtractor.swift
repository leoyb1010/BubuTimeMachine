import Foundation

// MARK: - 旧健康记录 -> 结构化成长数据提取
/// 放在 App 共享层，供主 App 和 Widget extension 共用。
nonisolated enum GrowthMeasurementExtractor {
    enum Metric {
        case height
        case weight
        case head
    }

    struct Values: Equatable {
        var heightCm: Double?
        var weightKg: Double?
        var headCircumferenceCm: Double?

        var isEmpty: Bool {
            heightCm == nil && weightKg == nil && headCircumferenceCm == nil
        }

        func value(for metric: Metric) -> Double? {
            switch metric {
            case .height: heightCm
            case .weight: weightKg
            case .head: headCircumferenceCm
            }
        }
    }

    static func values(from record: HealthRecord) -> Values {
        let text = searchText(for: record)
        var values = Values()

        values.heightCm = explicitMetricValue(
            keywords: ["身高", "身长"],
            unitVariants: ["cm", "CM", "厘米", "公分"],
            in: text,
            convert: { $0 },
            range: 30...150
        )
        values.weightKg = explicitMetricValue(
            keywords: ["体重"],
            unitVariants: ["kg", "KG", "公斤", "千克", "斤"],
            in: text,
            convert: { value, unit in unit == "斤" ? value / 2 : value },
            range: 1...60
        )
        values.headCircumferenceCm = explicitMetricValue(
            keywords: ["头围"],
            unitVariants: ["cm", "CM", "厘米", "公分"],
            in: text,
            convert: { $0 },
            range: 20...70
        )

        if let amountValue = record.amountValue,
           let amountUnit = record.amountUnit {
            applyAmountValue(amountValue, unit: amountUnit, record: record, text: text, into: &values)
        }

        if record.kind == .checkup {
            if values.weightKg == nil,
               let kg = unitValue(unitVariants: ["kg", "KG", "公斤", "千克"], in: text, range: 1...60) {
                values.weightKg = kg
            } else if values.weightKg == nil,
                      let jin = unitValue(unitVariants: ["斤"], in: text, range: 2...120) {
                values.weightKg = jin / 2
            }

            if values.headCircumferenceCm == nil,
               text.contains("头围"),
               let head = unitValue(unitVariants: ["cm", "CM", "厘米", "公分"], in: text, range: 20...70) {
                values.headCircumferenceCm = head
            }

            if values.heightCm == nil,
               let height = unitValue(unitVariants: ["cm", "CM", "厘米", "公分"], in: text, range: 30...150) {
                values.heightCm = height
            }
        }

        return values
    }

    static func value(_ metric: Metric, from record: HealthRecord) -> Double? {
        values(from: record).value(for: metric)
    }

    private static func searchText(for record: HealthRecord) -> String {
        ([record.title, record.amountText, record.detail].compactMap { $0 } + record.tags)
            .joined(separator: " ")
    }

    private static func explicitMetricValue(
        keywords: [String],
        unitVariants: [String],
        in text: String,
        convert: (Double) -> Double,
        range: ClosedRange<Double>
    ) -> Double? {
        explicitMetricValue(
            keywords: keywords,
            unitVariants: unitVariants,
            in: text,
            convert: { value, _ in convert(value) },
            range: range
        )
    }

    private static func explicitMetricValue(
        keywords: [String],
        unitVariants: [String],
        in text: String,
        convert: (Double, String?) -> Double,
        range: ClosedRange<Double>
    ) -> Double? {
        let keywordPattern = keywords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let unitPattern = unitVariants.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let patterns = [
            #"(?i)(?:\#(keywordPattern))\s*(?:约|大约)?\s*[:：=]?\s*(\d+(?:\.\d+)?)\s*(\#(unitPattern))?"#,
            #"(?i)(\d+(?:\.\d+)?)\s*(\#(unitPattern))\s*(?:\#(keywordPattern))"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let textRange = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: textRange),
                  let numberRange = Range(match.range(at: 1), in: text),
                  let raw = Double(text[numberRange]) else { continue }
            let unit: String?
            if match.numberOfRanges > 2,
               let unitRange = Range(match.range(at: 2), in: text) {
                unit = String(text[unitRange])
            } else {
                unit = nil
            }
            let value = convert(raw, unit)
            guard range.contains(value) else { continue }
            return value
        }
        return nil
    }

    private static func unitValue(unitVariants: [String], in text: String, range: ClosedRange<Double>) -> Double? {
        let unitPattern = unitVariants.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let pattern = #"(?i)(\d+(?:\.\d+)?)\s*(\#(unitPattern))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let numberRange = Range(match.range(at: 1), in: text),
                  let value = Double(text[numberRange]),
                  range.contains(value) else { continue }
            return value
        }
        return nil
    }

    private static func applyAmountValue(
        _ value: Double,
        unit: String,
        record: HealthRecord,
        text: String,
        into values: inout Values
    ) {
        let normalizedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalizedUnit {
        case "kg", "KG", "公斤", "千克":
            if values.weightKg == nil,
               (text.contains("体重") || record.kind == .checkup),
               (1...60).contains(value) {
                values.weightKg = value
            }
        case "斤":
            let kg = value / 2
            if values.weightKg == nil,
               (text.contains("体重") || record.kind == .checkup),
               (1...60).contains(kg) {
                values.weightKg = kg
            }
        case "cm", "CM", "厘米", "公分":
            if text.contains("头围"),
               values.headCircumferenceCm == nil,
               (20...70).contains(value) {
                values.headCircumferenceCm = value
            } else if values.heightCm == nil,
                      (text.contains("身高") || text.contains("身长") || record.kind == .checkup),
                      (30...150).contains(value) {
                values.heightCm = value
            }
        default:
            break
        }
    }
}
