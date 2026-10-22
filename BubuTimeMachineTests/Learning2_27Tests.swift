import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 2.27 学习升级：跟读打分 / 学习周报 / 上传进度 / Siri 深链

@MainActor
struct Learning2_27Tests {

    // MARK: 跟读打分

    @Test func speechChineseExactAndHomophones() {
        #expect(SpeechPracticeScorer.score(target: "苹果", heard: "苹果") == 100)
        // 识别成同音字也算对（按拼音比）。
        #expect(SpeechPracticeScorer.score(target: "苹果", heard: "平果") == 100)
        // 平翘舌、前后鼻音混淆宽松处理。
        #expect(SpeechPracticeScorer.score(target: "狮子", heard: "思子") == 100)
        #expect(SpeechPracticeScorer.score(target: "红色", heard: "红色。") == 100)
    }

    @Test func speechChinesePartialCountsForToddlers() {
        let partial = SpeechPracticeScorer.score(target: "我喜欢吃苹果", heard: "苹果")
        #expect(partial >= SpeechPracticeScorer.passScore)
        #expect(partial < 100)
        #expect(SpeechPracticeScorer.passes(partial))
        #expect(SpeechPracticeScorer.score(target: "苹果", heard: "香蕉") == 0)
        #expect(!SpeechPracticeScorer.passes(0))
    }

    @Test func speechEnglishLenient() {
        #expect(SpeechPracticeScorer.score(target: "Apple", heard: "apple") == 100)
        #expect(SpeechPracticeScorer.score(target: "elephant", heard: "elefant") == 100)
        #expect(SpeechPracticeScorer.score(target: "Red apple", heard: "apple") >= 40)
        #expect(SpeechPracticeScorer.score(target: "Red apple", heard: "apple") < 100)
        #expect(SpeechPracticeScorer.score(target: "dog", heard: "cat") == 0)
        #expect(SpeechPracticeScorer.score(target: "dog", heard: "") == 0)
    }

    @Test func speechLocaleAndTargetTrimming() {
        #expect(SpeechPracticeScorer.localeIdentifier(for: "红色") == "zh-CN")
        #expect(SpeechPracticeScorer.localeIdentifier(for: "Red") == "en-US")
        #expect(SpeechPracticeScorer.practiceTarget("Red! It's red.") == "Red")
        #expect(SpeechPracticeScorer.practiceTarget("小星星，亮晶晶") == "小星星")
        #expect(SpeechPracticeScorer.practiceTarget("  ") == nil)
        #expect(SpeechPracticeScorer.practiceTarget("This sentence is far too long for a toddler to say") == nil)
    }

