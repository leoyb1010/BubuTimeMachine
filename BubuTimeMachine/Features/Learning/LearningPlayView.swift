import SwiftUI
import UIKit

struct LearningPlayItem: Hashable, Identifiable {
    let packID: String
    let activity: LearningActivityDTO
    var id: String { packID + "/" + activity.id }
}

/// 布布的互动页（给两岁半的孩子：大、开心、可以犯错）。
/// 开场白 → 每题自动播一次「暖场 + 题目」→ 点选项先听名字再判定（答对鼓励，答错温柔提示再选一次）→ 结束语。
/// 所有声音都走同一个播放器，不会叠在一起；离开页面或切到后台立刻停。
/// 不给孩子打分数，只记录第一次的选择，供周/月复习挑选需要再玩一次的内容；
/// 跟读（「跟我说」）的宽松分数只写进记录备注，界面上只出现星星和鼓励。
struct LearningPlayView: View {
    let client: BubuLearningClient
    let childID: String?
    let items: [LearningPlayItem]
    let title: String
    /// 2.29 开场白 / 结束语（复习没有）。
    var greeting: LearningLineDTO? = nil
    var closing: LearningLineDTO? = nil
    @State private var index = 0
    @State private var chosen: String?
    @State private var wrongIDs: Set<String> = []
    @State private var outcome: LearningLessonFlow.ChoiceOutcome?
    @State private var answered = false
    @State private var recorded = false
    @State private var wiggle = 0
    @State private var celebration = 0
    @State private var greeted = false
    @State private var player = NativeLearningAudioPlayer()
    /// 答题块的实际尺寸：决定选项列数、选项卡紧凑与否、合上横拿时题目和选项是否左右并排。
    @State private var answerPaneSize: CGSize = .zero
    @State private var hingeStatus: BubuHingeStatus?
    @State private var hingeNudge = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let nextAnchor = "learning.play.next-anchor"

    private var current: LearningPlayItem? { items.indices.contains(index) ? items[index] : nil }

