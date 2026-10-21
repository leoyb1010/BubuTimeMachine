import Foundation
import SwiftData
import Testing
#if !TIMELINE_HELPER_TESTS
@testable import BubuTimeMachine
#endif

@Suite(.serialized) @MainActor
struct TimelineQueryTests {
    private func fixture() throws -> (ModelContainer, ModelContext, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("timeline-query-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("test.store"))
        let container = try ModelContainer(for: Entry.self, configurations: configuration)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return (container, context, directory)
    }
    private func entry(_ context: ModelContext, at seconds: Double, type: MediaType? = nil,
                       note: String? = nil, role: String? = nil) -> Entry {
        let value = Entry(happenedAt: Date(timeIntervalSince1970: seconds), authorRole: "妈妈", note: note)
        context.insert(value)
        if let type {
            let media = Media(type: type, localFileName: "fixture")
            media.resourceRoleRaw = role
            media.entry = value
            context.insert(media)
        }
        return value
    }

    @Test("筛选先于分页：只取指定日期内的自动视频，隐藏Live资源不算独立视频")
    func filtersRunBeforeLimit() throws {
        let (_, context, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 86_400)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let automatic = entry(context, at: 86_401, type: .video, note: "【第二大脑自动整理】\n踢球")
        _ = entry(context, at: 86_410, type: .video, note: "家人记录")
        _ = entry(context, at: 86_420, type: .video, note: "【第二大脑自动整理】\nLive原件", role: "live-paired")
        _ = entry(context, at: 86_430, type: .photo, note: "【第二大脑自动整理】\n图片")
        _ = entry(context, at: 172_800, type: .video, note: "【第二大脑自动整理】\n次日")
        try context.save()
        let filter = TimelineFilters(kind: .video, source: .automatic, start: date, end: date)
        let result = try context.fetch(TimelineEntryQuery.descriptor(filters: filter, query: "", sort: .capture, limit: 1, calendar: calendar))
        #expect(result.map(\.id) == [automatic.id])
    }

    @Test("日期结束日包含当天最后一秒，家庭来源不会误排除正文中提及marker的记录")
    func dateAndSourceBoundaries() throws {
        let (_, context, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = Date(timeIntervalSince1970: 86_400)
        let manual = entry(context, at: 172_799, type: .photo, note: "今天讨论了【第二大脑自动整理】这个功能")
        _ = entry(context, at: 172_800, type: .photo)
        _ = entry(context, at: 86_450, type: .photo, note: "【第二大脑自动整理】\n新素材")
        try context.save()
        let filter = TimelineFilters(kind: .all, source: .family, start: end, end: end)
        let result = try context.fetch(TimelineEntryQuery.descriptor(filters: filter, query: "", sort: .capture, limit: 20, calendar: calendar))
        #expect(result.map(\.id) == [manual.id])
    }

    @Test("搜索不把200条之外的老记录截断，也不加载全部记录")
    func searchQueriesWholeStoreButReturnsOnePage() throws {
        let (_, context, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = entry(context, at: 1, note: "corn and pumpkin")
        for index in 2...205 { _ = entry(context, at: Double(index), note: "其他时光") }
        try context.save()
        let result = try context.fetch(TimelineEntryQuery.descriptor(filters: .init(), query: "CORN", sort: .capture, limit: 2))
        #expect(result.count == 1 && result.first?.id == target.id)
    }

    @Test("最新、最早与最近收录排序都在数据库取页前生效")
    func sortBeforePagination() throws {
        let (_, context, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = entry(context, at: 1); old.createdAt = Date(timeIntervalSince1970: 99)
        let recent = entry(context, at: 10); recent.createdAt = Date(timeIntervalSince1970: 10)
        try context.save()
        #expect(try context.fetch(TimelineEntryQuery.descriptor(filters: .init(), query: "", sort: .capture, limit: 1)).first?.id == recent.id)
        #expect(try context.fetch(TimelineEntryQuery.descriptor(filters: .init(), query: "", sort: .oldest, limit: 1)).first?.id == old.id)
        #expect(try context.fetch(TimelineEntryQuery.descriptor(filters: .init(), query: "", sort: .recorded, limit: 1)).first?.id == old.id)
    }

    @Test("语音筛选同时包含附加录音与音频素材，忽略纯照片")
    func voiceFilterIncludesAttachedRecordings() throws {
        let (_, context, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let spoken = entry(context, at: 1)
        let note = VoiceNote(localFileName: "test.m4a", durationSeconds: 2, authorRole: "妈妈")
        note.transcript = "小熊你好"
        note.entry = spoken; context.insert(note)
        let audio = entry(context, at: 2, type: .audio)
        _ = entry(context, at: 3, type: .photo)
        try context.save()
        let result = try context.fetch(TimelineEntryQuery.descriptor(filters: .init(kind: .audio), query: "", sort: .capture, limit: 20))
        #expect(result.map(\.id) == [audio.id, spoken.id])
        let transcript = try context.fetch(TimelineEntryQuery.descriptor(filters: .init(kind: .audio), query: "小熊", sort: .capture, limit: 20))
        #expect(transcript.map(\.id) == [spoken.id])
    }

    @Test("远端命中按ID单独取回，仍遵守本机日期与来源条件")
    func remoteIDsRespectLocalScope() throws {
        let (_, context, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let automatic = entry(context, at: 1, note: "【第二大脑自动整理】\n玩球")
        let family = entry(context, at: 2, note: "家人记录")
        _ = entry(context, at: 3, note: "【第二大脑自动整理】\n未命中的其他内容")
        try context.save()
        let result = try context.fetch(TimelineEntryQuery.descriptor(filters: .init(source: .automatic), query: "",
            sort: .capture, limit: 80, entryIDs: [automatic.id, family.id]))
        #expect(result.map(\.id) == [automatic.id])
        #expect(try context.fetch(TimelineEntryQuery.descriptor(filters: .init(), query: "", sort: .capture,
            limit: 80, entryIDs: [])).isEmpty)
    }

    @Test("父记录已同步但命中媒体未到齐时，仍标记为等待同步")
    func missingMatchedMediaIsPending() throws {
        let (_, context, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let value = entry(context, at: 1)
        try context.save()
        let references = [(entryID: value.id, mediaID: "remote-video")]
        #expect(TimelineEntryQuery.pendingRemoteCount(references: references, known: [value]) == 1)
        let video = Media(type: .video, localFileName: nil)
        video.remoteId = "remote-video"; video.entry = value; context.insert(video)
        try context.save()
        #expect(TimelineEntryQuery.pendingRemoteCount(references: references, known: [value]) == 0)
        value.isArchived = true
        #expect(TimelineEntryQuery.pendingRemoteCount(references: references, known: [value]) == 0)
    }
}
