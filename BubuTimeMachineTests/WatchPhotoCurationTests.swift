import Foundation
import Testing
import UIKit
@testable import BubuTimeMachine

@MainActor
struct WatchPhotoCurationTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func withPhotos(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("watch-curation-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func entry(_ directory: URL, at date: Date, note: String? = "一起去公园") throws -> Entry {
        let name = "\(UUID()).png"
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        try #require(image.pngData()).write(to: directory.appendingPathComponent(name))
        let entry = Entry(happenedAt: date, authorRole: "妈妈", note: note)
        entry.media = [Media(type: .photo, localFileName: name)]
        return entry
    }

    private func cards(_ entries: [Entry], directory: URL) -> [WatchMemory] {
        WatchSnapshotBuilder.photoCards(entries: entries, birthday: nil,
                                        now: date(2026, 10, 3), calendar: calendar,
                                        photoURL: { directory.appendingPathComponent($0) })
    }

    @Test("最多五张，最新三张之后优先那年今日与不同旧日期")
    func latestThreeThenAnniversary() throws {
        try withPhotos { directory in
            let entries = try [date(2026, 10, 3), date(2026, 10, 2), date(2026, 10, 1),
                               date(2026, 9, 30), date(2026, 9, 30), date(2025, 10, 3),
                               date(2024, 9, 1)].map { try entry(directory, at: $0) }
            let result = cards(Array(entries.reversed()), directory: directory)
            #expect(result.count == 5)
            #expect(Array(result.prefix(3)).map(\.id) == entries.prefix(3).map { $0.media[0].id.uuidString })
            #expect(result[3].id == entries[5].media[0].id.uuidString)
            #expect(result[3].isOnThisDay)
            #expect(result[3].dateText == "2025年10月3日")
            #expect(result[4].dateText == "2026年9月30日")
        }
    }

    @Test("原始童言与自写标题可作短句，同一天照片不足时不凑旧日期")
    func sayingAndTitleFallback() throws {
        try withPhotos { directory in
            let saying = try entry(directory, at: date(2026, 10, 3), note: "【布布说】\n\n她说：月亮也要回家睡觉。\n\n当时：散步回家")
            let titled = try entry(directory, at: date(2026, 10, 2), note: "  ")
            titled.title = "第一次自己吹泡泡"
            let result = cards([saying, titled], directory: directory)
            #expect(result.map(\.note) == ["月亮也要回家睡觉。", "第一次自己吹泡泡"])
            let sameDay = try (0..<8).map { _ in try entry(directory, at: date(2026, 10, 3)) }
            #expect(cards(sameDay, directory: directory).count == 3)
        }
    }

    @Test("排除归档、亲子桥日表、视频、截图、文档、来源资源、缺失和损坏文件")
    func rejectsNonLifePhotos() throws {
        try withPhotos { directory in
            let entries = try (0..<10).map { _ in try entry(directory, at: date(2026, 10, 3)) }
            entries[0].isArchived = true
            var report = SchoolDailyReport()
            report.confirmed = true
            entries[1].note = "【幼儿园】\n\n" + report.noteBlock
            entries[2].media[0].typeRaw = "video"
            entries[3].media[0].aiTags = ["聊天截图"]
            entries[4].media[0].aiTags = ["document"]
            entries[5].media[0].resourceRoleRaw = "source"
            entries[6].media[0].resourceRoleRaw = "document"
            entries[7].media[0].localFileName = "missing.png"
            try Data("not an image".utf8).write(to: directory.appendingPathComponent(entries[8].media[0].localFileName!))
            entries[9].media[0].aiTags = ["亲子桥"]
            #expect(cards(entries, directory: directory).isEmpty)
        }
    }

    @Test("保留普通幼儿园生活照，只用原始小故事，不用第一人称改写或餐睡数据")
    func preservesSchoolLifeAndOriginalWords() throws {
        try withPhotos { directory in
            let school = try entry(directory, at: date(2026, 10, 3),
                                   note: "【幼儿园】\n\n今天的小故事：和朋友一起搭了高高的积木。\n\n餐食：吃光了\n\n午睡：一小时")
            school.media[0].aiTags = ["幼儿园", "生活照片"]
            school.firstPersonNote = "我是积木小超人！"
            let plain = try entry(directory, at: date(2026, 10, 2), note: "她把小花送给了妈妈。")
            plain.firstPersonNote = "我最爱妈妈啦！"
            let mealOnly = try entry(directory, at: date(2026, 10, 1), note: "【幼儿园】\n\n餐食：吃光了\n\n午睡：一小时")
            mealOnly.title = "幼儿园的一天"
            let result = cards([school, plain, mealOnly], directory: directory)
            #expect(result.map(\.note) == ["和朋友一起搭了高高的积木。", "她把小花送给了妈妈。", ""])
            #expect(school.note?.contains("餐食：吃光了") == true)
            #expect(school.firstPersonNote == "我是积木小超人！")
        }
    }

    @Test("素材 ID、内容哈希与回退缩略图名称均去重，单条记录只出一张")
    func deduplicatesAssetsAndFallsBackToOriginal() throws {
        try withPhotos { directory in
            let entries = try (1...6).map { try entry(directory, at: date(2026, 10, 7 - $0)) }
            entries[1].media[0].id = entries[0].media[0].id
            entries[0].media[0].contentHash = "shared-hash"
            entries[2].media[0].contentHash = "SHARED-HASH"
            entries[3].media[0].localFileName = nil
            entries[3].media[0].thumbnailFileName = entries[0].media[0].localFileName
            entries[4].media[0].thumbnailFileName = "missing-thumbnail.png"
            entries[4].media.append(Media(type: .photo, localFileName: entries[5].media[0].localFileName))
            let result = cards(entries, directory: directory)
            #expect(result.count == 3)
            #expect(result[1].photoFileName == entries[4].media[0].localFileName)
            #expect(Set(result.map(\.id)).count == result.count)
        }
    }

    @Test("只看最新三百条未归档记录，资料不足时不凑满五张")
    func boundsCandidatePool() throws {
        try withPhotos { directory in
            let olderPhoto = try entry(directory, at: date(2025, 1, 1))
            let newer = (0..<300).map { _ in Entry(happenedAt: date(2026, 1, 1), authorRole: "妈妈") }
            #expect(cards(newer + [olderPhoto], directory: directory).isEmpty)
            newer.forEach { $0.isArchived = true }
            #expect(cards(newer + [olderPhoto], directory: directory).count == 1)
        }
    }

    @Test("凑齐五张就停止读取照片，短句含省略号不超过24个字符")
    func readsOnlySelectedPhotos() throws {
        try withPhotos { directory in
            let entries = try (1...10).map {
                try entry(directory, at: date(2026, 9, 30 - $0), note: String(repeating: "🌈", count: 30))
            }
            var reads = 0
            let result = WatchSnapshotBuilder.photoCards(
                entries: entries, birthday: nil, now: date(2026, 10, 3), calendar: calendar,
                photoURL: {
                    reads += 1
                    return directory.appendingPathComponent($0)
                })
            #expect(result.count == 5)
            #expect(reads == 5)
            #expect(result.allSatisfy { $0.note.count == 24 && $0.note.hasSuffix("…") })
        }
    }
}
