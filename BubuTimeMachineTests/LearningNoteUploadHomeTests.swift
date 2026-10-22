import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 课程说明 / 上传去重 / 首页最近时光与时光同序
struct LearningNoteUploadHomeTests {

    // MARK: Duplicate upload

    private func temporaryFile(_ bytes: Data, ext: String = "mp4") throws -> URL {
        let url = CourseUploadSheet.temporary(ext)
        try bytes.write(to: url)
        return url
    }

    @Test func everyPickedCopyGetsItsOwnTemporaryURL() {
        let urls = (0..<50).map { _ in CourseUploadSheet.temporary("mp4") }
        #expect(Set(urls).count == urls.count)
    }

    @Test func identicalContentIsAdmittedOnceEvenFromTwoTemporaryCopies() async throws {
        let video = Data((0..<300_000).map { UInt8($0 % 251) })
        let first = try temporaryFile(video), second = try temporaryFile(video)
        let other = try temporaryFile(video + Data([1]))
        defer { for url in [first, second, other] { try? FileManager.default.removeItem(at: url) } }

        let firstDigest = try await LearningUploadSelection.digest(of: first)
        let secondDigest = try await LearningUploadSelection.digest(of: second)
        let otherDigest = try await LearningUploadSelection.digest(of: other)
        #expect(first != second && firstDigest == secondDigest && firstDigest != otherDigest)

        var selection = LearningUploadSelection()
        #expect(selection.add(LearningUploadFile(url: first, fileName: "a.mp4", mimeType: "video/mp4"), digest: firstDigest) == .added)
        #expect(selection.add(LearningUploadFile(url: second, fileName: "b.mp4", mimeType: "video/mp4"), digest: secondDigest) == .duplicate)
        #expect(selection.add(LearningUploadFile(url: other, fileName: "c.mp4", mimeType: "video/mp4"), digest: otherDigest) == .added)
        #expect(selection.files.map(\.url) == [first, other])

        // Removing a file frees its content, so the parent can pick it again.
        let removed = selection.remove(atOffsets: IndexSet(integer: 0))
        #expect(removed.map(\.url) == [first])
        #expect(selection.add(LearningUploadFile(url: second, fileName: "b.mp4", mimeType: "video/mp4"), digest: secondDigest) == .added)
    }

    @Test func selectionStopsAtTheLimit() {
        var selection = LearningUploadSelection()
        for index in 0..<LearningUploadSelection.limit {
            let file = LearningUploadFile(url: URL(fileURLWithPath: "/tmp/\(index).jpg"), fileName: "\(index).jpg", mimeType: "image/jpeg")
            #expect(selection.add(file, digest: "d\(index)") == .added)
        }
        let extra = LearningUploadFile(url: URL(fileURLWithPath: "/tmp/x.jpg"), fileName: "x.jpg", mimeType: "image/jpeg")
        #expect(selection.isFull && selection.add(extra, digest: "new") == .full)
        #expect(selection.add(extra, digest: "d0") == .duplicate)
    }

    // MARK: Course note

    @Test func noteIsTrimmedCappedAndOmittedWhenEmpty() {
        #expect(LearningCourseNote.normalized("  \n ") == nil)
        #expect(LearningCourseNote.normalized(" 秋天的儿歌 leaf ") == "秋天的儿歌 leaf")
        #expect(LearningCourseNote.normalized(String(repeating: "字", count: 2_500))?.count == LearningCourseNote.maxLength)
        #expect(LearningCourseNote.normalized(String(repeating: "👨‍👩‍👧", count: 500))?.unicodeScalars.count == LearningCourseNote.maxLength)
    }

    private func courseJSON(note: String?) -> Data {
        var object: [String: Any] = [
            "id": "c1", "child_id": "k1", "school_date": "2026-10-21", "title": "水果", "kind": "teaching",
            "language": "en-US", "state": "no_lesson", "source_count": 1, "expected_files": 1, "activity_count": 0,
            "pack": NSNull(), "sources": [], "created_at": "2026-10-21T08:00:00+08:00",
        ]
        if let note { object["note"] = note }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    @Test func courseNoteDecodesAndOlderServersStillWork() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        #expect(try decoder.decode(LearningCourseDetailDTO.self, from: courseJSON(note: "重点词 apple")).note == "重点词 apple")
        #expect(try decoder.decode(LearningCourseDetailDTO.self, from: courseJSON(note: nil)).note == nil)
        #expect(try decoder.decode(LearningCourseDTO.self, from: courseJSON(note: "儿歌")).note == "儿歌")
        #expect(try decoder.decode(LearningCourseDTO.self, from: courseJSON(note: nil)).note == nil)
    }

    // MARK: Home 最近时光

    private func item(_ id: String, _ capturedAt: String) -> OnlineTimelineItem {
        OnlineTimelineItem(id: id, contentHash: id, kind: "photo", capturedAt: capturedAt, localDay: String(capturedAt.prefix(10)),
                           description: "", ocr: "", tags: [], segments: [], labelProvenanceText: "",
                           previewUrl: "/learning/api/online-timeline/\(id)/preview", largeUrl: "", mediaUrl: "",
                           aspect: 1, people: nil, place: nil, confirmedByFamily: nil,
                           descriptionAdjusted: nil, transcriptHidden: nil)
    }

    private func date(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }

    @Test func homeRecentMatchesTimelineDefaultOrder() {
        let items = [item("o3", "2026-10-21T18:00:00+08:00"), item("o2", "2026-10-20T09:00:00+08:00"),
                     item("o1", "2026-10-18T09:00:00+08:00")]
        let familyNew = OnlineTimelineFamilyRef(id: UUID(), date: date("2026-10-21T12:00:00+08:00"))
        let familyOld = OnlineTimelineFamilyRef(id: UUID(), date: date("2026-10-19T12:00:00+08:00"))
        let family = [familyNew, familyOld]

        let home = HomeRecentModel.elements(items: items, family: family, connected: true, hasMore: false, limit: 4)
        #expect(home.map(\.id) == ["o-o3", "f-" + familyNew.id.uuidString, "o-o2", "f-" + familyOld.id.uuidString])

        // Same prefix as the 时光 tab's default merged stream.
        let timeline = OnlineTimelineLayoutBuilder.elements(items: items, family: family, query: OnlineTimelineQuery(),
                                                            source: .merged, hasMore: false).elements
        #expect(home.map(\.id) == Array(timeline.prefix(4)).map(\.id))

        // Not connected: only the family records, newest first.
        let offline = HomeRecentModel.elements(items: items, family: family, connected: false, hasMore: false, limit: 6)
        #expect(offline.map(\.id) == ["f-" + familyNew.id.uuidString, "f-" + familyOld.id.uuidString])
    }

    @Test func homeRecentSharesTimelineCacheKey() {
        // The home page reads the 时光 tab's cached first page, so both must use the same key.
        let query = OnlineTimelineQuery()
        #expect(query.cacheKey == "kind=all&order=desc&limit=60")
        #expect(query.parameters(page: 1).contains(URLQueryItem(name: "page", value: "1")))
    }
}
