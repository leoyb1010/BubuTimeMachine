import Foundation

/// Map printed row anchors and verified checkbox ink into the existing daily-report fields.
nonisolated enum SchoolReportReading {
    static func addDetails(_ lines: [SchoolOCRLine], to report: inout SchoolDailyReport) {
        func near(_ title: String) -> [SchoolOCRLine] {
            guard let heading = lines.first(where: { $0.text.replacingOccurrences(of: " ", with: "").contains(title) }) else { return [] }
            return lines.filter { abs($0.y - heading.y) < max(0.012, heading.height * 0.8) }
        }
        func chosen(_ field: SchoolReportField, rows: [SchoolOCRLine], choices: [String], multiple: Bool = false) {
            let selected = Array(Set(rows.flatMap(\.checkedOptions).filter { choices.contains($0) })).sorted()
            if !selected.isEmpty && (multiple || selected.count == 1) {
                report.candidates[field.rawValue] = selected.joined(separator: "；")
            }
        }
        chosen(.napQuality, rows: lines, choices: SchoolReportField.napQuality.choices)
        chosen(.bowel, rows: lines, choices: ["没有排便"])
        chosen(.health, rows: near("身体状况"), choices: SchoolReportField.health.choices, multiple: true)
        if let health = report.candidates[SchoolReportField.health.rawValue], health.contains("健康；") || health.contains("；健康") {
            report.candidates.removeValue(forKey: SchoolReportField.health.rawValue)
            addReview("身体状况的勾选有冲突，以原图为准", to: &report)
        }
        chosen(.appearance, rows: lines, choices: ["整洁良好", "有受伤"], multiple: true)
        chosen(.mood, rows: near("精神"), choices: SchoolReportField.mood.choices)
        chosen(.participation, rows: near("参与度"), choices: ["主动", "被动", "较无积极参与"])
        chosen(.peers, rows: near("同伴互动"), choices: SchoolReportField.peers.choices)
        chosen(.supplies, rows: lines, choices: SchoolReportField.supplies.choices, multiple: true)

        // Literal handwritten evidence is filled too, but uncertain times must not produce a false duration.
        if let line = lines.first(where: { $0.text.contains("时") && groups(#"(\d{1,2})\s*时\s*(\d{1,2})\s*分.*?(\d{1,2})\s*时\s*(\d{1,2})\s*分"#, $0.text).count == 4 }) {
            let parts = groups(#"(\d{1,2})\s*时\s*(\d{1,2})\s*分.*?(\d{1,2})\s*时\s*(\d{1,2})\s*分"#, line.text)
            let range = "\(parts[0]):\(parts[1])–\(parts[2]):\(parts[3])"
            if SchoolVisualValue.nap(range) != nil {
                report.candidates[SchoolReportField.nap.rawValue] = range + (line.confidence < 0.8 ? "（时间待核对）" : "")
                if line.confidence < 0.8 { addReview("午睡手写时间可能误读", to: &report) }
            }
        }
        for (index, field) in [SchoolReportField.milkFirst, .milkSecond].enumerated() {
            guard let anchor = lines.first(where: { $0.text.range(of: "^\(index + 1)[、，,.．]", options: .regularExpression) != nil }) else { continue }
            let rows = lines.filter { abs($0.y - anchor.y) < max(0.010, anchor.height * 0.65) }.sorted { $0.x < $1.x }
            let raw = rows.map(\.text).joined(separator: " ")
            let selected = Set(rows.flatMap(\.checkedOptions))
            let milk = ["母奶", "牛奶"].filter { selected.contains($0) }
            guard milk.count == 1 else { continue }
            var parts = [milk[0]]
            let volume = groups(milk[0] + #"\s*(\d{1,4})\s*m[lI！!]"#, raw)
            if let amount = volume.first, let n = Int(amount), n > 0, n <= 1000 {
                parts[0] += " \(amount)ml（奶量待核对）"
                addReview("\(field.rawValue)的手写奶量", to: &report)
            }
            if selected.contains("喝完") && !selected.contains("没喝完") { parts.append("喝完") }
            if selected.contains("没喝完") && !selected.contains("喝完") { parts.append("没喝完") }
            let time = groups(#"(\d{1,2})\s*时\s*(\d{1,2})\s*分"#, raw)
            if time.count == 2, let hour = Int(time[0]), let minute = Int(time[1]), hour < 24, minute < 60 {
                parts.insert(String(format: "%02d:%02d（时间待核对）", hour, minute), at: 0)
                addReview("\(field.rawValue)的手写时间", to: &report)
            }
            report.candidates[field.rawValue] = parts.joined(separator: "；")
        }
    }

    /// A missing/misread year can use the selected record year's context, always explicitly labelled.
    static func date(from evidence: String, relativeTo reference: Date) -> (date: Date, inferredYear: Bool)? {
        let parts = groups(#"(\d{2,4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日"#, evidence)
        guard parts.count == 3, let rawYear = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        let calendar = Calendar.current
        let referenceYear = calendar.component(.year, from: reference)
        let inferred = rawYear < 2000 || rawYear > referenceYear
        let year = inferred ? referenceYear : rawYear
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.month, from: date) == month, calendar.component(.day, from: date) == day,
              date <= calendar.startOfDay(for: reference) else { return nil }
        return (date, inferred)
    }

    static func addReview(_ note: String, to report: inout SchoolDailyReport) {
        if report.reviewNotes == nil { report.reviewNotes = [] }
        if report.reviewNotes?.contains(note) != true { report.reviewNotes?.append(note) }
    }
    private static func groups(_ pattern: String, _ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return [] }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }
}
