import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - PocketBase 同步查询回归测试
struct PocketBaseClientSyncQueryTests {

    @Test("增量拉取用服务器 updated 游标过滤（新契约：单一权威时钟，不再用 clientUpdatedAt）")
    func incrementalQueryUsesServerUpdated() {
        let since = Date(timeIntervalSince1970: 2_000_000_000)
        // 生产路径 fetchRecords 传 sort:"updated"（服务器系统字段）。
        let items = PocketBaseClient.listRecordsQueryItems(since: since, sort: "updated", page: 3)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        #expect(values["perPage"] == "200")
        #expect(values["page"] == "3")
        #expect(values["sort"] == "updated")
        // 过滤字段改用服务器 updated，且与游标推进同参照系（S-P1-1）。
        #expect(values["filter"]?.contains("updated>'") == true)
        // 关键回归点：不得再用写入设备各自的 clientUpdatedAt 做增量过滤。
        #expect(values.description.contains("clientUpdatedAt") == false)
        #expect(values["filter"]?.contains("\(PocketBaseClient.syncTimestampString(since))") == true)
    }

    @Test("墓碑增量查询同样用 updated 过滤并叠加 isDeleted")
    func deletedQueryUsesServerUpdatedAndIsDeleted() {
        let since = Date(timeIntervalSince1970: 2_000_000_000)
        let items = PocketBaseClient.listRecordsQueryItems(since: since, sort: "updated", page: 1, onlyDeleted: true)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        #expect(values["filter"]?.contains("updated>'") == true)
        #expect(values["filter"]?.contains("isDeleted=true") == true)
        #expect(values.description.contains("clientUpdatedAt") == false)
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

    @Test("同步时间戳使用 PocketBase date 过滤格式")
    func syncTimestampUsesPocketBaseDateFilterFormat() {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let value = PocketBaseClient.syncTimestampString(date)

        #expect(value == "2033-05-18 03:33:20.000Z")
        #expect(value.contains(" "))
        #expect(!value.contains("T"))
    }

    @Test("multipart fields 会注入同步时间戳")
    func multipartFieldsGetSyncTimestamp() {
        var fields = ["localId": "abc"]
        let date = Date(timeIntervalSince1970: 2_000_000_000)

        PocketBaseClient.addSyncTimestamp(to: &fields, date: date)

        #expect(fields["clientUpdatedAt"] == PocketBaseClient.syncTimestampString(date))
    }
}