    var body: some View {
        NavigationStack {
            ZStack {
                BubuThemedBackground().ignoresSafeArea()
                if let current {
                    LearningPlayLayoutReader { layout in
                        stage(current, short: layout.isShort)
                    }
                    .id(current.id)
                } else {
                    ScrollView {
                        finished.frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .defaultScrollAnchor(.center, for: .alignment)
                }
            }
            // 小路放在内容顶部（不占工具栏正中），工具栏竖排到侧边时也一直看得见。
            .safeAreaInset(edge: .top, spacing: 0) {
                progressTrail
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BubuTheme.Spacing.s)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { player.stop(); dismiss() }
                        .accessibilityLabel("结束")
                        .accessibilityIdentifier("learning.play.close")
                }
            }
        }
        .bubuLayoutRoot()
        // 铰链只配一个小动画：放到桌上半折时「再听一次」的小耳朵跳一下；布局只看尺寸和折痕。
        .bubuOnHingeChange { status, _ in
            guard status != hingeStatus else { return }
            hingeStatus = status
            if status == .partiallyOpen, !reduceMotion { hingeNudge += 1 }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { player.stop() } }
        .onDisappear { player.stop() }
        .task(id: index) {
            chosen = nil; wrongIDs = []; outcome = nil; answered = false; recorded = false
            guard let current else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            // 开场白只在第一题前说一次。
            let opening = greeted ? nil : greeting
            greeted = true
            player.play(LearningLessonFlow.openingCues(for: current.activity, greeting: opening), client: client)
        }
    }

    // MARK: Stage

    /// 页面根不滚动，用系统分栏放「题图块」和「答题块」，滚动只发生在块内部。
    /// 分栏规则（ArrangementView）：主块在前（横向时左、纵向时上），副块在后；合上横拿时系统只显示主块。
    /// - 一般情况：主块 = 题目 + 再听一次 + 题图，副块 = 选项 / 跟读 + 下一个 → 横拿左图右按钮，竖拿上图下按钮，
    ///   桌面半折上半屏题图、下半屏大按钮，书本半折各占一侧。
    /// - 矮屏（合上横拿 / 普通 iPhone 横拿）：主块 = 题目 + 再听一次 + 选项（系统只显示它时也能完整答题），
    ///   副块只放题图。
    /// 只有一个 ArrangementView、在块里分支：旋转进出矮屏时分栏容器不重建。
    private func stage(_ item: LearningPlayItem, short: Bool) -> some View {
        BubuArrangement(axes: [.horizontal, .vertical], style: .split) {
            if short { answerPane(item, withHeader: true) } else { promptPane(item) }
        } secondary: {
            if short { mediaPane(item.activity) } else { answerPane(item, withHeader: false) }
        }
    }

    /// 题目 + 题图：题图按这一块的剩余高度取最大的一档，都放不下时在块内滚动。
    private func promptPane(_ item: LearningPlayItem) -> some View {
        ViewThatFits(in: .vertical) {
            promptStack(item, mediaHeight: 300)
            promptStack(item, mediaHeight: 220)
            promptStack(item, mediaHeight: 150)
            ScrollView { promptStack(item, mediaHeight: 120) }
                .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func promptStack(_ item: LearningPlayItem, mediaHeight: CGFloat) -> some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            header(item.activity, includesLyrics: false)
            promptMedia(item.activity, height: mediaHeight, showsLyrics: true)
        }
        .padding(BubuTheme.Spacing.l)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    /// 矮屏的副块：只放题图（或唱歌的舞台），铺满这一块。
    @ViewBuilder
    private func mediaPane(_ activity: LearningActivityDTO) -> some View {
        Group {
            if activity.kind == "music" {
                ScrollView {
                    promptMedia(activity, height: 180, showsLyrics: false)
                }
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.center, for: .alignment)
            } else if LearningLessonFlow.showsPromptImage(activity), let image = activity.prompt?.imageUrl {
                LearningRemoteImage(path: image, client: client, label: "上课时的画面")
                    .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            } else {
                BubuMascotBadge(size: 120, expression: .happy)
                    .bubuBreathingWiggle(degrees: player.playingLine ? 3 : 1)
                    .accessibilityHidden(true)
            }
        }
        .padding(BubuTheme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func promptMedia(_ activity: LearningActivityDTO, height: CGFloat, showsLyrics: Bool) -> some View {
        if activity.kind == "music" {
            SingAlongStage(lyrics: showsLyrics ? activity.prompt?.text : nil, image: activity.prompt?.imageUrl,
                           client: client, singing: player.playingPrompt && player.isPlaying,
                           progress: player.progress, imageHeight: height)
        } else if LearningLessonFlow.showsPromptImage(activity), let image = activity.prompt?.imageUrl {
            LearningRemoteImage(path: image, client: client, label: "上课时的画面", maxHeight: height)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        }
    }

    /// 答题块：选项 / 跟读 / 一起唱 + 下一个（矮屏时连题目和再听一次一起）。内容多时块内滚动，答完自动滚到「下一个」。
    private func answerPane(_ item: LearningPlayItem, withHeader: Bool) -> some View {
        let padding = BubuTheme.Spacing.l
        // 合上横拿只显示主块时宽度够：题目在左、选项在右，主要按钮不用滚动。
        let sideBySide = withHeader && answerPaneSize.width >= 560
        let contentWidth = max(0, min(answerPaneSize.width, sideBySide ? 900 : 640) - padding * 2)
        let choiceWidth = sideBySide ? (contentWidth - padding) / 2 : contentWidth
        let arrangement = sideBySide
            ? AnyLayout(HStackLayout(alignment: .center, spacing: padding))
            : AnyLayout(VStackLayout(spacing: padding))
        return ScrollViewReader { proxy in
            ScrollView {
                arrangement {
                    if withHeader { header(item.activity, includesLyrics: true) }
                    answers(item, choiceWidth: choiceWidth)
                }
                .padding(padding)
                .frame(maxWidth: sideBySide ? 900 : 640)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center, for: .alignment)
            .onChange(of: answered) { _, done in
                guard done else { return }
                // 等「下一个」出现在布局里再滚过去。
                Task { @MainActor in
                    withAnimation(BubuMotion.allowed(BubuMotion.gentle, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(Self.nextAnchor, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { answerPaneSize = $0 }
    }

    // MARK: Activity

    /// 题型标签、题目、（没有声音时家长念的）题目文字、再听一次。
    private func header(_ activity: LearningActivityDTO, includesLyrics: Bool) -> some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            if index == 0, let greeting, !greeting.text.isEmpty {
                MascotBubble(text: greeting.text, expression: .happy, speaking: player.playingLine)
            }
            Text(LearningLessonFlow.label(activity)).font(BubuTheme.Font.caption.weight(.bold))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(BubuTheme.Color.pinkSurface, in: Capsule())
                .foregroundStyle(BubuTheme.Color.deepRose)
            Text(activity.title).font(BubuTheme.Font.hugeTitle).foregroundStyle(BubuTheme.Color.warmBrown)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // 没有声音时题目文字就是家长念给布布听的那句；儿歌的歌词平时在唱歌舞台上，舞台不显示时放这里。
            if let text = activity.prompt?.text, !text.isEmpty, activity.kind != "music" || includesLyrics {
                Text(text).font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            listenButton(activity)
            if let error = player.errorText {
                Label(error, systemImage: "speaker.slash")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func answers(_ item: LearningPlayItem, choiceWidth: CGFloat) -> some View {
        let activity = item.activity
        VStack(spacing: BubuTheme.Spacing.l) {
            if activity.isChoice {
                choices(item, width: choiceWidth)
                // 选完后可以跟着说一遍正确答案（只庆祝，不另记一次互动）。
                if answered, let target = Self.choiceTarget(activity) {
                    SpeakPracticeCard(target: target, player: player, playModel: { playAnswer(activity) }) { _, _ in }
                }
            } else if activity.kind == "speak" {
                speak(item)
            } else {
                if let target = SpeechPracticeScorer.practiceTarget(activity.prompt?.text) {
                    // 儿歌：跟唱一句也算一起唱完了。
                    SpeakPracticeCard(target: target, player: player, playModel: {
                        player.play(LearningLessonFlow.replayCues(for: activity), client: client)
                    }, chime: !Self.speakHasVoice(activity, passed: true)) { score, passed in
                        feedbackAfterSpeaking(activity, passed: passed)
                        guard passed, !answered else { return }
                        answered = true
                        record(item, choice: nil, assistance: nil, note: "score:\(score)")
                    }
                }
                participation(item, label: "一起唱完啦")
            }
            if answered { nextButton.id(Self.nextAnchor) }
        }
        .frame(maxWidth: .infinity)
    }

    /// 大大的「再听一次」：只重放题目（儿歌重放原片那一句）。
    private func listenButton(_ activity: LearningActivityDTO) -> some View {
        let speaking = player.isPlaying && player.playingPrompt
        let title = activity.kind == "music" ? "再听一遍" : "再听一次"
        return Button {
            BubuHaptics.tapLight()
            player.play(LearningLessonFlow.replayCues(for: activity), client: client)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: speaking ? "speaker.wave.3.fill" : "ear.fill")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .symbolEffect(.variableColor.iterative, isActive: speaking && !reduceMotion)
                    .symbolEffect(.bounce, value: hingeNudge)
                    .accessibilityHidden(true)
                Text(title).font(BubuTheme.Font.title)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 32).padding(.vertical, 18)
            .frame(maxWidth: 360, minHeight: 76)
            .background(BubuTheme.Gradient.primaryButton, in: Capsule())
            .shadow(color: BubuTheme.Color.primary.opacity(0.3), radius: 10, y: 5)
        }
        .buttonStyle(BubuPressableStyle(scale: 0.94))
        .disabled(LearningLessonFlow.replayCues(for: activity).allSatisfy { $0 == nil })
        .accessibilityLabel(title)
        .accessibilityHint(activity.kind == "music" ? "再放一遍这句歌" : "再听一遍题目")
        .accessibilityIdentifier("learning.play.listen")
    }

    private func choices(_ item: LearningPlayItem, width: CGFloat) -> some View {
        let activity = item.activity
        // 偶数列（2 或 4）：三个选项是 2+1，单独那张靠前排，不会正好落在中间（折痕）上。
        let columns = LearningLessonFlow.evenChoiceColumns(count: activity.choices.count, width: width,
                                                           accessibilitySize: dynamicTypeSize.isAccessibilitySize)
        // 答题块矮（合上横拿、竖拿一半、桌面半折）时用紧凑选项卡，两行也放得下。
        let compact = answerPaneSize.height < 480
        return VStack(spacing: BubuTheme.Spacing.m) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(maximum: 280), spacing: 14), count: columns),
                      spacing: 14) {
                ForEach(activity.choices) { choice in
                    let revealed = answered && choice.id == activity.correctChoice
                    Button { tap(choice, in: item) } label: {
                        ChoiceTile(choice: choice, client: client,
                                   highlighted: revealed,
                                   dimmed: wrongIDs.contains(choice.id) && !revealed,
                                   compact: compact)
                            .overlay {
                                if revealed && outcome == .correct && !reduceMotion {
                                    BubuBurst(count: 14, radius: 90).id(celebration).allowsHitTesting(false)
                                }
                            }
                            .scaleEffect(player.playingChoiceID == choice.id && !reduceMotion ? 1.04 : 1)
                            .animation(BubuMotion.allowed(BubuMotion.quick, reduceMotion: reduceMotion),
                                       value: player.playingChoiceID == choice.id)
                            // 没找对轻轻摇一下；减弱动态效果时不摇，只靠选项变淡 + 温柔提示。
                            .phaseAnimator([0.0, -8.0, 8.0, -4.0, 0.0], trigger: chosen == choice.id ? wiggle : 0) { view, x in
                                view.offset(x: reduceMotion ? 0 : x)
                            } animation: { _ in .spring(duration: 0.14) }
                    }
                    .buttonStyle(BubuPressableStyle(scale: 0.94))
                    .accessibilityHint(answered ? "点一下听名字" : "点一下听名字，也就是选它")
                    .accessibilityIdentifier("learning.play.choice")
                }
            }
            choiceFeedback(activity)
        }
    }

    @ViewBuilder
    private func choiceFeedback(_ activity: LearningActivityDTO) -> some View {
        if let outcome {
            let (text, symbol, line): (String, String, String?) = switch outcome {
            case .correct: ("找对啦！", "star.fill", activity.praise?.text)
            case .retry: ("再找找看～", "heart.fill", activity.retryHint?.text)
            case .reveal: ("是这个哦！", "heart.fill", activity.answer?.text)
            }
            VStack(spacing: 6) {
                Label(text, systemImage: symbol)
                    .font(BubuTheme.Font.title)
                    .foregroundStyle(outcome == .correct ? BubuTheme.Color.deepRose : BubuTheme.Color.warmBrown)
                if let line, !line.isEmpty {
                    Text(line).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if answered, LearningLessonFlow.answerCue(activity) != nil {
                    Button {
                        player.play([LearningLessonFlow.answerCue(activity)], client: client)
                    } label: { Label("听老师说答案", systemImage: "speaker.wave.2") }
                        .buttonStyle(.bordered).tint(BubuTheme.Color.deepRose)
                }
            }
            .id(outcome == .retry ? "retry-\(wrongIDs.count)" : "done")
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
            .accessibilityElement(children: .combine)
        }
    }

    /// 点选项：先听名字；还没答完时同时判定。答完后再点只听名字。
    private func tap(_ choice: LearningChoiceDTO, in item: LearningPlayItem) {
        let activity = item.activity
        guard !answered, !wrongIDs.contains(choice.id) else {
            BubuHaptics.selection()
            player.play([NativeLearningCue.choice(choice)], client: client)
            return
        }
        if !recorded {
            recorded = true
            record(item, choice: choice.id, assistance: nil)
        }
        let result = LearningLessonFlow.outcome(choiceID: choice.id, correctChoice: activity.correctChoice,
                                                wrongTries: wrongIDs.count)
        let cues = LearningLessonFlow.cues(for: result, choice: choice, activity: activity)
        withAnimation(BubuMotion.allowed(BubuMotion.quick, reduceMotion: reduceMotion)) {
            chosen = choice.id
            outcome = result
            switch result {
            case .correct:
                answered = true
                celebration += 1
            case .retry:
                wrongIDs.insert(choice.id)
            case .reveal:
                wrongIDs.insert(choice.id)
                answered = true
            }
        }
        switch result {
        case .correct:
            BubuHaptics.success()
            if !LearningLessonFlow.hasVoice(cues) { BubuSound.play(.milestone) }
        case .retry, .reveal:
            wiggle += 1
            BubuHaptics.tapLight()
        }
        player.play(cues, client: client)
        if UIAccessibility.isVoiceOverRunning {
            let spoken = switch result {
            case .correct: activity.praise?.text ?? "找对啦！"
            case .retry: activity.retryHint?.text ?? "再找找看"
            case .reveal: "是\(activity.choices.first { $0.id == activity.correctChoice }?.label ?? "这个")哦"
            }
            UIAccessibility.post(notification: .announcement, argument: spoken)
        }
    }

    private func speak(_ item: LearningPlayItem) -> some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            Text("轮到布布说一说啦").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            if let target = Self.speakTarget(item.activity) {
                // 端侧识别不支持该语言时卡片自己隐藏，下面家长代点的按钮照常可用。
                SpeakPracticeCard(target: target, player: player, playModel: { playAnswer(item.activity) },
                                  chime: !Self.speakHasVoice(item.activity, passed: true)) { score, passed in
                    feedbackAfterSpeaking(item.activity, passed: passed)
                    guard passed, !answered else { return }
                    answered = true
                    record(item, choice: nil, assistance: false, note: "score:\(score)")
                }
            }
            if answered {
                if let praise = item.activity.praise?.text, !praise.isEmpty {
                    Label(praise, systemImage: "star.fill").font(BubuTheme.Font.headline)
                        .foregroundStyle(BubuTheme.Color.deepRose).multilineTextAlignment(.center)
                }
                Button {
                    player.play([LearningLessonFlow.answerCue(item.activity)], client: client)
                } label: { Label("听老师的示范", systemImage: "speaker.wave.2") }
                    .buttonStyle(.bordered).tint(BubuTheme.Color.deepRose)
            } else {
                // 大字号下两个大按钮并排放不下时改成上下排，文字不被截断。
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: BubuTheme.Spacing.m) { speakButtons(item) }
                    VStack(spacing: BubuTheme.Spacing.m) { speakButtons(item) }
                }
            }
        }
    }

    @ViewBuilder
    private func speakButtons(_ item: LearningPlayItem) -> some View {
        bigChoice("说出来啦", symbol: "face.smiling.fill", tint: BubuTheme.Color.actionFill) {
            answered = true; record(item, choice: nil, assistance: false)
            player.play(LearningLessonFlow.speakCues(passed: true, activity: item.activity), client: client)
        }
        bigChoice("要听提示", symbol: "lightbulb.fill", tint: BubuTheme.Color.butterSurface, foreground: BubuTheme.Color.warmBrown) {
            answered = true; record(item, choice: nil, assistance: true)
            player.play([LearningLessonFlow.answerCue(item.activity)], client: client)
        }
    }

    private func feedbackAfterSpeaking(_ activity: LearningActivityDTO, passed: Bool) {
        player.play(LearningLessonFlow.speakCues(passed: passed, activity: activity), client: client)
    }

    private static func speakHasVoice(_ activity: LearningActivityDTO, passed: Bool) -> Bool {
        LearningLessonFlow.hasVoice(LearningLessonFlow.speakCues(passed: passed, activity: activity))
    }

    private func playAnswer(_ activity: LearningActivityDTO) {
        player.play([LearningLessonFlow.answerCue(activity) ?? LearningLessonFlow.promptCue(activity)], client: client)
    }

    /// 跟老师说：优先老师的示范答案，其次知识点、题目原声。
    static func speakTarget(_ activity: LearningActivityDTO) -> String? {
        SpeechPracticeScorer.practiceTarget(activity.answer?.text)
            ?? SpeechPracticeScorer.practiceTarget(activity.concept)
            ?? SpeechPracticeScorer.practiceTarget(activity.prompt?.text)
    }

    /// 找一找答对后跟着说：正确选项的名字（颜色块也有名字）。
    static func choiceTarget(_ activity: LearningActivityDTO) -> String? {
        guard let correct = activity.choices.first(where: { $0.id == activity.correctChoice }) else { return nil }
        return SpeechPracticeScorer.practiceTarget(correct.label)
    }

    private func participation(_ item: LearningPlayItem, label: String) -> some View {
        Group {
            if !answered {
                bigChoice(label, symbol: "music.note", tint: BubuTheme.Color.mintSurface, foreground: BubuTheme.Color.warmBrown) {
                    answered = true; record(item, choice: nil, assistance: nil)
                    let cues = LearningLessonFlow.speakCues(passed: true, activity: item.activity)
                    if LearningLessonFlow.hasVoice(cues) { player.play(cues, client: client) }
                }
            }
        }
    }

    private func bigChoice(_ title: String, symbol: String, tint: Color, foreground: Color = .white,
                           action: @escaping () -> Void) -> some View {
        Button { BubuHaptics.tapLight(); action() } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 40, weight: .semibold, design: .rounded))
                    .symbolEffect(.bounce, value: answered)
                    .accessibilityHidden(true)
                Text(title).font(BubuTheme.Font.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 128)
            .background(tint, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .shadow(color: BubuTheme.Color.deepRose.opacity(0.12), radius: 8, y: 4)
        }
        .buttonStyle(BubuPressableStyle(scale: 0.95))
        .accessibilityLabel(title)
    }

    private var nextButton: some View {
        Button {
            player.stop()
            withAnimation(BubuMotion.allowed(BubuMotion.gentle, reduceMotion: reduceMotion)) { index += 1 }
        } label: {
            Text(index + 1 < items.count ? "下一个" : "完成").font(BubuTheme.Font.title)
                .frame(maxWidth: 320, minHeight: 60)
                .foregroundStyle(BubuTheme.Color.deepRose)
                .background(BubuTheme.Color.card, in: Capsule())
                .overlay(Capsule().stroke(BubuTheme.Color.primary, lineWidth: 3))
        }
        .buttonStyle(BubuPressableStyle(scale: 0.95))
        .accessibilityIdentifier("learning.play.next")
    }

    /// 小路：走过的变成星星，正在玩的是小脚印，后面的是空圈。
    private var progressTrail: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                let mark = LearningLessonFlow.trailMark(i, current: index)
                Image(systemName: mark == .done ? "star.fill" : mark == .current ? "shoeprints.fill" : "circle")
                    .font(.system(size: mark == .current ? 15 : 11, weight: .bold))
                    .foregroundStyle(mark == .upcoming ? BubuTheme.Color.hairline
                                     : mark == .done ? BubuTheme.Color.butter : BubuTheme.Color.primary)
                    .symbolEffect(.bounce, value: mark == .done && !reduceMotion)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(index < items.count ? "第 \(index + 1) 个，共 \(items.count) 个" : "全部完成，共 \(items.count) 个")
    }

    private var finished: some View {
        VStack(spacing: BubuTheme.Spacing.l) {
            Button {
                player.play([NativeLearningCue.line(closing)], client: client)
            } label: {
                BubuMascotBadge(size: 132, expression: .yeah)
                    .overlay { if !reduceMotion { BubuBurst(count: 22, radius: 150) } }
                    .bubuBreathingWiggle(degrees: player.playingLine ? 3 : 1)
            }
            .buttonStyle(.plain)
            .disabled(NativeLearningCue.line(closing) == nil)
            .accessibilityLabel("布布")
            .accessibilityHint(NativeLearningCue.line(closing) == nil ? "" : "再听一次结束语")
            Text("今天学完啦！").font(BubuTheme.Font.hugeTitle).foregroundStyle(BubuTheme.Color.warmBrown)
            if let closing, !closing.text.isEmpty {
                SpeechBubble(text: closing.text)
            }
            HStack(spacing: 6) {
                ForEach(0..<min(items.count, 8), id: \.self) { _ in
                    Image(systemName: "star.fill").foregroundStyle(BubuTheme.Color.butter)
                }
            }
            .font(.title2)
            .accessibilityHidden(true)
            Text("和老师一起玩了 \(items.count) 个小互动").font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            Button("回到课程") { player.stop(); dismiss() }.buttonStyle(.borderedProminent).tint(BubuTheme.Color.actionFill)
                .font(BubuTheme.Font.headline)
                .accessibilityIdentifier("learning.play.done")
        }
        .padding()
        .onAppear {
            BubuHaptics.success()
            if let cue = NativeLearningCue.line(closing) {
                player.play([cue], client: client)
            } else {
                BubuSound.play(.milestone)
            }
        }
    }

    private func record(_ item: LearningPlayItem, choice: String?, assistance: Bool?, note: String? = nil) {
        guard let childID else { return }
        let body = LearningAttemptUpload(id: UUID().uuidString, childId: childID, packId: item.packID,
                                         activityId: item.activity.id, kind: item.activity.kind,
                                         choice: choice, assistance: assistance, note: note)
        Task { await LearningAttemptOutbox.shared.submit(body, client: client) }
    }
}

