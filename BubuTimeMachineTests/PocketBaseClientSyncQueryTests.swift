import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - PocketBase 同步查询回归测试
struct PocketBaseClientSyncQueryTests {

    @Test("同一毫秒 401 条记录和墓碑都能跨页完整拉取")
    func tiedTimestampsDoNotLoseRows() async throws {
        let timestamp = "2026-09-08 00:00:00.123Z"
        for deleted in [false, true] {
            let records: [[String: Any]] = (0..<401).map {
                ["id": String(format: "%015d", $0), "updated": timestamp, "isDeleted": deleted]
            }
            var requests = 0
            let result = try await PocketBaseClient.collectPages(since: nil) { since, afterID in
                requests += 1
                let remaining = records.filter { row in
                    guard let since else { return true }
                    let updated = PocketBaseClient.serverUpdatedDate(row)!
                    return updated > since || (updated == since && (row["id"] as! String) > (afterID ?? ""))
                }
                return Array(remaining.prefix(200))
            }
            #expect(result.count == 401)
            #expect(requests == 3)
            #expect(Set(result.compactMap { $0["id"] as? String }).count == 401)
        }
    }

    @Test("跨页重复的已编辑记录保留最新版本")
    func movedRecordKeepsLatestVersion() async throws {
        var page = 0
        let result = try await PocketBaseClient.collectPages(since: nil) { _, _ in
            page += 1
            if page == 1 {
                return (0..<200).map { ["id": String(format: "%015d", $0), "updated": "2026-09-08 00:00:00.123Z"] }
            }
            return [["id": "000000000000000", "updated": "2026-09-08 00:00:01.123Z", "note": "new"]]
        }
        #expect(result.count == 200)
        #expect(result.first?["note"] as? String == "new")
    }

    @Test("坏响应和分页上限不能返回部分成功")
    func invalidPageFailsClosed() async {
        do {
            _ = try await PocketBaseClient.collectPages(since: nil) { _, _ in [["id": "missing-date"]] }
            Issue.record("缺少 updated 必须失败")
        } catch {}
        do {
            _ = try await PocketBaseClient.collectPages(since: nil, maxRounds: 1) { _, _ in
                (0..<200).map { ["id": String(format: "%015d", $0), "updated": "2026-09-08 00:00:00.123Z"] }
            }
            Issue.record("达到上限必须失败")
        } catch {}
        do {
            let since = PocketBaseClient.serverUpdatedDate(["updated": "2026-09-08 00:00:01.123Z"])!
            _ = try await PocketBaseClient.collectPages(since: since) { _, _ in
                [["id": "backwards", "updated": "2026-09-08 00:00:00.123Z"]]
            }
            Issue.record("游标倒退必须失败")
        } catch {}
    }

    @Test("联合游标包含 id 并保持墓碑过滤的括号边界")
    func compoundCursorQuery() {
        let since = Date(timeIntervalSince1970: 2_000_000_000)
        let query = PocketBaseClient.listRecordsQueryItems(since: since, sort: "updated,id", page: 1,
                                                         onlyDeleted: true, afterID: "000000000000199")
        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        #expect(values["sort"] == "updated,id")
        #expect(values["filter"] == "(updated>'2033-05-18 03:33:20.000Z' || (updated='2033-05-18 03:33:20.000Z' && id>'000000000000199')) && (isDeleted=true)")
    }

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
