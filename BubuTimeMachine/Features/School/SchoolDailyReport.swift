import Foundation

nonisolated enum SchoolReportField: String, CaseIterable, Codable, Sendable {
    case reportedName = "表上姓名", reportedAge = "表上年龄"
    case milk = "喝奶"
    case milkFirst = "第1次喝奶", milkSecond = "第2次喝奶"
    case morningSnack = "上午点心", lunch = "中午午餐", fruit = "水果", afternoonSnack = "下午点心"
    case nap = "午睡时间", napQuality = "睡眠品质"
    case temperatureAM = "早上体温", temperatureNoon = "中午体温", temperaturePM = "晚上体温"
    case bowel = "排便", health = "身体状况", appearance = "身体外观"
    case bowelFirst = "第1次排便", bowelSecond = "第2次排便", bowelThird = "第3次排便"
    case injury = "受伤部位与情形", appearanceOther = "其他外观情况"
    case mood = "精神", participation = "参与度", peers = "同伴互动", notice = "特别叮嘱"
    case specialBehavior = "特殊行为", supplies = "准备物品"

    static let meals: [Self] = [.morningSnack, .lunch, .fruit, .afternoonSnack]
    static let sections: [(title: String, symbol: String, fields: [Self])] = [
        ("一天四餐", "fork.knife", [.morningSnack, .lunch, .fruit, .afternoonSnack]),
        ("喝奶记录", "waterbottle", [.milkFirst, .milkSecond, .milk]),
        ("睡眠", "moon.zzz.fill", [.nap, .napQuality]),
        ("体温与排便", "heart.text.clipboard", [.temperatureAM, .temperatureNoon, .temperaturePM, .bowel, .bowelFirst, .bowelSecond, .bowelThird]),
        ("身体与外观", "figure.child", [.health, .appearance, .injury, .appearanceOther]),
        ("在园表现", "face.smiling", [.mood, .participation, .peers, .specialBehavior]),
        ("老师叮嘱", "backpack", [.supplies, .notice]),
        ("表上基本信息", "person.text.rectangle", [.reportedName, .reportedAge])
    ]
    var prompt: String {
        switch self {
        case .morningSnack, .lunch, .fruit, .afternoonSnack: "如 90%；食量佳；速度普通"
        case .milk: "补充说明（旧记录也保留在这里）"
        case .milkFirst, .milkSecond: "时间；母奶/牛奶及毫升数；喝完/没喝完；剩余毫升数"
        case .nap: "核对原图中的开始和结束时间"
        case .temperatureAM, .temperatureNoon, .temperaturePM: "如 36.6°C，没记录就留空"
        case .notice: "老师请准备的物品或特别提醒"
        case .bowelFirst, .bowelSecond, .bowelThird: "时间；便量（正常/多/少）；状况（正常/硬/稀）；颜色"
        case .injury, .appearanceOther: "部位及具体情形，没填写就留空"
        case .reportedName: "表上填写的名字，没写就留空"
        case .reportedAge: "如 2岁4月2天；原表空白则留空"
        case .supplies: "奶瓶、奶粉、湿巾、袜子、上衣、裤子或其他"
        default: "未确认就留空"
        }
    }
    var choices: [String] {
        switch self {
        case .napQuality: ["很安静", "容易醒", "睡不着"]
        case .bowel: ["没有排便", "有排便"]
        case .health: ["健康", "发烧", "咳嗽", "流鼻水", "痰音", "尿布疹"]
        case .appearance: ["整洁良好", "有受伤", "其他"]
        case .mood: ["佳", "普通", "不佳"]
        case .participation: ["主动", "被动", "缺少积极参与"]
        case .peers: ["佳", "普通", "很少互动"]
        case .supplies: ["奶瓶", "奶粉", "80抽大包湿巾", "袜子", "上衣", "裤子"]
        default: []
        }
    }
}

/// OCR coordinates are normalized, top-left based. Keep geometry instead of flattening columns.
nonisolated struct SchoolOCRLine: Sendable, Equatable {
    let text: String
    let x: Double
    let y: Double
    let confidence: Float
    var checkedOptions: [String] = []
    var width: Double = 0
    var height: Double = 0
}

