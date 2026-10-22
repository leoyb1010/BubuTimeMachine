import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 2.26 核心：错误分类、取消判断、事件插入、精选过期、时光排版稳定
@MainActor
struct Core2_26Tests {

    // MARK: Error classifier

    @Test func timeoutsAndRefusedConnectionsMeanTheHomeServerIsDown() {
        for code in [URLError.Code.timedOut, .cannotConnectToHost, .cannotFindHost] {
            #expect(LearningErrorKind(URLError(code)) == .serverUnreachable)
            #expect(learningErrorText(URLError(code)) == "家里的服务器没有回应，可能需要在 Mac mini 上处理一下，请稍后重试。")
        }
        #expect(LearningErrorKind(LearningServiceError.server(502)) == .serverUnreachable)
        #expect(LearningErrorKind(LearningServiceError.server(500)) == .other)
    }

    @Test func noNetworkIsOffline() {
        #expect(LearningErrorKind(URLError(.notConnectedToInternet)) == .offline)
        #expect(LearningErrorKind(URLError(.networkConnectionLost)) == .offline)
        #expect(learningErrorText(URLError(.notConnectedToInternet)) == LearningErrorKind.offlineText)
        #expect(BubuStateKind(LearningErrorKind(URLError(.notConnectedToInternet))) == .offline)
    }

    @Test func unauthorizedAsksToReconnect() {
        #expect(LearningErrorKind(LearningServiceError.unauthorized) == .unauthorized)
        #expect(learningErrorText(LearningServiceError.unauthorized) == LearningErrorKind.unauthorizedText)
        #expect(LearningErrorKind(APIError.unauthorized) == .unauthorized)
    }

    @Test func serviceUnavailableUsesServerDetail() {
        let detail = "家里的服务器暂时读不到素材库，请稍后重试。"
        #expect(LearningErrorKind(BubuLearningClientError.unavailable(detail)) == .serviceUnavailable(detail))
        #expect(learningErrorText(BubuLearningClientError.unavailable("请在 Mac mini 上允许访问外接盘")) == "请在 Mac mini 上允许访问外接盘")
        #expect(learningErrorText(BubuLearningClientError.unavailable(nil)) == LearningErrorKind.serviceUnavailableText)
        #expect(BubuStateKind(.serviceUnavailable(nil)) == .serverDown)
    }

    @Test func otherErrorsKeepTheirOwnTextOrFallback() {
        #expect(learningErrorText(BubuLearningClientError.conflict) == "内容刚刚更新过，请刷新后重新核对。")
        #expect(learningErrorText(CocoaError(.fileReadCorruptFile), fallback: "兜底") == "兜底")
    }

    // MARK: Cancellation

    @Test func bothCancellationFlavorsAreCancellation() {
        #expect(isCancellation(CancellationError()))
        #expect(isCancellation(URLError(.cancelled)))
        #expect(!isCancellation(URLError(.timedOut)))
        #expect(!isCancellation(LearningServiceError.unauthorized))
        #expect(LearningErrorKind(URLError(.cancelled)) == .cancelled)
    }

    // MARK: Event interleaving

    private func event(_ id: String, _ day: String) -> OnlineTimelineEvent {
        OnlineTimelineEvent(id: id, title: id, story: nil, day: day, place: nil, count: 3, coverUrl: nil, itemIds: [])
    }

    private func describe(_ slots: [OnlineTimelineSlot<String>]) -> [String] {
        slots.map { slot in
            switch slot {
            case .element(let day): day
            case .event(let event): "E:" + event.id
            }
        }
    }

    @Test func eventsSitBeforeTheirDayNewestFirst() {
        let days = ["2025-07-14", "2025-07-12", "2025-07-12", "2025-07-10"]
        let events = [event("beach", "2025-07-12"), event("park", "2025-07-11"),
                      event("future", "2025-08-01"), event("old", "2025-06-01")]
        let paging = OnlineTimelineLayoutBuilder.interleave(days, day: { $0 }, events: events, newestFirst: true, hasMore: true)
        #expect(describe(paging) == ["2025-07-14", "E:beach", "2025-07-12", "2025-07-12", "E:park", "2025-07-10"])
        let complete = OnlineTimelineLayoutBuilder.interleave(days, day: { $0 }, events: events, newestFirst: true, hasMore: false)
        #expect(describe(complete) == ["2025-07-14", "E:beach", "2025-07-12", "2025-07-12", "E:park", "2025-07-10", "E:old"])
    }

    @Test func eventsSitBeforeTheirDayOldestFirst() {
        let days = ["2025-07-10", "2025-07-12", "2025-07-14"]
        let slots = OnlineTimelineLayoutBuilder.interleave(days, day: { $0 }, events: [event("beach", "2025-07-12")],
                                                           newestFirst: false, hasMore: true)
        #expect(describe(slots) == ["2025-07-10", "E:beach", "2025-07-12", "2025-07-14"])
    }