/// 读取答题页布局根（`.bubuLayoutRoot()`）下发的尺寸。
private struct LearningPlayLayoutReader<Content: View>: View {
    @Environment(\.bubuLayout) private var layout
    @ViewBuilder let content: (BubuLayout) -> Content

    var body: some View { content(layout) }
}

/// 布布（星星姐姐）说话的气泡：开场白、结束语。
private struct MascotBubble: View {
    let text: String
    let expression: BubuExpression
    let speaking: Bool

    var body: some View {
        HStack(alignment: .center, spacing: BubuTheme.Spacing.m) {
            BubuMascotBadge(size: 72, expression: expression)
                .bubuBreathingWiggle(degrees: speaking ? 3 : 1)
                .accessibilityHidden(true)
            SpeechBubble(text: text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(BubuTheme.Font.headline)
            .foregroundStyle(BubuTheme.Color.warmBrown)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
                .stroke(BubuTheme.Color.pinkSurface, lineWidth: 2))
    }
}

/// 一起唱：放原片那一句时，布布跟着摇、音符跳起来，歌词大大地显示；进度条跟着走。
private struct SingAlongStage: View {
    let lyrics: String?
    let image: String?
    let client: BubuLearningClient
    let singing: Bool
    let progress: Double
    /// 画面高度随所在那一块的可用高度变化。
    var imageHeight: CGFloat = 220
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            ZStack {
                if let image {
                    LearningRemoteImage(path: image, client: client, label: "唱歌时的画面", maxHeight: imageHeight)
                        .frame(height: imageHeight)
                        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                        .opacity(0.9)
                }
                HStack(alignment: .bottom, spacing: 18) {
                    note("music.note", delay: 0)
                    BubuMascotBadge(size: 96, expression: .music)
                        .bubuBreathingWiggle(degrees: singing ? 4 : 1)
                    note("music.quarternote.3", delay: 1)
                }
                .padding(.top, image == nil ? 0 : max(imageHeight - 80, 0))
            }
            if let lyrics, !lyrics.isEmpty {
                Text(lyrics).font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("歌词：\(lyrics)")
            }
            ProgressView(value: singing ? progress : 0)
                .tint(BubuTheme.Color.primary)
                .frame(maxWidth: 280)
                .opacity(singing ? 1 : 0.35)
                .accessibilityHidden(true)
        }
        .padding(BubuTheme.Spacing.m)
        .frame(maxWidth: .infinity)
        .background(BubuTheme.Color.mintSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func note(_ symbol: String, delay: Int) -> some View {
        let image = Image(systemName: symbol)
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(BubuTheme.Color.deepRose)
            .accessibilityHidden(true)
        if singing && !reduceMotion {
            image.phaseAnimator(delay == 0 ? [0.0, -14.0] : [-14.0, 0.0]) { view, y in
                view.offset(y: y)
            } animation: { _ in .easeInOut(duration: 0.45) }
        } else {
            image.opacity(singing ? 1 : 0.5)
        }
    }
}

struct ChoiceTile: View {
    let choice: LearningChoiceDTO
    let client: BubuLearningClient
    var highlighted = false
    var dimmed = false
    var compact = false

