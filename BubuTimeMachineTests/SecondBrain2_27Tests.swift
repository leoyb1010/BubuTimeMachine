import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 2.27 魔法屋功能页：词表/地点兜底清洗、服务器状态标题、家人最近互动、成长月刊
@MainActor
struct SecondBrain2_27Tests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: Words

    @Test func dropsSpeechRecognitionFragments() {
        for fragment in ["己家", "来自", "那记住我", "起我", "对不", "他蹲", "", "22", "哈!", "一二三四五"] {
            #expect(!SecondBrainHygiene.isPlausibleWord(fragment), "\(fragment)")
        }
        for word in ["妈妈", "爸爸", "姥姥", "我们", "你好", "不要", "吃", "谢谢", "bye", "小汽车"] {
            #expect(SecondBrainHygiene.isPlausibleWord(word), "\(word)")
        }
    }

    @Test func recountsMonthsFromCleanWords() {
        let months = [
            WordsMonthDTO(month: "2026-08", newWords: ["爸爸", "对不", "妈妈"], total: 30),
            WordsMonthDTO(month: "2026-07", newWords: ["己家", "妈妈"], total: 24),
            WordsMonthDTO(month: "2026-06", newWords: ["来自"], total: 1),
        ]
        let cleaned = SecondBrainHygiene.cleanedMonths(months)
        // June had only junk, so the line starts in July; "妈妈" is counted once.
        #expect(cleaned.map(\.month) == ["2026-07", "2026-08"])
        #expect(cleaned.map(\.newWords) == [["妈妈"], ["爸爸"]])
        #expect(cleaned.map(\.total) == [1, 2])
    }

    // MARK: Places

    private func place(_ name: String, short: String, city: String? = "深圳市", count: Int, ids: [String],
                       first: String? = nil, last: String? = nil) -> PlaceDTO {
        PlaceDTO(name: name, short: short, city: city, count: count, coverUrl: nil, itemIds: ids, firstDay: first, lastDay: last)
    }

    @Test func mergesDuplicatePlacesAndDropsCityOnlyAndCoordinates() {
        let merged = SecondBrainHygiene.mergedPlaces([
            place("尚云花园", short: "尚云花园", count: 220, ids: ["a", "b"], first: "2025-01-02", last: "2026-01-01"),
            place("深圳市·尚云花园", short: "尚云花园", count: 83, ids: ["b", "c"], first: "2024-06-01", last: "2025-05-01"),
            place("深圳市", short: "深圳市", count: 50, ids: ["d"]),
            place("惠州市", short: "惠州市", city: "惠州市", count: 37, ids: ["e"]),
            place("22.5431, 114.0579", short: "22.5431, 114.0579", count: 9, ids: ["f"]),
            place("民治", short: "民治", count: 75, ids: ["g"]),
        ])
        #expect(merged.map(\.displayName) == ["尚云花园", "民治"])
        let home = merged[0]
        #expect(home.name == "深圳市·尚云花园")
        #expect(home.count == 303)
        #expect(home.itemIds == ["a", "b", "c"])
        #expect(home.firstDay == "2024-06-01")
        #expect(home.lastDay == "2026-01-01")
    }

    // MARK: Server status

    private func status(ok: Bool = true, library: Bool? = true, worker: Bool? = true, voices: Int? = 0,
                        backup: String? = "2026-10-22T08:00:00+08:00") -> LearningServerStatusDTO {
        LearningServerStatusDTO(ok: ok, learningStore: true, brainLibrary: library, workerAlive: worker, workerHeartbeatAt: nil,
                                snapshotAt: nil, captionsPending: 0, voicesPending: voices, backupAt: backup, items: 10, checkedAt: nil)
    }

    @Test func headlineFollowsRowWarnings() {
        let now = BubuLearningDates.parseISO("2026-10-22T10:00:00+08:00")!
        // ok:true with no backup must not read "一切正常".
        #expect(ServerStatusView.headline(status(voices: 529, backup: nil), now: now).title == "备份还没开始")
        #expect(ServerStatusView.headline(status(library: false, backup: nil), now: now).title == "有 2 处需要看一下")
        // A backlog alone is progress, not a warning.
        let busy = ServerStatusView.headline(status(voices: 529), now: now)
        #expect(busy.level == .progress)
        #expect(ServerStatusView.pending(529, unit: "段").level == .progress)
        #expect(ServerStatusView.headline(status(), now: now) == .init(level: .ok, title: "一切正常", detail: nil))
    }

    // MARK: Family social recent

    @Test func decodesRecentSocialAndSummarises() throws {
        let list = try decode(SocialRecentList.self, """
        {"items": [
          {"item_id": "x1", "author": "姥姥", "text": null, "kind": "heart", "created_at": "2026-10-21T09:00:00+08:00", "preview_url": "/p/x1"},
          {"item_id": "x2", "author": "姥姥", "text": null, "kind": "heart", "created_at": "2026-10-21T08:00:00+08:00", "preview_url": "/p/x2"},
          {"item_id": "x2", "author": "妈妈", "text": "好可爱", "kind": "comment", "created_at": "2026-10-20T08:00:00+08:00", "preview_url": null},
          {"item_id": "x3", "author": "", "text": null, "kind": "heart", "created_at": null, "preview_url": null}
        ]}
        """)
        #expect(list.items.count == 4)
        #expect(list.items[3].authorName == "家人")
        #expect(FamilySocialSummary.line(list.items) == "姥姥给 2 张照片点了心 · 妈妈留了 1 句话 · 家人给 1 张照片点了心")
        #expect(FamilySocialSummary.line([]) == nil)
    }

    // MARK: Monthly magazine

    @Test func magazineNumbersIssuesOldestFirstAndShelvesNewestFirst() {
        func report(_ month: String) -> MonthlyReportDTO {
            MonthlyReportDTO(month: month, title: month, summary: "", highlightIds: [], photos: 0, videos: 0, places: [], firsts: [])
        }
        let issues = MonthlyMagazine.issues([report("2025-02"), report("2024-05"), report("2025-01"), report("2024-05")])
        #expect(issues.map(\.month) == ["2024-05", "2025-01", "2025-02"])
        let shelves = MonthlyMagazine.shelves(issues)
        #expect(shelves.map(\.year) == ["2025", "2024"])
        #expect(shelves[0].issues.map(\.month) == ["2025-02", "2025-01"])
        #expect(MonthlyMagazine.shortPlaces(["深圳市 · 尚云花园", "深圳市·尚云花园", "民治"]) == ["尚云花园", "民治"])
    }
}
