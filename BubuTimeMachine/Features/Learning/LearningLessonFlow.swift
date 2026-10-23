import Foundation

/// 2.29 课堂节奏（纯函数，便于测试）：开场白 → 每题「暖场 + 题目」→ 点选项先听名字再判定 →
/// 答对鼓励 / 答错温柔提示再试 → 结束语。所有声音交给同一个 `NativeLearningAudioPlayer` 依次播放。
nonisolated enum LearningLessonFlow {
    /// 答错几次后直接告诉答案：两岁半的孩子不该卡在一道题上。
    static let maxWrongTries = 2

    enum Style: Equatable, Sendable {
        case classic, callResponse, findIt, counting, singAlong

        /// 未知值按 classic 处理。
        init(_ raw: String?) {
            switch raw {
            case "call_response": self = .callResponse
            case "find_it": self = .findIt
            case "counting": self = .counting
            case "sing_along": self = .singAlong
            default: self = .classic
            }
        }
    }

    enum ChoiceOutcome: Equatable, Sendable {
        /// 找对啦：名字 + 鼓励。
        case correct
        /// 没找对：名字 + 温柔提示，再选一次。
        case retry
        /// 试过几次了：名字 + 老师的答案，正确选项亮起来。
        case reveal
    }

    enum TrailMark: Equatable, Sendable { case done, current, upcoming }

    static func style(_ activity: LearningActivityDTO) -> Style { Style(activity.style) }

    /// 胶囊上的玩法名：有明确玩法时用玩法名，否则用题型名。
    static func label(_ activity: LearningActivityDTO) -> String {
        switch style(activity) {
        case .classic: activity.kindLabel
        case .callResponse: "我说你说"
        case .findIt: "看一看，找一找"
        case .counting: "数一数"
        case .singAlong: "一起唱"
        }
    }

    /// 选择题也显示题目画面：找一找（find_it）通常要看着画面找。
    static func showsPromptImage(_ activity: LearningActivityDTO) -> Bool {
        guard activity.prompt?.imageUrl != nil else { return false }
        return !activity.isChoice || activity.kind == "speak" || style(activity) == .findIt
    }

    /// 进入一题时自动播一次：第一题前先放开场白，再暖场，最后是题目。
    static func openingCues(for activity: LearningActivityDTO, greeting: LearningLineDTO?) -> [NativeLearningCue?] {
        [NativeLearningCue.line(greeting), NativeLearningCue.line(activity.warmup), promptCue(activity)]
    }

    /// 「再听一次」只重放题目；没有题目声音时退回暖场。
    static func replayCues(for activity: LearningActivityDTO) -> [NativeLearningCue?] {
        [promptCue(activity) ?? NativeLearningCue.line(activity.warmup)]
    }

    static func promptCue(_ activity: LearningActivityDTO) -> NativeLearningCue? {
        NativeLearningCue.clip(activity.prompt, activityKind: activity.kind, isAnswer: false)
    }

    static func answerCue(_ activity: LearningActivityDTO) -> NativeLearningCue? {
        NativeLearningCue.clip(activity.answer, activityKind: activity.kind, isAnswer: true)
    }

    /// 没有标准答案的题（例如放一放）选什么都算完成。
    static func outcome(choiceID: String, correctChoice: String?, wrongTries: Int) -> ChoiceOutcome {
        guard let correctChoice, choiceID != correctChoice else { return .correct }
        return wrongTries + 1 >= maxWrongTries ? .reveal : .retry
    }

    /// 点了选项之后要说的话：先读选项名字，再判定。
    static func cues(for outcome: ChoiceOutcome, choice: LearningChoiceDTO,
                     activity: LearningActivityDTO) -> [NativeLearningCue?] {
        let name = NativeLearningCue.choice(choice)
        switch outcome {
        case .correct:
            // 只播一句鼓励，避免「答案 + 鼓励」重复太长；没有鼓励时用老师的答案。
            return [name, NativeLearningCue.line(activity.praise) ?? answerCue(activity)]
        case .retry:
            // 没有提示语就把题目再说一遍。
            return [name, NativeLearningCue.line(activity.retryHint) ?? promptCue(activity)]
        case .reveal:
            return [name, answerCue(activity) ?? NativeLearningCue.line(activity.praise)]
        }
    }

    /// 跟读/跟唱：说出来了就鼓励，没听清就温柔提示。
    static func speakCues(passed: Bool, activity: LearningActivityDTO) -> [NativeLearningCue?] {
        passed ? [NativeLearningCue.line(activity.praise)] : [NativeLearningCue.line(activity.retryHint)]
    }

    /// 这次反馈有没有自己的声音；有就不再叠加提示音，保证同一时刻只有一个声音。
    static func hasVoice(_ cues: [NativeLearningCue?]) -> Bool {
        cues.contains { $0 != nil }
    }

    static func trailMark(_ position: Int, current: Int) -> TrailMark {
        position < current ? .done : position == current ? .current : .upcoming
    }

    /// 选项的列数：大字号时少放几列，文字不被挤断。
    static func choiceColumns(count: Int, accessibilitySize: Bool) -> Int {
        max(1, min(count, accessibilitySize ? 2 : 3))
    }

    /// 答题页选项的列数：只用偶数列（2 或 4），三个选项排成 2+1，避免单独一张正好落在正中（书本折痕）上。
    /// 答题块够宽（≥ 600pt，如桌面半折的下半屏、iPad）且不是大字号时一行 4 个。
    static func evenChoiceColumns(count: Int, width: CGFloat, accessibilitySize: Bool) -> Int {
        guard count > 1 else { return 1 }
        return count >= 3 && !accessibilitySize && width >= 600 ? 4 : 2
    }
}