    var body: some View {
        VStack(spacing: 8) {
            if let colors = choice.colors, !colors.isEmpty {
                HStack(spacing: 4) {
                    ForEach(colors, id: \.self) { hex in
                        RoundedRectangle(cornerRadius: 10).fill(Color(hex: hex)).frame(height: compact ? 44 : 80)
                    }
                }
            } else if let image = choice.imageUrl {
                // A fixed-height clear frame keeps an aspect-fill picture from widening the tile.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 80 : 130)
                    .overlay { LearningRemoteImage(path: image, client: client, label: choice.label, contentMode: .fill) }
                    .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.xs))
            }
            Text(choice.label).font(compact ? BubuTheme.Font.body.weight(.semibold) : BubuTheme.Font.headline)
                .multilineTextAlignment(.center).lineLimit(2)
        }
        .foregroundStyle(BubuTheme.Color.warmBrown)
        .padding(compact ? 8 : 12)
        .frame(maxWidth: .infinity)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous)
            .stroke(highlighted ? BubuTheme.Color.primary : BubuTheme.Color.hairline, lineWidth: highlighted ? 4 : 1))
        .overlay(alignment: .topTrailing) {
            if highlighted {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(BubuTheme.Color.primary).padding(6)
            }
        }
        .opacity(dimmed ? 0.55 : 1)
        // 图片的说明和文字是同一个名字，合并朗读一次即可。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(choice.label)
        .accessibilityValue(highlighted ? "正确答案" : dimmed ? "再看看别的" : "")
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }
}

