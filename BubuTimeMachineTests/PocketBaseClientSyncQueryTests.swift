import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - PocketBase 同步查询回归测试
struct PocketBaseClientSyncQueryTests {

    @Test("增量拉取只使用 clientUpdatedAt 游标")
    func incrementalQueryUsesClientUpdatedAt() {
        let since = Date(timeIntervalSince1970: 2_000_000_000)
        let items = PocketBaseClient.listRecordsQueryItems(since: since, sort: "clientUpdatedAt", page: 3)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        #expect(values["perPage"] == "200")
        #expect(values["page"] == "3")
        #expect(values["sort"] == "clientUpdatedAt")
        #expect(values["filter"]?.contains("clientUpdatedAt>") == true)
        #expect(values.description.contains("updated>") == false)
        #expect(values.description.contains("-updated") == false)
        #expect(values.description.contains("-created") == false)
    }

    @Test("全量拉取可不带排序和过滤")
    func fullQueryCanOmitSortAndFilter() {
        let items = PocketBaseClient.listRecordsQueryItems(since: nil, sort: nil, page: 1)
        let names = Set(items.map(\.name))

        #expect(names.contains("perPage"))
        #expect(names.contains("page"))
        #expect(!names.contains("sort"))
        #expect(!names.contains("filter"))
    }

    @Test("JSON body 会注入同步时间戳")
    func jsonBodyGetsSyncTimestamp() {
        var body: [String: Any] = ["localId": "abc"]
        let date = Date(timeIntervalSince1970: 2_000_000_000)

        PocketBaseClient.addSyncTimestamp(to: &body, date: date)

        #expect(body["clientUpdatedAt"] as? String == PocketBaseClient.syncTimestampString(date))
    }

    @Test("multipart fields 会注入同步时间戳")
    func multipartFieldsGetSyncTimestamp() {
        var fields = ["localId": "abc"]
        let date = Date(timeIntervalSince1970: 2_000_000_000)

        PocketBaseClient.addSyncTimestamp(to: &fields, date: date)

        #expect(fields["clientUpdatedAt"] == PocketBaseClient.syncTimestampString(date))
    }
}