    @Test func attemptUploadOmitsNilNote() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let plain = LearningAttemptUpload(id: "a", childId: "c", packId: "p", activityId: "x", kind: "speak")
        let text = String(decoding: try encoder.encode(plain), as: UTF8.self)
        #expect(!text.contains("note"))
        let scored = LearningAttemptUpload(id: "a", childId: "c", packId: "p", activityId: "x", kind: "speak",
                                           assistance: false, note: "score:85")
        #expect(String(decoding: try encoder.encode(scored), as: UTF8.self).contains("\"note\":\"score:85\""))
    }

    // MARK: 学习周报

    private func shanghai(_ day: String, hour: Int = 10) -> Date {
        BubuLearningDates.day(day)!.addingTimeInterval(TimeInterval(hour * 3600))
    }

    private func attempt(_ id: String, _ day: String, kind: String, event: String, correct: Bool? = nil,
                         note: String? = nil, concept: String? = nil, pack: String = "p1") -> LearningAttemptRecordDTO {
        LearningAttemptRecordDTO(id: id, packId: pack, activityId: id, createdAt: shanghai(day).timeIntervalSince1970,
                                 kind: kind, eventKind: event, correct: correct, note: note, concept: concept)
    }

    private func course(_ id: String, _ day: String, state: String) -> LearningCourseDTO {
        LearningCourseDTO(id: id, childId: "c", schoolDate: day, title: "课", kind: "teaching", language: "en-US",
                          createdAt: nil, state: state, sourceCount: 1, expectedFiles: 1, activityCount: 3, pack: nil)
    }

    @Test func weeklyReportAggregation() throws {
        // 2026-10-19 是周一。
        let weekStart = LearningWeeklySummary.weekStart(containing: shanghai("2026-10-22"))
        #expect(BubuLearningDates.dayString(weekStart) == "2026-10-19")
        let attempts = [
            attempt("1", "2026-10-19", kind: "listen_choice", event: "choice", correct: true, concept: "apple"),
            attempt("2", "2026-10-19", kind: "listen_choice", event: "choice", correct: false, concept: "apple"),
            attempt("3", "2026-10-21", kind: "color_choice", event: "choice", correct: true, concept: "red", pack: "p2"),
            attempt("4", "2026-10-21", kind: "speak", event: "speaking_attempt", note: "score:80", concept: "red", pack: "p2"),
            attempt("5", "2026-10-22", kind: "speak", event: "speaking_attempt", note: "score:60", concept: "apple"),
            attempt("6", "2026-10-22", kind: "speak", event: "speaking_attempt", note: "score:100", concept: "apple"),
            // 上一周，不计入。
            attempt("old", "2026-10-18", kind: "listen_choice", event: "choice", correct: true, concept: "dog", pack: "p0"),
        ]
        let courses = [course("c1", "2026-10-19", state: "published"), course("c2", "2026-10-21", state: "draft"),
                       course("c0", "2026-10-12", state: "published")]
        let activity = LearningActivityDTO(id: "x", kind: "speak", title: "说颜色", concept: "red", instruction: nil,
                                           correctChoice: nil, prompt: nil, answer: nil, choices: [])
        let review = [LearningReviewDTO.Item(packId: "p2", activityId: "x", concept: "red", reason: "上次需要提示", activity: activity),
                      LearningReviewDTO.Item(packId: "p2", activityId: "x", concept: "red", reason: "重复", activity: activity)]

        let summary = LearningWeeklySummary.make(weekStart: weekStart, courses: courses, attempts: attempts, review: review)
        #expect(summary.lessonsPublished == 1)
        #expect(summary.lessonsPracticed == 2)
        #expect(summary.activitiesDone == 6)
        #expect(summary.days.map(\.count) == [2, 0, 2, 2, 0, 0, 0])
        #expect(summary.activeDays == 3)
        let listen = try #require(summary.accuracy.first { $0.kind == "listen_choice" })
        #expect(listen.correct == 1 && listen.total == 2 && listen.percent == 50)
        #expect(summary.accuracy.first?.kind == "listen_choice")
        #expect(summary.speakScores.map(\.score) == [80, 80])
        #expect(summary.averageSpeakScore == 80)
        #expect(summary.words.first == "apple")
        #expect(Set(summary.words) == ["apple", "red"])
        #expect(summary.suggestions == [LearningWeeklySummary.Suggestion(title: "red", reason: "上次需要提示")])
    }

    @Test func attemptRecordDecodesScoreAndLenientTimestamp() throws {
        let json = #"{"items":[{"id":"a","pack_id":"p","activity_id":"x","created_at":1761100000.5,"kind":"speak","event_kind":"speaking_attempt","note":"score:85"},{"id":"b","created_at":"1761100000"}]}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let list = try decoder.decode(LearningAttemptRecordList.self, from: Data(json.utf8))
        #expect(list.items.count == 2)
        #expect(list.items[0].speakScore == 85)
        #expect(list.items[1].createdAt == 1_761_100_000)
        #expect(list.items[1].speakScore == nil)
    }

    // MARK: 上传 Live Activity 状态

    @Test func courseUploadPhaseMapping() {
        #expect(CourseUploadActivityPhase.from(courseState: "uploading") == .uploading)
        #expect(CourseUploadActivityPhase.from(courseState: "processing") == .parsing)
        #expect(CourseUploadActivityPhase.from(courseState: "waiting") == .parsing)
        #expect(CourseUploadActivityPhase.from(courseState: "draft") == .ready)
        #expect(CourseUploadActivityPhase.from(courseState: "published") == .ready)
        #expect(CourseUploadActivityPhase.from(courseState: "failed") == .failed)
        #expect(CourseUploadActivityPhase.from(courseState: "no_lesson") == .failed)
        #expect(CourseUploadActivityPhase.from(courseState: "mystery") == nil)
        #expect(CourseUploadActivityPhase.ready.isTerminal && CourseUploadActivityPhase.failed.isTerminal)
        #expect(!CourseUploadActivityPhase.parsing.isTerminal)
    }

    @Test func courseUploadPhaseText() {
        #expect(CourseUploadActivityPhase.compressing.text(progress: 0.424) == "压缩中 42%")
        #expect(CourseUploadActivityPhase.uploading.text(step: 2, steps: 3) == "上传中 2/3")
        #expect(CourseUploadActivityPhase.uploading.text(step: 1, steps: 1) == "上传中")
        #expect(CourseUploadActivityPhase.parsing.text() == "解析中")
        #expect(CourseUploadActivityPhase.ready.text() == "草稿可审核")
        // 进度条单调前进：压缩 → 上传 → 解析 → 完成。
        let values = [CourseUploadActivityPhase.compressing.overallProgress(progress: 1),
                      CourseUploadActivityPhase.uploading.overallProgress(step: 2, steps: 2),
                      CourseUploadActivityPhase.parsing.overallProgress(),
                      CourseUploadActivityPhase.ready.overallProgress()]
        #expect(values == values.sorted())
        #expect(values.last == 1)
    }

    // MARK: Siri 深链

    @Test func intentURLs() throws {
        let now = shanghai("2026-10-22")
        #expect(BubuIntentLinks.timeline(on: BubuIntentLinks.sameDayLastYear(from: now)).absoluteString
                == "bubu://moment?date=2025-10-22")
        #expect(BubuIntentLinks.learning(on: now).absoluteString == "bubu://learning?date=2026-10-22")
        // 闰日回落到 2 月 28 日。
        #expect(BubuIntentLinks.dayString(BubuIntentLinks.sameDayLastYear(from: shanghai("2028-02-29"))) == "2027-02-28")
        let ask = BubuIntentLinks.ask("  她第一次去海边是什么时候？1+1 ")
        let components = try #require(URLComponents(url: ask, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "bubu" && components.host == "ask")
        #expect(components.queryItems?.first { $0.name == "q" }?.value == "她第一次去海边是什么时候？1+1")
        #expect(!(ask.query(percentEncoded: true) ?? "").contains("+"))
        #expect(BubuIntentLinks.ask("   ").absoluteString == "bubu://ask")
        // 已有路由仍认得这些 host（时光、学习）。
        #expect(BubuRoute(host: URL(string: "bubu://moment?date=2025-10-22")?.host) == .moment)
        #expect(BubuRoute(host: BubuIntentLinks.learning(on: now).host) == .learning)
    }
}
