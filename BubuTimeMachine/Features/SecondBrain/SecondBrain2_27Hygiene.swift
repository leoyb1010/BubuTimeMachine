import Foundation

// MARK: - 2.27 客户端兜底清洗
/// The family service may still hand back speech-recognition fragments as "words" and the same
/// place twice ("尚云花园" and "深圳市·尚云花园"). The server fix is separate; these keep the pages
/// readable even against an older server.
nonisolated enum SecondBrainHygiene {

    // MARK: Words

    /// Characters that only end a word (自己 → "己…", 对不起 → "起…"): a token starting with one is a split fragment.
    private static let tailOnlyStarts: Set<Character> = ["己", "起", "么", "们", "的", "了", "着", "吗", "呢", "吧", "啦", "嘛"]
    /// Characters that only start a word: a two-character token ending with one was cut short (对不起 → "对不").
    private static let headOnlyEnds: Set<Character> = ["不", "自", "的", "了"]
    private static let pronouns: Set<Character> = ["我", "你", "他", "她", "它"]
    /// After a pronoun these still make a word (我们, 他的…).
    private static let pronounSuffixes: Set<Character> = ["们", "的", "家", "好", "俩"]

    /// Conservative: keeps short Chinese words (1–4 characters) and simple English words; drops
    /// digits, punctuation, sentence pieces like "那记住我" / "他蹲" and split fragments like "己家" / "对不".
    static func isPlausibleWord(_ raw: String) -> Bool {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return false }
        if word.allSatisfy({ $0.isASCII && $0.isLetter }) { return word.count <= 12 }
        guard word.count <= 4, word.allSatisfy(isCJK) else { return false }
        let chars = Array(word)
        if tailOnlyStarts.contains(chars[0]) { return false }
        if chars.count == 2, headOnlyEnds.contains(chars[1]) { return false }
        // Pronoun + verb is a sentence piece, not a word ("他蹲", "我要").
        if pronouns.contains(chars[0]), chars.count >= 2, !pronounSuffixes.contains(chars[1]), chars[1] != chars[0] { return false }
        // A pronoun inside a 3–4 character token is a clause ("那记住我").
        if chars.count >= 3, chars.dropFirst().contains(where: { pronouns.contains($0) }) { return false }
        return true
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    /// Drops implausible words, de-duplicates across months and recomputes the running total from
    /// what is left, so the curve and headline match the chips. Months that end up empty before the
    /// first real word are dropped; later empty months stay (the curve stays flat).
    static func cleanedMonths(_ months: [WordsMonthDTO]) -> [WordsMonthDTO] {
        var seen: Set<String> = []
        var total = 0
        var result: [WordsMonthDTO] = []
        for month in months.sorted(by: { $0.month < $1.month }) {
            var fresh: [String] = []
            for raw in month.newWords {
                let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard isPlausibleWord(word), seen.insert(word).inserted else { continue }
                fresh.append(word)
            }
            total += fresh.count
            if total == 0 { continue }
            result.append(WordsMonthDTO(month: month.month, newWords: fresh, total: total))
        }
        return result
    }

    static func cleanedFirsts(_ firsts: [WordFirstDTO]) -> [WordFirstDTO] {
        var seen: Set<String> = []
        return firsts.filter { isPlausibleWord($0.word) && seen.insert($0.id).inserted }
    }

    // MARK: Places

    /// "22.5431, 114.0579", "N22°32′", "GPS …": raw coordinates, not a place name.
    static func looksLikeCoordinates(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if lowered.contains("gps") || name.contains("°") { return true }
        if name.contains(where: { $0.isNumber }),
           (try? Regex(#"-?\d{1,3}\.\d{2,}"#).firstMatch(in: name)) != nil { return true }
        let meaningful = name.filter { $0.isLetter }
        return meaningful.isEmpty
    }

    /// "深圳市", "广东省", "惠州市" alone: only a city, too coarse to count as a place she went.
    static func isCityOnly(_ place: PlaceDTO) -> Bool {
        let short = place.displayName.trimmingCharacters(in: .whitespaces)
        if let city = place.city?.trimmingCharacters(in: .whitespaces), !city.isEmpty, short == city { return true }
        guard !place.name.contains("·") else { return false }
        return ["市", "省", "自治区", "特别行政区"].contains { short.hasSuffix($0) } && short.count <= 8
    }

    /// The part after the last "·": "深圳市·尚云花园" → "尚云花园".
    static func placeKey(_ place: PlaceDTO) -> String {
        let source = place.short.isEmpty ? place.name : place.short
        let tail = source.split(separator: "·").last.map(String.init) ?? source
        return tail.trimmingCharacters(in: .whitespaces)
    }

    /// Hides coordinate strings and city-only rows, then folds "X" and "城市·X" into one row
    /// (counts summed, photos unioned, widest day range). Sorted by count, most first.
    static func mergedPlaces(_ places: [PlaceDTO]) -> [PlaceDTO] {
        var groups: [String: [PlaceDTO]] = [:]
        var order: [String] = []
        for place in places where !looksLikeCoordinates(place.name) && !isCityOnly(place) {
            let key = placeKey(place)
            guard !key.isEmpty else { continue }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(place)
        }
        let merged: [PlaceDTO] = order.compactMap { key in
            guard let rows = groups[key], let biggest = rows.max(by: { $0.count < $1.count }) else { return nil }
            if rows.count == 1 { return biggest }
            // The "城市·X" spelling geocodes better; keep it as the identity when present.
            let named = rows.first { $0.name.contains("·") } ?? biggest
            var ids: [String] = []
            var seen: Set<String> = []
            for row in rows.sorted(by: { $0.count > $1.count }) {
                for id in row.itemIds where seen.insert(id).inserted { ids.append(id) }
            }
            let firsts = rows.compactMap(\.firstDay).filter { !$0.isEmpty }
            let lasts = rows.compactMap(\.lastDay).filter { !$0.isEmpty }
            return PlaceDTO(name: named.name, short: key,
                            city: rows.compactMap(\.city).first { !$0.isEmpty },
                            count: max(rows.reduce(0) { $0 + $1.count }, ids.count),
                            coverUrl: biggest.coverUrl ?? rows.compactMap(\.coverUrl).first,
                            itemIds: ids, firstDay: firsts.min(), lastDay: lasts.max())
        }
        return merged.sorted { $0.count > $1.count }
    }
}