// MARK: - 周/月复习

struct LearningReviewView: View {
    let client: BubuLearningClient
    let childID: String?
    let period: String
    let day: String
    @State private var review: LearningReviewDTO?
    @State private var errorText: String?
    @State private var playing = false

    var body: some View {
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            if let review {
                ScrollView {
                    VStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
                        Text("\(CourseDetailView.readableDay(review.windowStart)) – \(CourseDetailView.readableDay(review.windowEnd))")
                            .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        if review.items.isEmpty {
                            ContentUnavailableView("这段时间还没有开放的课程", systemImage: "books.vertical",
                                                   description: Text("家长核对并开放课程后，这里会挑出值得再玩一次的原声。"))
                        } else {
                            BubuBigActionButton(title: "开始复习", subtitle: "\(review.items.count) 个老师原声", systemImage: "play.fill") {
                                playing = true
                            }
                            .accessibilityIdentifier("learning.review.start")
                            LearningPanel(title: "这次复习", symbol: "sparkles") {
                                ForEach(review.items, id: \.self) { item in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.activity.title).font(BubuTheme.Font.body.weight(.semibold))
                                        Text(item.reason).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .padding(BubuTheme.Spacing.item)
                    .bubuContentColumn(820)
                }
            } else if let errorText {
                ContentUnavailableView {
                    Label("复习暂时打不开", systemImage: "exclamationmark.triangle")
                } description: { Text(errorText) } actions: {
                    Button("重新加载") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(period == "week" ? "本周复习" : "本月复习")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(isPresented: $playing) {
            if let review {
                LearningPlayView(client: client, childID: childID,
                                 items: review.items.map { LearningPlayItem(packID: $0.packId, activity: $0.activity) },
                                 title: period == "week" ? "本周复习" : "本月复习")
            }
        }
    }

    private func load() async {
        var query = [URLQueryItem(name: "period", value: period), URLQueryItem(name: "date", value: day)]
        if let childID { query.append(URLQueryItem(name: "child_id", value: childID)) }
        do {
            review = try await client.get("api/reviews", query: query, as: LearningReviewDTO.self)
            errorText = nil
        } catch is CancellationError {
        } catch { errorText = learningErrorText(error) }
    }
}

// MARK: - 互动记录发件箱

/// 上传的互动记录：在 `LearningAttemptBody` 基础上多一个 `note`（跟读分数 `score:85`）。
/// 字段都可选解码，旧版本落盘的待上传记录照样能读出来；nil 字段不会编码进请求。
nonisolated struct LearningAttemptUpload: Codable, Sendable, Hashable {
    let id: String
    let childId: String
    let packId: String
    let activityId: String
    let kind: String
    var choice: String?
    var assistance: Bool?
    var note: String?
}

/// 先落盘再上传；同一 UUID 重试由服务端幂等去重。按服务+账号隔离，不依赖网页存储。
actor LearningAttemptOutbox {
    static let shared = LearningAttemptOutbox()
    private nonisolated struct Pending: Codable { let scope: String; let body: LearningAttemptUpload }
    private nonisolated struct Saved: Decodable, Sendable { let id: String? }

    private var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BubuLearningAttempts.json")
    }

    private func read() -> [Pending] {
        guard let file, let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([Pending].self, from: data)) ?? []
    }

    private func write(_ values: [Pending]) {
        guard let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(values).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func submit(_ body: LearningAttemptUpload, client: BubuLearningClient) async {
        write(read() + [Pending(scope: client.scope, body: body)])
        await flush(client: client)
    }

    private var flushing = false

    func flush(client: BubuLearningClient) async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        for item in read() where item.scope == client.scope {
            do {
                _ = try await client.send("POST", "api/attempts", body: item.body, as: Saved.self)
                remove(item.body.id)
            } catch LearningServiceError.unavailableMedia {
                remove(item.body.id)  // the course was withdrawn
            } catch BubuLearningClientError.conflict {
                remove(item.body.id)
            } catch BubuLearningClientError.message {
                remove(item.body.id)  // rejected as invalid; retrying can never succeed
            } catch {
                return  // offline or signed out: keep everything for the next try
            }
        }
    }

    /// Re-read after each send so attempts queued meanwhile are never overwritten.
    private func remove(_ id: String) {
        write(read().filter { $0.body.id != id })
    }
}