/// Each of the four meals has independent amount, rating and speed; keep other text losslessly.
nonisolated struct SchoolMeal: Equatable, Sendable {
    var amount = ""
    var rating = ""
    var speed = ""
    var notes: [String] = []
    init(_ text: String) {
        for part in text.replacingOccurrences(of: ";", with: "；").components(separatedBy: "；") {
            let part = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if part.isEmpty { continue }
            let labelled = part.replacingOccurrences(of: "：", with: "").replacingOccurrences(of: ":", with: "").replacingOccurrences(of: " ", with: "")
            if ["食量佳", "食量普通", "食量不佳"].contains(labelled) { rating = String(labelled.dropFirst(2)) }
            else if ["速度快", "速度普通", "速度慢"].contains(labelled) { speed = String(labelled.dropFirst(2)) }
            else if labelled.hasPrefix("食量"), SchoolVisualValue.fraction(String(labelled.dropFirst(2))) != nil {
                let readAmount = String(labelled.dropFirst(2))
                if amount.isEmpty { amount = readAmount }
                else if amount != readAmount { notes.append(part) }
            }
            else if amount.isEmpty { amount = part }
            else { notes.append(part) }
        }
    }
    var text: String {
        ([amount, rating.isEmpty ? "" : "食量" + rating, speed.isEmpty ? "" : "速度" + speed] + notes)
            .filter { !$0.isEmpty }.joined(separator: "；")
    }
}