    @Test func noElementsMeansNoEventCards() {
        let slots = OnlineTimelineLayoutBuilder.interleave([String](), day: { $0 }, events: [event("beach", "2025-07-12")],
                                                           newestFirst: true, hasMore: false)
        #expect(slots.isEmpty)
    }

    // MARK: Daily picks staleness (Shanghai day)

    @Test func picksAreOnlyFreshOnTheirShanghaiDay() throws {
        // 2026-10-22 23:30 in Shanghai is still 15:30 UTC the same day…
        let lateEvening = try #require(BubuLearningDates.parseISO("2026-10-22T23:30:00+08:00"))
        #expect(!DailyPicksStore.isStale(pickDay: "2026-10-22", now: lateEvening))
        // …and 00:10 the next morning in Shanghai is still 2026-10-22 in UTC, but the picks are stale.
        let nextMorning = try #require(BubuLearningDates.parseISO("2026-10-23T00:10:00+08:00"))
        #expect(DailyPicksStore.isStale(pickDay: "2026-10-22", now: nextMorning))
        #expect(DailyPicksStore.isStale(pickDay: nil, now: lateEvening))
    }

    // MARK: Section building

    private func item(_ id: String, _ capturedAt: String?, video: Bool = false, aspect: Double = 1) -> OnlineTimelineItem {
        OnlineTimelineItem(id: id, contentHash: id, kind: video ? "video" : "photo", capturedAt: capturedAt, localDay: nil,
                           description: "", ocr: "", tags: [], segments: [], labelProvenanceText: "",
                           previewUrl: "/learning/api/online-timeline/\(id)/preview", largeUrl: "", mediaUrl: "",
                           aspect: aspect, people: nil, place: "深圳市 · 潜龙 · 曼海宁", confirmedByFamily: nil,
                           descriptionAdjusted: nil, transcriptHidden: nil)
    }

    private func build(_ items: [OnlineTimelineItem], events: [OnlineTimelineEvent] = [], hasMore: Bool = true) -> OnlineTimelineLayout {
        OnlineTimelineLayoutBuilder.build(elements: items.map(OnlineTimelineElement.init), events: events,
                                          newestFirst: true, hasMore: hasMore, width: 360, target: 118)
    }

    private func october() -> [OnlineTimelineItem] {
        (0..<9).map { index in item(String(format: "a%023d", index), String(format: "2026-10-%02dT10:00:00+08:00", 20 - index)) }
    }

    @Test func sectionsAreStableAcrossRebuilds() {
        let first = build(october())
        let second = build(october())
        #expect(first.rows.map(\.id) == second.rows.map(\.id))
        #expect(first.rows.map(\.index) == Array(0..<first.rows.count))
        #expect(first.elementCount == 9)
        guard case .header(let key, let title, let subtitle) = first.rows[0].content else {
            Issue.record("first row should be the month header"); return
        }
        #expect(key == "2026-10")
        #expect(title == "2026年10月")
        #expect(subtitle == "照片 9 · 曼海宁")
    }

    @Test func loadingAnotherMonthKeepsEarlierRows() {
        let base = october()
        let before = build(base)
        let september = (0..<4).map { index in item(String(format: "b%023d", index), String(format: "2026-09-%02dT10:00:00+08:00", 28 - index)) }
        let after = build(base + september)
        // Every full row of October keeps its identity; only the last (partial) row may reflow.
        let stable = before.rows.dropLast().map(\.id)
        #expect(Array(after.rows.prefix(stable.count).map(\.id)) == Array(stable))
        #expect(after.rows.contains { $0.id == "m-2026-09" })
    }

    @Test func monthKeysUseShanghaiDay() {
        // 2026-09-30 17:00 UTC is already October 1st in Shanghai.
        let layout = build([item(String(format: "c%023d", 1), "2026-09-30T17:00:00Z")])
        #expect(layout.rows.first?.id == "m-2026-10")
    }

    @Test func eventCardsBecomeTheirOwnRows() {
        let layout = build(october(), events: [event("beach", "2026-10-16")])
        let ids = layout.rows.map(\.id)
        #expect(ids.contains("e-beach"))
        #expect(ids.first == "m-2026-10")
        #expect(layout.elementCount == 9)
    }

    @Test func undatedItemsGoToUnknownMonth() {
        let layout = build([item(String(format: "d%023d", 1), nil)], hasMore: false)
        guard case .header(_, let title, _) = layout.rows.first?.content else {
            Issue.record("expected header"); return
        }
        #expect(title == "未知日期")
    }
}
