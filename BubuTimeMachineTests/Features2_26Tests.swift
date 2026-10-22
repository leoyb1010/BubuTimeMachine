import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 2.26 能力：问答 / 语言成长线 / 地点 / 家人互动 / 认一认历史 / 生日影片 / 地理编码缓存
@MainActor
struct Features2_26Tests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    private static let hexA = "aaaaaaaaaaaaaaaaaaaaaaaa"
    private static let hexB = "bbbbbbbbbbbbbbbbbbbbbbbb"

    private static func itemJSON(_ id: String) -> String {
        """
        {"id": "\(id)", "content_hash": "h", "kind": "photo", "captured_at": "2025-07-12T10:00:00+08:00",
         "local_day": "2025-07-12", "description": "布布在沙滩上", "ocr": "", "tags": ["海边"], "segments": [],
         "label_provenance_text": "第二大脑认出", "preview_url": "/learning/api/online-timeline/\(id)/preview?size=thumb",
         "large_url": "/learning/api/online-timeline/\(id)/preview?size=large", "media_url": "/learning/api/online-timeline/\(id)/media"}
        """
    }

    // MARK: DTO decoding

    @Test func decodesAskResponse() throws {
        let json = """
        {"answer": "2025 年 7 月 12 日在舟山[1]。", "citations": [{"id": "\(Self.hexA)", "note": "第一次踩到沙子"}],
         "items": [\(Self.itemJSON(Self.hexA)), \(Self.itemJSON(Self.hexB))], "semantic": true, "model_used": true}
        """
        let response = try decode(AskResponseDTO.self, json)
        #expect(response.modelUsed)
        #expect(response.semantic == true)
        #expect(response.citations.first?.note == "第一次踩到沙子")
        #expect(response.items.map(\.id) == [Self.hexA, Self.hexB])

        let fallback = try decode(AskResponseDTO.self, """
        {"answer": null, "citations": [], "items": [\(Self.itemJSON(Self.hexB))], "semantic": false, "model_used": false}
        """)
        #expect(fallback.answer == nil)
        #expect(!fallback.modelUsed)
        #expect(fallback.items.count == 1)
    }

    @Test func decodesWords() throws {
        let json = """
        {"months": [{"month": "2026-03", "new_words": ["爸爸", "苹果"], "total": 12}],
         "firsts": [{"word": "爸爸", "item_id": "\(Self.hexA)", "voice_id": null, "captured_at": "2026-03-02T09:00:00+08:00", "text": "爸爸抱"},
                    {"word": "苹果", "item_id": "\(Self.hexB)", "voice_id": "v1", "captured_at": "2026-03-05", "text": "苹果"}],
         "source_count": 79, "pending": 551}
        """
        let words = try decode(WordsResponseDTO.self, json)
        #expect(words.months.first?.newWords == ["爸爸", "苹果"])
        #expect(words.months.first?.total == 12)
        #expect(words.months.first?.date != nil)
        #expect(words.firsts.first?.voiceId == nil)
        #expect(words.firsts.last?.voiceId == "v1")
        #expect(words.firsts.allSatisfy { $0.date != nil })
        #expect(words.sourceCount == 79)
        #expect(words.pending == 551)
    }

    @Test func decodesPlaces() throws {
        let json = """
        {"items": [{"name": "上海市·世纪公园", "short": "世纪公园", "city": "上海市", "count": 34,
                    "cover_url": "/learning/api/online-timeline/\(Self.hexA)/preview?size=thumb&revision=3",
                    "item_ids": ["\(Self.hexA)"], "first_day": "2025-04-03", "last_day": "2026-09-30"}]}
        """
        let place = try #require(try decode(PlaceListDTO.self, json).items.first)
        #expect(place.id == "上海市·世纪公园")
        #expect(place.displayName == "世纪公园")
        #expect(place.count == 34)
        #expect(place.itemIds == [Self.hexA])
        #expect(PlacesMapView.dayRange(place).contains("2025"))
        #expect(PlaceGeocodeCache.query(for: place.name) == "上海市 世纪公园")
    }

    @Test func decodesSocialAndHeart() throws {
        let json = """
        {"comments": [{"id": "c1", "author": "妈妈", "text": "好可爱", "created_at": "2026-10-22T13:00:00+08:00", "mine": true},
                      {"id": "c2", "author": "家人", "text": "哈哈", "created_at": null, "mine": false}],
         "hearts": 3, "hearted": true}
        """
        let social = try decode(TimelineSocialDTO.self, json)
        #expect(social.hearts == 3)
        #expect(social.hearted)
        #expect(social.comments.map(\.isMine) == [true, false])
        #expect(social.comments.first?.author == "妈妈")
        let heart = try decode(TimelineHeartDTO.self, #"{"hearts": 4, "hearted": true}"#)
        #expect(heart.hearts == 4)
        let comment = try decode(TimelineCommentDTO.self, #"{"id": "c3", "author": "爸爸", "text": "新的", "created_at": "2026-10-22T14:00:00+08:00", "mine": true}"#)
        #expect(comment.text == "新的")
    }

    @Test func decodesRecognitionHistoryAndBatch() throws {
        let json = """
        {"items": [{"id": "\(Self.hexA)", "decision": "yes", "decided_at": "2026-10-22T10:00:00+08:00", "preview_url": "/learning/api/online-timeline/\(Self.hexA)/preview?size=thumb"},
                   {"id": "\(Self.hexB)", "decision": "no", "decided_at": null, "preview_url": null}]}
        """
        let history = try decode(RecognitionHistoryList.self, json)
        #expect(history.items.map(\.decision) == ["yes", "no"])
        #expect(history.items.last?.previewUrl == nil)
        #expect(try decode(RecognitionBatchResult.self, #"{"applied": 12}"#).applied == 12)

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let body = RecognitionBatchBody(decisions: [.init(id: Self.hexA, decision: "yes")])
        let object = try JSONSerialization.jsonObject(with: encoder.encode(body)) as? [String: [[String: String]]]
        #expect(object?["decisions"]?.first?["decision"] == "yes")
    }

    // MARK: Citation markers

    @Test func parsesNumberedAndHexCitations() {
        let citations = [AskCitationDTO(id: Self.hexA, note: nil), AskCitationDTO(id: Self.hexB, note: "动物园")]
        let ids: Set = [Self.hexA, Self.hexB]
        let parts = AskCitationParser.parse("去了海边[1]，还去了动物园【2】和[\(Self.hexB)]。", citations: citations, itemIDs: ids)
        #expect(parts == [
            .text("去了海边"), .cite(number: 1, id: Self.hexA),
            .text("，还去了动物园"), .cite(number: 2, id: Self.hexB),
            .text("和"), .cite(number: 2, id: Self.hexB), .text("。"),
        ])
        #expect(AskCitationParser.hasCitations(parts))
    }

    @Test func leavesUnresolvedMarkersAsText() {
        let citations = [AskCitationDTO(id: Self.hexA, note: nil)]
        let parts = AskCitationParser.parse("见[3]和[^1]", citations: citations, itemIDs: [Self.hexA])
        #expect(parts == [.text("见[3]和"), .cite(number: 1, id: Self.hexA)])
        let plain = AskCitationParser.parse("没有标记的回答", citations: citations, itemIDs: [Self.hexA])
        #expect(plain == [.text("没有标记的回答")])
        #expect(!AskCitationParser.hasCitations(plain))
        // A citation whose id isn't among the returned items can't open anything.
        #expect(AskCitationParser.parse("[1]", citations: citations, itemIDs: []) == [.text("[1]")])
    }

    // MARK: Film moment selection

    private func report(_ month: String, _ ids: [String], title: String = "小报") -> MonthlyReportDTO {
        MonthlyReportDTO(month: month, title: title, summary: "", highlightIds: ids, photos: 1, videos: 0, places: [], firsts: [])
    }

    private func first(_ id: String, item: String?, date: String, title: String, status: String = "confirmed") -> GrowthFirstDTO {
        GrowthFirstDTO(id: id, concept: title, title: title, date: date, itemId: item, previewUrl: nil, description: nil, status: status)
    }

    @Test func picksOnePerMonthPreferringConfirmedFirsts() {
        let months = ["2025-07", "2025-08", "2025-09"]
        let plans = BirthdayFilmPlanner.select(
            months: months,
            reports: [report("2025-09", ["s1", "s2"], title: "开学啦"), report("2025-07", ["j1", "j2"]), report("2025-08", ["a1"])],
            firsts: [first("f1", item: "beach", date: "2025-07-12", title: "看海"),
                     first("f2", item: "cand", date: "2025-08-02", title: "走路", status: "candidate")],
            perMonth: 1)
        #expect(plans.map(\.itemId) == ["beach", "a1", "s1"])
        #expect(plans.map(\.month) == months)
        #expect(plans[0].caption == "2025 年 7 月 · 第一次看海")
        #expect(plans[2].caption == "2025 年 9 月 · 开学啦")
    }

    @Test func fillsMonthsWithoutRepeatsAndKeepsOrder() {
        let plans = BirthdayFilmPlanner.select(
            months: ["2025-11", "2025-10"],
            reports: [report("2025-10", ["x", "y", "z"]), report("2025-11", ["x", "w"])],
            firsts: [first("f", item: "x", date: "2025-10-03T09:00:00+08:00", title: "第一次荡秋千")],
            perMonth: 2)
        #expect(plans.map(\.itemId) == ["x", "y", "w"])
        #expect(plans.first?.caption == "2025 年 10 月 · 第一次荡秋千")
        #expect(plans[1].caption == "2025 年 10 月")
        #expect(Set(plans.map(\.itemId)).count == plans.count)
    }

    @Test func trailingMonthsEndAtCurrentMonth() {
        let now = BubuLearningDates.day("2026-10-22")!
        let months = SecondBrainMonths.trailing(12, endingAt: now)
        #expect(months.count == 12)
        #expect(months.first == "2025-11")
        #expect(months.last == "2026-10")
        #expect(months == months.sorted())
        #expect(SecondBrainMonths.caption("2026-03") == "2026 年 3 月")
    }

    @Test func filmLengthStaysInRange() {
        #expect(BirthdayFilmPlanner.photoSeconds(count: 24) == 2.75)
        #expect(BirthdayFilmPlanner.photoSeconds(count: 40) == 2.5)
        #expect(BirthdayFilmPlanner.photoSeconds(count: 6) == 4.0)
        let duration = BirthdayFilmRenderer.duration(photoCount: 24)
        #expect(duration >= 60 && duration <= 90)
    }

    // MARK: Geocode cache

    @Test func geocodeCacheRoundTrips() throws {
        var cache = PlaceGeocodeCache()
        cache.entries["上海市·世纪公园"] = .init(latitude: 31.22, longitude: 121.55)
        cache.entries["某个没有的地方"] = .notFound
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bubu-geocode-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("geocode.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        cache.save(to: url)
        let loaded = PlaceGeocodeCache.load(from: url)
        #expect(loaded == cache)
        #expect(loaded.entries["上海市·世纪公园"]?.found == true)
        #expect(loaded.entries["某个没有的地方"]?.found == false)
        // A missing or corrupt file starts empty instead of failing.
        #expect(PlaceGeocodeCache.load(from: url.appendingPathExtension("missing")).entries.isEmpty)
        try Data("not json".utf8).write(to: url)
        #expect(PlaceGeocodeCache.load(from: url).entries.isEmpty)
    }
}
