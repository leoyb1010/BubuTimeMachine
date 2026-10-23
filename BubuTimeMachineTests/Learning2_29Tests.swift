import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 2.29 互动与声音：可选字段解码 + 课堂节奏

@MainActor
struct Learning2_29Tests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: Data(json.utf8))
    }

    private let newPayload = """
    {"title": "10.22", "summary": "s", "warnings": [],
     "greeting": {"text": "Hi 布布！", "audio_url": "/learning/api/packs/p/resources/g.m4a"},
     "closing": {"text": "明天再玩！", "audio_url": null},
     "activities": [{
       "id": "a1", "kind": "listen_choice", "title": "找苹果", "concept": "apple", "instruction": null,
       "correct_choice": "apple", "style": "find_it",
       "warmup": {"text": "看！这是什么呀？", "audio_url": "/w.m4a"},
       "praise": {"text": "Yes! Apple! 太棒啦！", "audio_url": "/p.m4a"},
       "retry_hint": {"text": "再听一听", "audio_url": "/r.m4a"},
       "prompt": {"role": "cue", "text": "Where is the apple?", "audio_url": "/q.m4a", "image_url": "/i.jpg"},
       "answer": {"role": "answer", "text": "Yes! Apple!", "audio_url": "/a.m4a"},
       "choices": [{"id": "apple", "label": "apple", "image_url": null, "audio_url": "/c1.m4a"},
                   {"id": "umbrella", "label": "☂️ umbrella", "image_url": null, "audio_url": null}]}]}
    """

    private let oldPayload = """
    {"title": "10.20", "summary": "s", "warnings": [],
     "activities": [{"id": "a1", "kind": "speak", "title": "说颜色", "concept": "red", "instruction": null,
                     "correct_choice": null, "prompt": {"role": "cue", "text": "red", "audio_url": "/q.m4a"},
                     "answer": null, "choices": []}]}
    """

    // MARK: 解码

    @Test func decodesAll229Fields() throws {
        let payload = try decode(LearningPackDTO.Payload.self, newPayload)
        #expect(payload.greeting == LearningLineDTO(text: "Hi 布布！", audioUrl: "/learning/api/packs/p/resources/g.m4a"))
        #expect(payload.closing?.text == "明天再玩！")
        #expect(payload.closing?.audioUrl == nil)
        let activity = try #require(payload.activities.first)
        #expect(activity.style == "find_it")
        #expect(activity.warmup?.audioUrl == "/w.m4a")
        #expect(activity.praise?.text == "Yes! Apple! 太棒啦！")
        #expect(activity.retryHint?.audioUrl == "/r.m4a")
        #expect(activity.choices.map(\.audioUrl) == ["/c1.m4a", nil])
    }

    @Test func oldPackStillDecodes() throws {
        let payload = try decode(LearningPackDTO.Payload.self, oldPayload)
        #expect(payload.greeting == nil && payload.closing == nil)
        let activity = try #require(payload.activities.first)
        #expect(activity.style == nil && activity.warmup == nil && activity.praise == nil && activity.retryHint == nil)
    }

    @Test func nullFieldsDecodeLikeMissing() throws {
        let json = """
        {"title": "t", "summary": "", "warnings": [], "greeting": null, "closing": null,
         "activities": [{"id": "a", "kind": "music", "title": "唱", "concept": null, "instruction": null,
                         "correct_choice": null, "style": null, "warmup": null, "praise": null, "retry_hint": null,
                         "prompt": null, "answer": null, "choices": [{"id": "x", "label": "x", "audio_url": null}]}]}
        """
        let payload = try decode(LearningPackDTO.Payload.self, json)
        #expect(payload.greeting == nil)
        #expect(payload.activities[0].retryHint == nil)
        #expect(payload.activities[0].choices[0].audioUrl == nil)
    }

    @Test func lineWithoutTextStillDecodes() throws {
        let line = try decode(LearningLineDTO.self, #"{"audio_url": "/x.m4a"}"#)
        #expect(line.text.isEmpty)
        #expect(NativeLearningCue.line(line)?.path == "/x.m4a")
    }

    // MARK: 声音

    @Test func cuesSkipMissingAudio() throws {
        #expect(NativeLearningCue.line(nil) == nil)
        #expect(NativeLearningCue.line(LearningLineDTO(text: "hi", audioUrl: "")) == nil)
        let activity = try decode(LearningPackDTO.Payload.self, newPayload).activities[0]
        #expect(NativeLearningCue.choice(activity.choices[0]) == NativeLearningCue(path: "/c1.m4a", kind: .choice("apple")))
        #expect(NativeLearningCue.choice(activity.choices[1]) == nil)
    }

    @Test func teacherClipsStillFollowPolicy() {
        // 答案片段不能当题目自动播放。
        let answer = LearningClipDTO(sourceId: nil, segmentId: nil, role: "answer", text: "x", start: nil, end: nil,
                                     audioUrl: "/a.m4a", imageUrl: nil)
        #expect(NativeLearningCue.clip(answer, activityKind: "speak", isAnswer: false) == nil)
        #expect(NativeLearningCue.clip(answer, activityKind: "speak", isAnswer: true)?.kind == .answer)
    }

    @Test func openingPlaysGreetingWarmupThenPrompt() throws {
        let payload = try decode(LearningPackDTO.Payload.self, newPayload)
        let activity = payload.activities[0]
        let paths = LearningLessonFlow.openingCues(for: activity, greeting: payload.greeting).compactMap { $0?.path }
        #expect(paths == ["/learning/api/packs/p/resources/g.m4a", "/w.m4a", "/q.m4a"])
        // 之后的题不再说开场白。
        #expect(LearningLessonFlow.openingCues(for: activity, greeting: nil).compactMap { $0?.path } == ["/w.m4a", "/q.m4a"])
        #expect(LearningLessonFlow.replayCues(for: activity).compactMap { $0?.path } == ["/q.m4a"])
    }

    // MARK: 选择题节奏

    @Test func wrongAnswerRetriesThenReveals() {
        #expect(LearningLessonFlow.outcome(choiceID: "apple", correctChoice: "apple", wrongTries: 0) == .correct)
        #expect(LearningLessonFlow.outcome(choiceID: "pear", correctChoice: "apple", wrongTries: 0) == .retry)
        #expect(LearningLessonFlow.outcome(choiceID: "kiwi", correctChoice: "apple", wrongTries: 1) == .reveal)
        // 没有标准答案：选什么都算完成。
        #expect(LearningLessonFlow.outcome(choiceID: "any", correctChoice: nil, wrongTries: 0) == .correct)
    }

    @Test func choiceNameComesFirstThenFeedback() throws {
        let activity = try decode(LearningPackDTO.Payload.self, newPayload).activities[0]
        let apple = activity.choices[0], umbrella = activity.choices[1]
        #expect(LearningLessonFlow.cues(for: .correct, choice: apple, activity: activity).compactMap { $0?.path } == ["/c1.m4a", "/p.m4a"])
        #expect(LearningLessonFlow.cues(for: .retry, choice: umbrella, activity: activity).compactMap { $0?.path } == ["/r.m4a"])
        #expect(LearningLessonFlow.cues(for: .reveal, choice: umbrella, activity: activity).compactMap { $0?.path } == ["/a.m4a"])
    }

    @Test func oldPackFallsBackToTeacherClips() throws {
        let json = """
        {"id": "a", "kind": "listen_choice", "title": "t", "concept": null, "instruction": null, "correct_choice": "a",
         "prompt": {"role": "cue", "text": "q", "audio_url": "/q.m4a"},
         "answer": {"role": "answer", "text": "a", "audio_url": "/a.m4a"},
         "choices": [{"id": "a", "label": "a"}, {"id": "b", "label": "b"}]}
        """
        let activity = try decode(LearningActivityDTO.self, json)
        #expect(LearningLessonFlow.cues(for: .correct, choice: activity.choices[0], activity: activity).compactMap { $0?.path } == ["/a.m4a"])
        // 没有温柔提示就把题目再说一遍。
        #expect(LearningLessonFlow.cues(for: .retry, choice: activity.choices[1], activity: activity).compactMap { $0?.path } == ["/q.m4a"])
        #expect(LearningLessonFlow.speakCues(passed: true, activity: activity).allSatisfy { $0 == nil })
        #expect(!LearningLessonFlow.hasVoice(LearningLessonFlow.speakCues(passed: false, activity: activity)))
    }

    // MARK: 展示

    @Test func styleLabelsAndImages() throws {
        #expect(LearningLessonFlow.Style("sing_along") == .singAlong)
        #expect(LearningLessonFlow.Style("something_new") == .classic)
        #expect(LearningLessonFlow.Style(nil) == .classic)
        let activity = try decode(LearningPackDTO.Payload.self, newPayload).activities[0]
        #expect(LearningLessonFlow.label(activity) == "看一看，找一找")
        // 找一找的选择题也要显示题目画面。
        #expect(LearningLessonFlow.showsPromptImage(activity))
    }

    @Test func progressTrailAndColumns() {
        #expect(LearningLessonFlow.trailMark(0, current: 2) == .done)
        #expect(LearningLessonFlow.trailMark(2, current: 2) == .current)
        #expect(LearningLessonFlow.trailMark(3, current: 2) == .upcoming)
        #expect(LearningLessonFlow.choiceColumns(count: 4, accessibilitySize: false) == 3)
        #expect(LearningLessonFlow.choiceColumns(count: 4, accessibilitySize: true) == 2)
        #expect(LearningLessonFlow.choiceColumns(count: 0, accessibilitySize: false) == 1)
    }
}