/// Value type in the local draft; committed data remains readable Entry text, not another store.
nonisolated struct SchoolDailyReport: Codable, Equatable, Sendable {
    var values: [String: String] = [:]
    var candidates: [String: String] = [:]
    var dateEvidence = ""
    var confirmed = false
    var sourceHash: String?
    var automaticallyImported: Bool?
    var reviewNotes: [String]?
    var allowsOriginalDeduplication: Bool?
    var recognitionModel: String?

    mutating func adoptRecognizedValues() {
        allowsOriginalDeduplication = (allowsOriginalDeduplication ?? true) && values.isEmpty
        for field in SchoolReportField.allCases {
            guard let value = candidates[field.rawValue], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if self[field].isEmpty { values[field.rawValue] = value }
            else if SchoolReportField.meals.contains(field) {
                var existing = SchoolMeal(self[field])
                let incoming = SchoolMeal(value)
                if existing.amount.isEmpty { existing.amount = incoming.amount }
                if existing.rating.isEmpty { existing.rating = incoming.rating }
                if existing.speed.isEmpty { existing.speed = incoming.speed }
                values[field.rawValue] = existing.text
            }
        }
        automaticallyImported = true
        confirmed = false
    }

    subscript(_ field: SchoolReportField) -> String {
        get { values[field.rawValue] ?? "" }
        set {
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { values.removeValue(forKey: field.rawValue) }
            else { values[field.rawValue] = newValue }
            confirmed = false
            allowsOriginalDeduplication = false
        }
    }
    var hasContent: Bool { values.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    mutating func choose(_ choice: String, for field: SchoolReportField) {
        if SchoolReportField.meals.contains(field) {
            var meal = SchoolMeal(self[field])
            if choice.hasPrefix("食量") { meal.rating = String(choice.dropFirst(2)) }
            else if choice.hasPrefix("速度") { meal.speed = String(choice.dropFirst(2)) }
            self[field] = meal.text
        } else if field == .supplies {
            var parts = self[field].components(separatedBy: "；").filter { !$0.isEmpty }
            if !parts.contains(choice) { parts.append(choice) }
            self[field] = parts.joined(separator: "；")
        } else if field == .health, choice != "健康" {
            var parts = self[field].components(separatedBy: "；").filter { !$0.isEmpty && $0 != "健康" }
            if !parts.contains(choice) { parts.append(choice) }
            self[field] = parts.joined(separator: "；")
        } else { self[field] = choice }
    }
    mutating func setMealAmount(_ amount: String, for field: SchoolReportField) {
        var meal = SchoolMeal(self[field]); meal.amount = amount
        self[field] = meal.text
    }
    static let start = "【亲子桥·已核对】"
    static let automaticStart = "【亲子桥·自动识别】"
    static let end = "【亲子桥结束】"
    var noteBlock: String {
        guard confirmed || automaticallyImported == true else { return "" }
        let lines = SchoolReportField.allCases.compactMap { field -> String? in
            let value = self[field].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            let singleLine = value.components(separatedBy: .newlines).joined(separator: " / ")
                .replacingOccurrences(of: Self.end, with: "［亲子桥结束］")
            return "\(field.rawValue)：\(singleLine)"
        }
        let heading = confirmed ? Self.start : Self.automaticStart
        let modelLine = recognitionModel == "deepseek-flash" ? ["识别模型：deepseek-flash"] : []
        let notes = modelLine + (reviewNotes ?? []).map { "识别提示：" + $0.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: Self.end, with: "［亲子桥结束］") }
        return ([heading] + (lines.isEmpty ? ["未识别栏目以原表为准"] : lines) + notes + [Self.end]).joined(separator: "\n")
    }
    static func from(note: String?) -> Self? {
        guard MemoryJournalKind.school.contains(note), let rawNote = note else { return nil }
        // OCR/source text is evidence, never authority to claim a reviewed structured record.
        let sourceStart = rawNote.range(of: "\n\n老师原文")?.lowerBound ?? rawNote.endIndex
        let note = String(rawNote[..<sourceStart])
        let automatic = note.range(of: Self.automaticStart + "\n")
        guard
              let start = note.range(of: Self.start + "\n") ?? automatic,
              let end = note.range(of: "\n" + Self.end, range: start.upperBound..<note.endIndex) else { return nil }
        var report = Self()
        for line in note[start.upperBound..<end.lowerBound].components(separatedBy: .newlines) {
            if line == "识别模型：deepseek-flash" { report.recognitionModel = "deepseek-flash" }
            if line.hasPrefix("识别提示：") {
                if report.reviewNotes == nil { report.reviewNotes = [] }
                report.reviewNotes?.append(String(line.dropFirst("识别提示：".count)))
            }
            for field in SchoolReportField.allCases where line.hasPrefix(field.rawValue + "：") {
                report[field] = String(line.dropFirst(field.rawValue.count + 1))
            }
        }
        report.confirmed = automatic == nil
        report.automaticallyImported = automatic == nil ? nil : true
        return report
    }

    /// Template recognition is anchored to printed headings, not pixel constants from one photo.
    /// Never infer checkbox selection from printed option text. All values stay unconfirmed.
    static func recognize(_ lines: [SchoolOCRLine]) -> Self? {
        guard lines.contains(where: { $0.text.contains("亲子桥") || $0.text.contains("親子橋") }) else { return nil }
        var report = Self()
        report.dateEvidence = lines.first(where: { $0.text.contains("今天") && $0.text.contains("月") })?.text ?? ""
        func heading(_ text: String) -> SchoolOCRLine? { lines.first { $0.text.contains(text) } }
        if let morning = heading("上午点心"), let fruit = heading("水果"),
           let lunch = heading("午餐"), let afternoon = heading("下午点心"),
           let sleep = lines.first(where: { $0.text == "睡眠" || $0.text.contains("睡眠品质") }),
           morning.x < fruit.x, morning.y < lunch.y, lunch.y < sleep.y,
           abs(morning.y - fruit.y) < 0.05, abs(lunch.y - afternoon.y) < 0.05 {
            let divider = (morning.x + fruit.x) / 2
            let slots: [(SchoolReportField, Bool, Double, Double)] = [
                (.morningSnack, true, morning.y, lunch.y), (.fruit, false, fruit.y, afternoon.y),
                (.lunch, true, lunch.y, sleep.y), (.afternoonSnack, false, afternoon.y, sleep.y)
            ]
            for (field, left, top, bottom) in slots {
                let cell = lines.filter { $0.y > top + 0.01 && $0.y < bottom && ($0.x < divider) == left }
                let percentages = cell
                    .flatMap { matches(#"(?<!\d)(?:100|[0-9]{1,2})\s*[%％]"#, in: $0.text) }
                // Two competing values are ambiguity, not permission to choose one.
                var meal = SchoolMeal("")
                if percentages.count == 1 { meal.amount = percentages[0] }
                let ratings = cell.filter { $0.text.contains("食量") }.flatMap(\.checkedOptions).filter { ["佳", "普通", "不佳"].contains($0) }
                let speeds = cell.filter { $0.text.contains("速度") }.flatMap(\.checkedOptions).filter { ["快", "普通", "慢"].contains($0) }
                if Set(ratings).count == 1 { meal.rating = ratings[0] }
                if Set(speeds).count == 1 { meal.speed = speeds[0] }
                if !meal.text.isEmpty { report.candidates[field.rawValue] = meal.text }
            }
        }
        for (field, label) in [(SchoolReportField.temperatureAM, "早上"), (.temperatureNoon, "中午"), (.temperaturePM, "晚上")] {
            let values = lines.filter { $0.confidence >= 0.85 && $0.text.contains(label) }
                .flatMap { matches(#"(?<!\d)(?:3[0-9]|4[0-2])\.[0-9](?!\d)"#, in: $0.text) }
            if values.count == 1 { report.candidates[field.rawValue] = values[0] + "°C" }
        }
        SchoolReportReading.addDetails(lines, to: &report)
        return report
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}
