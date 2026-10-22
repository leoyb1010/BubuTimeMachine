import Foundation
import Testing
@testable import BubuTimeMachine

/// 2.27 手表 / 精选：跨零点不消失但改标、家人照片与精选并存、快照只装手表读的字段。
struct Watch2_27Tests {
    private func at(_ iso: String) throws -> Date {
        try #require(BubuLearningDates.parseISO(iso))
    }

    private func card(_ id: String, reason: String? = nil, onThisDay: Bool = false) -> WatchMemory {
        WatchMemory(id: id, dateText: "2024年10月22日", note: "", ageText: "", isOnThisDay: onThisDay,
                    photoFileName: "\(id).jpg", reason: reason)
    }

    private func snapshot(family: [WatchMemory], picks: [WatchMemory], day: String?) -> WatchSnapshot {
        WatchSnapshot(childName: "测试宝宝", birthday: nil, roleRaw: "妈妈", achievedMilestones: 0,
                      totalMilestones: 0, recent: [], updatedAt: .now, photoCards: family,
                      dailyPicks: picks, dailyPicksDay: day)
    }

    @Test func freshnessFollowsShanghaiDay() throws {
        let lateEvening = try at("2026-10-22T23:30:00+08:00")
        let afterMidnight = try at("2026-10-23T00:10:00+08:00")
        let twoDaysLater = try at("2026-10-24T08:00:00+08:00")
        #expect(DailyPicksDay.freshness(of: "2026-10-22", now: lateEvening) == .today)
        #expect(DailyPicksDay.freshness(of: "2026-10-22", now: afterMidnight) == .yesterday)
        #expect(DailyPicksDay.freshness(of: "2026-10-22", now: twoDaysLater) == .expired)
        #expect(DailyPicksDay.freshness(of: nil, now: lateEvening) == .expired)
        #expect(DailyPicksDay.string(afterMidnight) == "2026-10-23")
    }

    @Test func storeStalenessMatchesSharedRule() throws {
        let afterMidnight = try at("2026-10-23T00:10:00+08:00")
        // 「需要换新」：只有当天的才新鲜；但昨天的仍可展示（freshness == .yesterday）。
        #expect(DailyPicksStore.isStale(pickDay: "2026-10-22", now: afterMidnight))
        #expect(!DailyPicksStore.isStale(pickDay: "2026-10-23", now: afterMidnight))
    }

    @Test func nextMidnightIsShanghaiMidnight() throws {
        let lateEvening = try at("2026-10-22T23:30:00+08:00")
        #expect(DailyPicksDay.nextMidnight(after: lateEvening) == (try at("2026-10-23T00:00:00+08:00")))
    }

    @Test func yesterdaysPicksStayButLoseOnThisDayLabel() throws {
        let afterMidnight = try at("2026-10-23T00:10:00+08:00")
        let snap = snapshot(family: [], picks: [card("pick-a", reason: "那年今天", onThisDay: true)], day: "2026-10-22")
        let picks = WatchReadModel.dailyPicks(from: snap, now: afterMidnight)
        #expect(picks.count == 1)
        #expect(picks[0].reason == DailyPicksDay.yesterdayReason)
        #expect(picks[0].isOnThisDay == false)

        let sameDay = WatchReadModel.dailyPicks(from: snap, now: try at("2026-10-22T09:00:00+08:00"))
        #expect(sameDay[0].reason == "那年今天")
        #expect(WatchReadModel.dailyPicks(from: snap, now: try at("2026-10-24T09:00:00+08:00")).isEmpty)
    }

    @Test func deckMixesFamilyAndPicksWithoutDuplicates() throws {
        let now = try at("2026-10-22T09:00:00+08:00")
        let family = (1...5).map { card("f\($0)") }
        let picks = [card("pick-1", reason: "最近精选"), card("f1"), card("pick-2"),
                     card("pick-3"), card("pick-4"), card("pick-5")]
        let deck = WatchReadModel.deck(from: snapshot(family: family, picks: picks, day: "2026-10-22"), now: now)
        #expect(deck.count == WatchReadModel.deckLimit)
        #expect(deck.prefix(3).map(\.id) == ["f1", "f2", "f3"])
        #expect(deck[3].id == "pick-1")
        #expect(Set(deck.map(\.id)).count == deck.count)

        // 精选过期时只剩家人照片。
        let expired = WatchReadModel.deck(from: snapshot(family: family, picks: picks, day: "2026-10-01"), now: now)
        #expect(expired.map(\.id) == family.map(\.id))
    }

    @MainActor
    @Test func snapshotCarriesOnlyWatchReadFields() {
        let inputs = WatchSnapshotBuilder.Inputs(childName: "测试宝宝", birthday: nil, roleRaw: "妈妈",
                                                 avatarFileName: nil, sleepingSince: nil, candidates: [])
        let snapshot = WatchSnapshotBuilder.build(inputs, now: .now)
        #expect(snapshot.memories == nil)
        #expect(snapshot.todayStats == nil)
        #expect(snapshot.recent.isEmpty)
        #expect(snapshot.photoCards?.isEmpty == true)
    }
}
