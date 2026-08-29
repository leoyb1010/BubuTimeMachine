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
}
