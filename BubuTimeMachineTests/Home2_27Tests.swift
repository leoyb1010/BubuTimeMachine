import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 2.27 首页「今天」：回忆卡文案 / 今日精选合并

@MainActor
struct Home2_27Tests {

    private func memory(kind: String, title: String = "1年前的今天",
                        subtitle: String = "2025年10月20日–25日 · 5个瞬间", count: Int = 5) -> MemoryCardDTO {
        MemoryCardDTO(id: "m1", kind: kind, title: title, subtitle: subtitle,
                      coverId: nil, coverUrl: nil, itemIds: [], count: count)
    }

    @Test func subtitleIsNotDoubleCounted() {
        let card = memory(kind: "family")
        #expect(card.displaySubtitle == "2025年10月20日–25日 · 5个瞬间")
        #expect(!card.displaySubtitle.contains("张"))
        #expect(memory(kind: "trip", subtitle: "  杭州 · 12个瞬间 ").displaySubtitle == "杭州 · 12个瞬间")
    }

    @Test func onThisDayChipShowsYearInsteadOfRepeatingTitle() {
        #expect(memory(kind: "on_this_day").chipLabel == "2025年")
        #expect(memory(kind: "on_this_day", subtitle: "2024年10月19日–25日 · 24个瞬间").chipLabel == "2024年")
        // 解析不出年份时退回原标签。
        #expect(memory(kind: "on_this_day", subtitle: "去年秋天").chipLabel == "那年今天")
        #expect(memory(kind: "family").chipLabel == "和家人")
        #expect(memory(kind: "trip").chipLabel == "去过的地方")
    }

    @Test func picksPreferServerOrderAndKeepLocalPreview() throws {
        let json = """
        {"items":[
          {"id":"a","description":"在公园","preview_url":"/learning/p/a","large_url":"/learning/l/a"},
          {"id":"b","description":" ","preview_url":"/learning/p/b","large_url":null},
          {"id":"a","description":"dup","preview_url":"/learning/p/a","large_url":null},
          {"id":"c","description":null,"preview_url":null,"large_url":null}
        ],"reason_by_id":{"a":"那年今天"}}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(HomeHighlightsResponse.self, from: Data(json.utf8))
        let local = [HomeTodayPick(id: "b", remotePath: nil, localFileURL: URL(fileURLWithPath: "/tmp/pick-b.jpg"),
                                   reason: nil, caption: nil)]
        let picks = HomeTodayModel.merge(highlights: response, local: local)

        #expect(picks.map(\.id) == ["a", "b"])          // 去重；没有任何图片的 c 被丢掉
        #expect(picks[0].remotePath == "/learning/l/a")  // 大图优先
        #expect(picks[0].chip == "那年今天")
        #expect(picks[0].displayCaption == "在公园")
        #expect(picks[1].remotePath == "/learning/p/b")
        #expect(picks[1].localFileURL?.lastPathComponent == "pick-b.jpg")
        #expect(picks[1].chip == "今日精选")
        #expect(picks[1].displayCaption == nil)
    }

    @Test func modelWithoutFamilyServiceStaysQuiet() async {
        let model = HomeTodayModel()
        await model.load(client: nil, consented: true)
        #expect(model.phase == .unavailable)
        #expect(model.memories.isEmpty)
        #expect(model.picks.isEmpty)
        #expect(!model.isLoading)
    }
}
