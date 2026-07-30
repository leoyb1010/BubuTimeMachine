import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 手表照片包与快照 v2 兼容回归
/// 照片包是自定义二进制容器，两端各自实现编解码的话一个字节序错位就是全灭；
/// 快照 v2 的向后兼容（v1 手机 ↔ v2 手表）靠"新增字段全可选"这一条约定成立——
/// 这两件事都值得钉死在测试里。
struct WatchPhotoBundleTests {

    @Test("编码后解码逐条还原（名字与字节都不差）")
    func roundTrip() throws {
        let items: [(name: String, data: Data)] = [
            ("a.jpg", Data([1, 2, 3])),
            ("中文名 photo.jpg", Data(repeating: 0xAB, count: 10_000)),
            ("empty.jpg", Data()),
        ]
        let decoded = try #require(WatchPhotoBundle.decode(WatchPhotoBundle.encode(items)))
        #expect(decoded.count == 3)
        for (lhs, rhs) in zip(items, decoded) {
            #expect(lhs.name == rhs.name)
            #expect(lhs.data == rhs.data)
        }
    }

    @Test("超过单包上限时截断尾部条目而不是炸掉")
    func truncatesOversizedBundle() throws {
        // 每张 500KB，5 张 = 2.5MB > 2MB 上限 → 只留前 4 张。
        let big = Data(repeating: 1, count: 500 * 1024)
        let items = (0..<5).map { (name: "p\($0).jpg", data: big) }
        let decoded = try #require(WatchPhotoBundle.decode(WatchPhotoBundle.encode(items)))
        #expect(decoded.count == 4)
        #expect(decoded.map(\.name) == ["p0.jpg", "p1.jpg", "p2.jpg", "p3.jpg"])
    }

    @Test("损坏/截断的包返回 nil，不返回半套照片")
    func rejectsCorruptData() {
        let good = WatchPhotoBundle.encode([("a.jpg", Data(repeating: 7, count: 100))])
        #expect(WatchPhotoBundle.decode(good.prefix(good.count - 10)) == nil)   // 尾部截断
        #expect(WatchPhotoBundle.decode(Data("nope".utf8)) == nil)              // 魔数不对
        #expect(WatchPhotoBundle.decode(Data()) == nil)
    }

    @Test("指纹与文件名顺序无关，内容变了指纹必变")
    func fingerprintSemantics() {
        let a = WatchPhotoBundle.fingerprint(["x.jpg", "y.jpg"])
        let b = WatchPhotoBundle.fingerprint(["y.jpg", "x.jpg"])
        let c = WatchPhotoBundle.fingerprint(["x.jpg", "z.jpg"])
        #expect(a == b)     // 集合相同 → 不重传
        #expect(a != c)     // 集合变了 → 必须重传
    }

    // MARK: 快照 v2 兼容

    @Test("v1 手机发来的快照（没有 v2 字段）解码成功，v2 字段为 nil")
    func decodesV1Snapshot() throws {
        // 手工构造 v1 形状的 JSON：只有 v1 的键。
        let v1JSON = """
        {"childName":"布布","birthday":null,"roleRaw":"妈妈",
         "achievedMilestones":3,"totalMilestones":10,
         "recent":[{"id":"1","dateText":"7月28日","note":"hi","moodEmoji":null}],
         "avatarData":null,"updatedAt":"2026-07-30T00:00:00Z"}
        """
        let snap = try #require(WatchLink.decode(WatchSnapshot.self, from: Data(v1JSON.utf8)))
        #expect(snap.childName == "布布")
        #expect(snap.memories == nil)
        #expect(snap.todayStats == nil)
        #expect(snap.sleepingSince == nil)
    }

    @Test("v2 快照编解码往返完整")
    func v2RoundTrip() throws {
        let snap = WatchSnapshot(
            childName: "布布", birthday: .now, roleRaw: "爸爸",
            achievedMilestones: 5, totalMilestones: 100,
            recent: [], updatedAt: .now,
            memories: [WatchMemory(id: "m1", dateText: "7月30日", note: "第一次游泳",
                                   ageText: "2岁2个月", isOnThisDay: true,
                                   moodEmoji: "🏊", photoFileName: "swim.jpg")],
            todayStats: ["meal": 4, "sleep": 1],
            sleepingSince: Date(timeIntervalSince1970: 1_800_000_000))
        let data = try #require(WatchLink.encode(snap))
        let back = try #require(WatchLink.decode(WatchSnapshot.self, from: data))
        #expect(back.memories?.count == 1)
        #expect(back.memories?.first?.isOnThisDay == true)
        #expect(back.memories?.first?.photoFileName == "swim.jpg")
        #expect(back.todayStats?["meal"] == 4)
        #expect(back.sleepingSince != nil)
    }

    @Test("新增的记录类型（undo/sleepStart/sleepEnd）编解码稳定")
    func newRecordTypes() throws {
        for type in [WatchRecordType.undo, .sleepStart, .sleepEnd] {
            let req = WatchRecordRequest(type: type, localId: "L1", roleRaw: "妈妈")
            let data = try #require(WatchLink.encode(req))
            let back = try #require(WatchLink.decode(WatchRecordRequest.self, from: data))
            #expect(back.type == type)
            #expect(back.localId == "L1")
        }
    }
}
