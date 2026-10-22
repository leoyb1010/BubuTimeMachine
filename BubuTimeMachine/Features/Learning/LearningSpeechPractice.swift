import SwiftUI
import AVFoundation
import Speech

// MARK: - 跟读打分（纯函数，便于测试）
/// 给幼儿的宽松打分：中文按拼音音节比（同音字、平翘舌、前后鼻音都算对），英文按单词比（发音接近也算对）。
/// 只要说中一部分就 ≥ 40 分，算「说出来啦」；全对 100 分。
nonisolated enum SpeechPracticeScorer {
    static let passScore = 40

    static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isHan)
    }

    /// 目标里有汉字就用中文识别，否则英文。
    static func localeIdentifier(for target: String) -> String {
        containsHan(target) ? "zh-CN" : "en-US"
    }

    /// 0–100。没听到或完全不相干为 0。
    static func score(target: String, heard: String) -> Int {
        let expected = tokens(target), spoken = tokens(heard)
        guard !expected.isEmpty, !spoken.isEmpty else { return 0 }
        let matched = commonLength(expected, spoken)
        guard matched > 0 else { return 0 }
        let ratio = Double(matched) / Double(expected.count)
        return min(100, Int((Double(passScore) + Double(100 - passScore) * ratio).rounded()))
    }

    static func passes(_ score: Int) -> Bool { score >= passScore }

    /// 课程里的目标句可能很长；只取第一小句，孩子跟得上。
    static func practiceTarget(_ text: String?) -> String? {
        guard let text else { return nil }
        let first = text.split(whereSeparator: { "，。！？!?,.;；:：、\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        guard !first.isEmpty else { return nil }
        if containsHan(first) {
            return first.count <= 12 ? first : nil
        }
        let words = first.split(separator: " ")
        return words.count <= 6 && first.count <= 40 ? first : nil
    }

    // MARK: Tokens

    /// 汉字 → 无声调拼音音节（再做童声宽松化）；字母数字 → 小写单词。
    static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var word = ""
        func flush() {
            if !word.isEmpty { result.append(word); word = "" }
        }
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        for character in folded {
            if character.unicodeScalars.contains(where: isHan) {
                flush()
                result.append(soften(pinyin(character)))
            } else if character.isLetter || character.isNumber {
                word.append(character)
            } else {
                flush()
            }
        }
        flush()
        return result
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }

    private static func pinyin(_ character: Character) -> String {
        let latin = String(character).applyingTransform(.mandarinToLatin, reverse: false) ?? String(character)
        let plain = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return plain.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// 小朋友常见的发音混淆：zh/ch/sh ≈ z/c/s，-ng ≈ -n，l ≈ n。
    private static func soften(_ syllable: String) -> String {
        var value = syllable
        for (from, to) in [("zh", "z"), ("ch", "c"), ("sh", "s")] where value.hasPrefix(from) {
            value = to + value.dropFirst(from.count)
        }
        if value.hasPrefix("l") { value = "n" + value.dropFirst() }
        if value.hasSuffix("ng") { value = String(value.dropLast()) }
        return value
    }

    // MARK: Matching

    private static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        // 拼音音节或很短的词必须一致；英文长词允许接近（appo ≈ apple，elefant ≈ elephant）。
        guard a.count >= 3, b.count >= 3, a.allSatisfy(\.isASCII), b.allSatisfy(\.isASCII) else { return false }
        if a.hasPrefix(b) || b.hasPrefix(a) { return true }
        let distance = levenshtein(Array(a), Array(b))
        return 1 - Double(distance) / Double(max(a.count, b.count)) >= 0.6
    }

    /// 最长公共子序列（宽松相等）：说话顺序对、可以夹杂别的字。
    private static func commonLength(_ a: [String], _ b: [String]) -> Int {
        var previous = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var current = [Int](repeating: 0, count: b.count + 1)
            for (j, y) in b.enumerated() {
                current[j + 1] = similar(x, y) ? previous[j] + 1 : max(previous[j + 1], current[j])
            }
            previous = current
        }
        return previous[b.count]
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var row = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var previousDiagonal = row[0]
            row[0] = i + 1
            for (j, y) in b.enumerated() {
                let saved = row[j + 1]
                row[j + 1] = x == y ? previousDiagonal : min(previousDiagonal, row[j], row[j + 1]) + 1
                previousDiagonal = saved
            }
        }
        return row[b.count]
    }
}

