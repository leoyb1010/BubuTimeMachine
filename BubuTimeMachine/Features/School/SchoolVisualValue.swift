import Foundation

/// Display-only interpretations. Never overwrite the original confirmed text.
nonisolated enum SchoolVisualValue {
    struct Nap: Equatable, Sendable {
        let start: String
        let end: String
        let minutes: Int
        var duration: String {
            if minutes < 60 { return "\(minutes)分钟" }
            let remainder = minutes % 60
            return "\(minutes / 60)小时" + (remainder == 0 ? "" : "\(remainder)分")
        }
    }
    static func fraction(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "％", with: "%")
        guard value.range(of: #"^\d{1,3}(?:\.\d+)?\s*%$"#, options: .regularExpression) != nil,
              let number = Double(value.dropLast().trimmingCharacters(in: .whitespaces)), (0...100).contains(number) else { return nil }
        return number / 100
    }
    static func nap(_ raw: String) -> Nap? {
        let pattern = #"^\s*(\d{1,2})(?:[:：]|时)\s*(\d{1,2})分?\s*[-–—~～至到]\s*(\d{1,2})(?:[:：]|时)\s*(\d{1,2})分?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) else { return nil }
        let numbers = (1...4).compactMap { index -> Int? in
            guard let range = Range(match.range(at: index), in: raw) else { return nil }
            return Int(raw[range])
        }
        guard numbers.count == 4, numbers[0] < 24, numbers[2] < 24, numbers[1] < 60, numbers[3] < 60 else { return nil }
        let duration = numbers[2] * 60 + numbers[3] - numbers[0] * 60 - numbers[1]
        guard duration > 0, duration <= 12 * 60 else { return nil }
        return Nap(start: String(format: "%02d:%02d", numbers[0], numbers[1]),
                   end: String(format: "%02d:%02d", numbers[2], numbers[3]), minutes: duration)
    }
}
