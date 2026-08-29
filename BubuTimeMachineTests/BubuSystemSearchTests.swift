import Testing
import Foundation
@testable import BubuTimeMachine

@Suite("系统搜索与时光深链")
@MainActor
struct BubuSystemSearchTests {
    @Test("具体时光 deep link 切到时光页并保留记录 id")
    func momentDeepLink() throws {
        let id = UUID()
        let router = BubuRouter()
        router.handle(BubuRoute.momentURL(id: id))

        #expect(router.pendingTab == 1)
        #expect(router.pendingEntryID == id)
        #expect(router.pendingQuickCapture == false)
    }

    @Test("非法时光 id 不会生成错误详情路由")
    func invalidMomentDeepLink() throws {
        let router = BubuRouter()
        router.handle(try #require(URL(string: "bubu://moment/not-a-uuid")))

        #expect(router.pendingTab == 1)
        #expect(router.pendingEntryID == nil)
    }

    @Test("后到的时光链接会清掉残留快速记录状态")
    func momentRouteClearsPendingCapture() {
        let router = BubuRouter()
        router.handle(BubuRoute.record.url)
        #expect(router.pendingQuickCapture)

        let id = UUID()
        router.handle(BubuRoute.momentURL(id: id))
        #expect(router.pendingQuickCapture == false)
        #expect(router.pendingEntryID == id)
    }

    @Test("Spotlight 差集只删除不再存在的实体")
    func spotlightStaleIdentifierDiff() {
        let kept = UUID()
        let removed = UUID()
        let added = UUID()
        let stale = BubuMomentSpotlightIndexer.staleIdentifiers(
            previous: [kept, removed], current: [kept, added])

        #expect(stale == [removed])
    }
}