// MARK: - 端侧语音识别

nonisolated enum SpeechPracticeError: Error { case unavailable }

/// 只用设备上的识别（`requiresOnDeviceRecognition`），声音不离开这台设备。
/// 音频回调在实时线程，整个类保持 nonisolated，结果再回到主线程。
nonisolated final class SpeechPracticeRecognizer: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<String, Error>?
    private var latest = ""
    /// 每段录音一个编号：上一段的延时收尾不会误伤下一段。
    private var listenID = 0
    /// 每次听到新内容 +1，用于「停顿后自动结束」。
    private var generation = 0

    /// 该语言是否支持端侧识别；不支持就整块隐藏跟读。
    static func isAvailable(localeID: String) -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: localeID))?.supportsOnDeviceRecognition == true
    }

    /// 只在点麦克风时调用。
    static func requestPermissions() async -> Bool {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    static var permissionDenied: Bool {
        SFSpeechRecognizer.authorizationStatus() == .denied || SFSpeechRecognizer.authorizationStatus() == .restricted
            || AVAudioApplication.shared.recordPermission == .denied
    }

    /// 录一小段（说完停顿约 1.4 秒自动结束，最长 maxSeconds），返回听到的文字（可能为空）。
    func listen(localeID: String, hints: [String], maxSeconds: Double = 6) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)),
              recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else { throw SpeechPracticeError.unavailable }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = hints
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let box = RequestBox(request)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            box.request.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
        let started: Int = lock.withLock {
            self.engine = engine
            self.request = request
            self.latest = ""
            self.listenID += 1
            return self.listenID
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { self.continuation = continuation }
                let recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    guard let self else { return }
                    if let result {
                        self.heard(result.bestTranscription.formattedString)
                        if result.isFinal { self.finish() }
                    } else if error != nil {
                        self.finish()
                    }
                }
                lock.withLock { self.task = recognition }
                DispatchQueue.global().asyncAfter(deadline: .now() + maxSeconds) { [weak self] in
                    guard let self, self.lock.withLock({ self.listenID == started && self.continuation != nil }) else { return }
                    self.stop()
                }
            }
        } onCancel: {
            self.stop()
        }
    }

    /// 停止收音；最终结果稍后到达，1.5 秒内没到就用已经听到的。
    func stop() {
        let (engine, request, id) = lock.withLock { (self.engine, self.request, self.listenID) }
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.lock.withLock({ self.listenID == id }) else { return }
            self.finish()
        }
    }

    private func heard(_ text: String) {
        let mark: Int = lock.withLock {
            latest = text
            generation += 1
            return generation
        }
        // 说完停顿一下就结束，不让孩子等。
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.lock.withLock({ self.generation == mark && self.continuation != nil }) else { return }
            self.stop()
        }
    }

    private func finish() {
        let (continuation, text, engine, task) = lock.withLock {
            let values = (self.continuation, latest, self.engine, self.task)
            self.continuation = nil
            self.engine = nil
            self.request = nil
            self.task = nil
            return values
        }
        guard let continuation else { return }
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        task?.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        continuation.resume(returning: text)
    }

    private final class RequestBox: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
        init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    }
}

// MARK: - 「跟我说」卡片

/// 先放老师的示范，再听布布说；说中一部分就庆祝，不出现「错误」。
struct SpeakPracticeCard: View {
    let target: String
    let player: NativeLearningAudioPlayer
    /// 播放示范原声（老师的答案/歌词）。
    let playModel: () -> Void
    /// 每次打完分回调（分数、是否算说出来）。
    let onScored: (Int, Bool) -> Void

    private enum Phase: Equatable { case idle, modeling, listening, scored(Int), retry, denied }

    @State private var phase = Phase.idle
    @State private var available = false
    @State private var heard = ""
    @State private var celebration = 0
    @State private var recognizer = SpeechPracticeRecognizer()
    @State private var listenTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var localeID: String { SpeechPracticeScorer.localeIdentifier(for: target) }

    var body: some View {
        Group {
            if available {
                card
            }
        }
        .onAppear { available = SpeechPracticeRecognizer.isAvailable(localeID: localeID) }
        .onDisappear {
            listenTask?.cancel()
            recognizer.stop()
        }
    }

    private var card: some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            HStack(spacing: 6) {
                Image(systemName: "mouth.fill").accessibilityHidden(true)
                Text("跟我说").font(BubuTheme.Font.caption.weight(.bold))
            }
            .foregroundStyle(BubuTheme.Color.deepRose)
            Text(target)
                .font(BubuTheme.Font.title)
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("要说的话：\(target)")
            micButton
            feedback
        }
        .padding(BubuTheme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
            .stroke(BubuTheme.Color.pinkSurface, lineWidth: 2))
        .overlay {
            if celebration > 0 && !reduceMotion {
                BubuBurst(count: 16, radius: 120).id(celebration).allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var micButton: some View {
        let busy = phase == .modeling || phase == .listening
        return Button {
            if phase == .listening { recognizer.stop() } else if !busy { start() }
        } label: {
            ZStack {
                Circle()
                    .fill(phase == .listening ? BubuTheme.Color.deepRose : BubuTheme.Color.primary)
                    .frame(width: 96, height: 96)
                    .shadow(color: BubuTheme.Color.primary.opacity(0.35), radius: 12, y: 6)
                Image(systemName: phase == .modeling ? "speaker.wave.2.fill" : "mic.fill")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, isActive: busy && !reduceMotion)
            }
            .scaleEffect(phase == .listening && !reduceMotion ? 1.06 : 1)
            .animation(reduceMotion ? nil : BubuMotion.breathe, value: phase == .listening)
        }
        .buttonStyle(BubuPressableStyle(scale: 0.92))
        .disabled(phase == .modeling)
        .accessibilityLabel(phase == .listening ? "说完了" : "跟我说：\(target)")
        .accessibilityHint(phase == .listening ? "轻点结束录音" : "先听老师说，再对着手机说出来")
        .accessibilityIdentifier("learning.play.speak.mic")
    }

    @ViewBuilder
    private var feedback: some View {
        switch phase {
        case .idle:
            Text("点麦克风，先听老师说，再跟着说").font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText).multilineTextAlignment(.center)
        case .modeling:
            Text("听老师说…").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
        case .listening:
            Text("轮到你啦，大声说出来！").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.deepRose)
        case .scored(let score):
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: index < stars(score) ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(index < stars(score) ? BubuTheme.Color.butter : BubuTheme.Color.hairline)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(stars(score)) 颗星")
                Text(score >= 85 ? "说得真棒！" : "说出来啦！").font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.deepRose)
                Button("再说一次") { start() }.buttonStyle(.bordered).tint(BubuTheme.Color.deepRose)
            }
        case .retry:
            VStack(spacing: 6) {
                Label("再说一次试试？", systemImage: "heart.fill").font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                if !heard.isEmpty {
                    Text("我听到了「\(heard)」").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
        case .denied:
            Text("要先在系统设置里允许麦克风和语音识别，才能跟读哦。声音只在这台设备上识别。")
                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private func stars(_ score: Int) -> Int { score >= 90 ? 3 : score >= 70 ? 2 : 1 }

    private func start() {
        listenTask?.cancel()
        listenTask = Task { await run() }
    }

    private func run() async {
        BubuHaptics.tapLight()
        guard await SpeechPracticeRecognizer.requestPermissions() else {
            phase = .denied
            return
        }
        // 1. 老师示范
        phase = .modeling
        playModel()
        try? await Task.sleep(for: .milliseconds(300))
        var waited = 0
        while (player.isLoading || player.isPlaying) && waited < 150 && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        guard !Task.isCancelled else { return }
        player.stop()
        // 2. 布布说
        phase = .listening
        let text: String
        do {
            text = try await recognizer.listen(localeID: localeID, hints: [target])
        } catch {
            available = SpeechPracticeRecognizer.isAvailable(localeID: localeID)
            phase = .retry
            heard = ""
            return
        }
        guard !Task.isCancelled else { return }
        heard = text
        let score = SpeechPracticeScorer.score(target: target, heard: text)
        let passed = SpeechPracticeScorer.passes(score)
        if passed {
            phase = .scored(score)
            celebration += 1
            BubuSound.play(.milestone)
            BubuHaptics.success()
        } else {
            phase = .retry
            BubuHaptics.tapLight()
        }
        onScored(score, passed)
    }
}
