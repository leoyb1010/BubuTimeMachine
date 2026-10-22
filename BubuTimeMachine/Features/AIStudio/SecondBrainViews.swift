import SwiftUI
import AVFoundation

// MARK: - DTOs (contract §4 §5 §6)

nonisolated struct MonthlyReportDTO: Decodable, Sendable, Hashable, Identifiable {
    let month: String
    let title: String
    let summary: String
    let highlightIds: [String]
    let photos: Int
    let videos: Int
    let places: [String]
    let firsts: [String]
    var id: String { month }
}
nonisolated struct MonthlyReportList: Decodable, Sendable { let items: [MonthlyReportDTO] }

nonisolated struct VoiceClipDTO: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let itemId: String
    let capturedAt: String?
    let start: Double
    let end: Double
    let text: String
    let heard: String?
    let audioUrl: String
}
nonisolated struct VoiceClipList: Decodable, Sendable { let items: [VoiceClipDTO] }

nonisolated struct RecognitionCandidateDTO: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let previewUrl: String
    let capturedAt: String?
    let confidence: Double?
    let description: String
}
nonisolated struct RecognitionCandidateList: Decodable, Sendable {
    let items: [RecognitionCandidateDTO]
    let remaining: Int?
}

/// Shown when the family service isn't connected.
private struct SecondBrainUnavailable: View {
    let title: String
    var body: some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            BubuEmptyIllustration(assetName: "BubuEmptyTimeline", size: 130)
            Text("连接家庭服务后才能看「\(title)」。").font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }
}

// MARK: - 每月成长小报（布布成长月刊）

struct MonthlyReportView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var reports: [MonthlyReportDTO] = []
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        let client = BubuLearningClient(env: env)
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
                    if let client {
                        if loading && reports.isEmpty {
                            ProgressView("正在翻开成长月刊…").frame(maxWidth: .infinity).padding(.vertical, 60)
                        } else if reports.isEmpty {
                            VStack(spacing: BubuTheme.Spacing.m) {
                                BubuMascotBadge(size: 96, expression: .thinking)
                                Text(errorText ?? "第一期小报会在下个月 1 号自动生成。")
                                    .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
                                    .multilineTextAlignment(.center)
                                if errorText != nil {
                                    Button("再试一次") { Task { await load(client) } }
                                        .buttonStyle(.bordered).tint(BubuTheme.Color.deepRose)
                                }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 60)
                        } else {
                            MonthlyMagazineShelf(reports: reports, client: client)
                        }
                    } else {
                        SecondBrainUnavailable(title: "每月成长小报")
                    }
                }
                .padding(BubuTheme.Spacing.item)
                .bubuContentColumn(860)
            }
        }
        .navigationTitle("成长小报")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: client?.scope) {
            guard let client else { loading = false; return }
            await load(client)
        }
        .accessibilityIdentifier("brain.monthly")
    }

    private func load(_ client: BubuLearningClient) async {
        loading = true
        do { reports = try await client.get("api/monthly", as: MonthlyReportList.self).items; errorText = nil }
        catch let error where !isCancellation(error) { errorText = learningErrorText(error) }
        catch {}
        loading = false
    }
}


// MARK: - 布布的声音

struct BubuVoicesView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clips: [VoiceClipDTO] = []
    @State private var loading = true
    @State private var voice = SecondBrainVoicePlayer()
    @State private var errorText: String?

    var body: some View {
        let client = BubuLearningClient(env: env)
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
                    Text("从家里的视频里，找出布布自己说的话。机器先听一遍，再请 Gemini 复听确认。")
                        .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
                    if let client {
                        // Playback errors show even when the list has clips (it used to be hidden then).
                        if let playError = voice.errorText {
                            SecondBrainErrorBanner(text: playError) { voice.errorText = nil }
                        }
                        if loading && clips.isEmpty {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 50)
                        } else if clips.isEmpty {
                            Text(errorText ?? "还没有整理出声音片段，稍后再来看看。").font(BubuTheme.Font.body)
                                .foregroundStyle(BubuTheme.Color.secondaryText).frame(maxWidth: .infinity).padding(.vertical, 40)
                        } else if let errorText {
                            SecondBrainErrorBanner(text: errorText) { self.errorText = nil }
                        }
                        ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                            clipRow(clip, client: client).entranceEffect(index: index)
                        }
                    } else {
                        SecondBrainUnavailable(title: "布布的声音")
                    }
                }
                .padding(BubuTheme.Spacing.item)
                .bubuContentColumn(820)
            }
        }
        .navigationTitle("布布的声音")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: client?.scope) {
            guard let client else { loading = false; return }
            do { clips = try await client.get("api/voices", as: VoiceClipList.self).items; errorText = nil }
            catch { errorText = learningErrorText(error) }
            loading = false
        }
        .onDisappear { voice.stop() }
        .accessibilityIdentifier("brain.voices")
    }

    private func clipRow(_ clip: VoiceClipDTO, client: BubuLearningClient) -> some View {
        let playing = voice.playing == clip.id
        return Button {
            Task { await voice.toggle(id: clip.id, path: clip.audioUrl, client: client, duration: max(1, clip.end - clip.start)) }
        } label: {
            HStack(spacing: BubuTheme.Spacing.m) {
                ZStack {
                    Circle().fill(playing ? BubuTheme.Color.actionFill : BubuTheme.Color.pinkSurface)
                    if voice.loading == clip.id {
                        ProgressView().tint(BubuTheme.Color.deepRose)
                    } else {
                        Image(systemName: playing ? "speaker.wave.3.fill" : "play.fill")
                            .foregroundStyle(playing ? .white : BubuTheme.Color.deepRose)
                            .symbolEffect(.variableColor.iterative, isActive: playing && !reduceMotion)
                    }
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("“\(clip.heard?.isEmpty == false ? clip.heard! : clip.text)”")
                        .font(BubuTheme.Font.body.weight(.semibold)).foregroundStyle(BubuTheme.Color.warmBrown)
                    if let date = clip.capturedAt.flatMap(BubuLearningDates.parseISO) {
                        Text(date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))
                            .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(BubuTheme.Spacing.m)
            .background(BubuTheme.Color.card.opacity(0.95), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(BubuPressableStyle())
        .accessibilityHint(playing ? "停止播放" : "播放这段声音")
        .accessibilityIdentifier("brain.voice")
    }
}

// MARK: - 认一认

/// Swipe-to-confirm queue for photos the library wasn't sure about. Decisions stay on
/// the 布布 side: yes adds the photo to 布布的时光, no keeps it out. Nothing is written back.
/// 2.26: every decision can be undone (chip for ~5 s, or later from 认过的), and a batch grid
/// lets a parent confirm many at once.
struct RecognitionView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var queue: [RecognitionCandidateDTO] = []
    @State private var remaining = 0
    @State private var loading = true
    @State private var drag: CGSize = .zero
    @State private var decided = 0
    @State private var errorText: String?
    @State private var batchMode = false
    @State private var picked: Set<String> = []
    @State private var batchBusy = false
    @State private var lastDecision: LastDecision?
    @State private var showHistory = false
    /// Cards whose decision is in flight: a second tap during the fly-out animation is ignored.
    @State private var deciding: Set<String> = []
    /// Size of the current round, for the progress bar.
    @State private var roundSize = 0

    /// A short round keeps 认一认 light even when a thousand photos wait.
    static let roundLimit = 10

    private struct LastDecision: Equatable {
        let candidate: RecognitionCandidateDTO
        let yes: Bool
        let token = UUID()
    }

    /// Card swipe per the 2.26 motion spec (a touch bouncier than `BubuMotion.gentle`).
    private static let swipe = Animation.spring(response: 0.4, dampingFraction: 0.75)
    private var motion: Animation? { reduceMotion ? nil : Self.swipe }

    var body: some View {
        let client = BubuLearningClient(env: env)
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            VStack(spacing: BubuTheme.Spacing.l) {
                if let client {
                    Picker("方式", selection: $batchMode) {
                        Text("一张张认").tag(false)
                        Text("批量").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("recognition.mode")
                    if !queue.isEmpty || remaining > 0 { pendingHeader }
                    if batchMode {
                        Text("勾选几张一起确认，只影响布布的时光，不改第二大脑。")
                            .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText).multilineTextAlignment(.center)
                    } else {
                        Text("右滑“是布布”，左滑“不是”。只影响布布的时光，不改第二大脑。")
                            .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText).multilineTextAlignment(.center)
                    }
                    if let errorText, !queue.isEmpty {
                        SecondBrainErrorBanner(text: errorText) { self.errorText = nil }
                    }
                    if loading && queue.isEmpty {
                        ProgressView().frame(maxHeight: .infinity)
                    } else if queue.isEmpty {
                        finished(client)
                    } else if batchMode {
                        batchGrid(client)
                    } else if let top = queue.first {
                        ZStack {
                            ForEach(Array(queue.prefix(3).enumerated()).reversed(), id: \.element.id) { depth, candidate in
                                card(candidate, client: client, depth: depth)
                                    .zIndex(Double(3 - depth))
                                    .transition(.asymmetric(insertion: reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity),
                                                            removal: .opacity))
                            }
                        }
                        .frame(maxHeight: .infinity)
                        // The undo chip sits above the buttons so it never covers them.
                        undoSlot(client)
                        HStack(spacing: BubuTheme.Spacing.l) {
                            decisionButton("不是", symbol: "xmark", tint: BubuTheme.Color.softFill, foreground: BubuTheme.Color.warmBrown) {
                                Task { await decide(top, yes: false, client: client) }
                            }
                            .accessibilityIdentifier("recognition.no")
                            decisionButton("是布布", symbol: "heart.fill", tint: BubuTheme.Color.actionFill, foreground: .white) {
                                Task { await decide(top, yes: true, client: client) }
                            }
                            .accessibilityIdentifier("recognition.yes")
                        }
                        .disabled(deciding.contains(top.id))
                    }
                    if queue.isEmpty { undoSlot(client) }
                } else {
                    SecondBrainUnavailable(title: "认一认")
                }
            }
            .padding(BubuTheme.Spacing.l)
            .bubuContentColumn(640)
        }
        .navigationTitle("认一认")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if client != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("认过的照片")
                        .accessibilityIdentifier("recognition.history")
                }
            }
        }
        .navigationDestination(isPresented: $showHistory) {
            if let client { RecognitionHistoryView(client: client) }
        }
        .task(id: client?.scope) { if let client { await load(client) } else { loading = false } }
        .task(id: lastDecision?.token) {
            guard let token = lastDecision?.token else { return }
            try? await Task.sleep(for: .seconds(5))
            if lastDecision?.token == token { withAnimation(reduceMotion ? nil : BubuMotion.gentle) { lastDecision = nil } }
        }
        .onChange(of: batchMode) { _, _ in picked = []; BubuHaptics.selection() }
        .accessibilityIdentifier("brain.recognition")
    }

    /// The pending count, front and centre: how many photos wait overall, and this round's progress.
    private var pendingHeader: some View {
        let total = max(remaining, queue.count)
        let done = max(0, roundSize - queue.count)
        return VStack(alignment: .leading, spacing: BubuTheme.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(total)").font(BubuTheme.Font.hugeTitle.monospacedDigit()).foregroundStyle(BubuTheme.Color.deepRose)
                    .contentTransition(.numericText())
                Text("张可能是布布，等你认一认").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer(minLength: 0)
            }
            if !batchMode, roundSize > 0 {
                ProgressView(value: Double(done), total: Double(max(roundSize, 1))).tint(BubuTheme.Color.primary)
                Text(queue.isEmpty ? "这一轮认完啦" : "这一轮 \(done) / \(roundSize) · 认完 \(roundSize) 张就好")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    .contentTransition(.numericText())
            }
        }
        .padding(BubuTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.pinkSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recognition.pending")
    }

    @ViewBuilder
    private func undoSlot(_ client: BubuLearningClient) -> some View {
        if let lastDecision {
            undoChip(lastDecision, client: client)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func finished(_ client: BubuLearningClient) -> some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            BubuMascotBadge(size: 110, expression: .yeah)
            Text(decided > 0 ? "这一轮认完啦，确认了 \(decided) 张" : (errorText ?? "现在没有需要确认的照片"))
                .font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            Button("再来一轮") { Task { await load(client) } }.buttonStyle(.bordered).tint(BubuTheme.Color.deepRose)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Swipe card

    private func card(_ candidate: RecognitionCandidateDTO, client: BubuLearningClient, depth: Int) -> some View {
        let isTop = depth == 0
        return VStack(spacing: 0) {
            Color.clear
                .overlay { LearningRemoteImage(path: candidate.previewUrl, client: client, label: candidate.description, contentMode: .fill) }
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                if let date = candidate.capturedAt.flatMap(BubuLearningDates.parseISO) {
                    Text(date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))
                        .font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(BubuTheme.Color.deepRose)
                }
                Text(candidate.description).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.warmBrown).lineLimit(3)
            }
            .padding(BubuTheme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BubuTheme.Color.card)
        }
        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .shadow(color: BubuTheme.Color.deepRose.opacity(isTop ? 0.15 : 0.08), radius: 12, y: 6)
        .overlay(alignment: .topLeading) {
            if isTop && drag.width > 40 { stamp("是布布", color: BubuTheme.Color.primary) }
        }
        .overlay(alignment: .topTrailing) {
            if isTop && drag.width < -40 { stamp("不是", color: BubuTheme.Color.warmBrown) }
        }
        // Cards behind sit a little lower and smaller, and rise into place when the top one leaves.
        .scaleEffect(1 - CGFloat(depth) * 0.05)
        .offset(y: CGFloat(depth) * 14)
        .offset(isTop ? drag : .zero)
        .rotationEffect(.degrees(isTop && !reduceMotion ? min(max(Double(drag.width / 20), -12), 12) : 0))
        .allowsHitTesting(isTop)
        .gesture(isTop ? DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if abs(value.translation.width) > 110 {
                    Task { await decide(candidate, yes: value.translation.width > 0, client: client) }
                } else {
                    withAnimation(motion) { drag = .zero }
                }
            } : nil)
        .accessibilityElement(children: .combine)
        .accessibilityHidden(!isTop)
        .accessibilityAction(named: "是布布") { Task { await decide(candidate, yes: true, client: client) } }
        .accessibilityAction(named: "不是布布") { Task { await decide(candidate, yes: false, client: client) } }
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text).font(BubuTheme.Font.headline).foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(-12)).padding(20)
    }

    private func decisionButton(_ title: String, symbol: String, tint: Color, foreground: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(BubuTheme.Font.headline)
                .foregroundStyle(foreground)
                .padding(.horizontal, 26).padding(.vertical, 14)
                .background(tint, in: Capsule())
        }
        .buttonStyle(BubuPressableStyle(scale: 0.93))
    }

    private func undoChip(_ decision: LastDecision, client: BubuLearningClient) -> some View {
        Button { Task { await undo(decision, client: client) } } label: {
            Label("撤销「\(decision.yes ? "是布布" : "不是")」", systemImage: "arrow.uturn.backward")
                .font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(BubuTheme.Color.warmBrown.opacity(0.92), in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .buttonStyle(BubuPressableStyle(scale: 0.94))
        .accessibilityIdentifier("recognition.undo")
    }

    // MARK: Batch grid

    private func batchGrid(_ client: BubuLearningClient) -> some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            HStack {
                Text("已选 \(picked.count) 张").font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(BubuTheme.Color.warmBrown)
                    .contentTransition(.numericText())
                Spacer()
                Button(picked.count == queue.count ? "全不选" : "全选") {
                    BubuHaptics.selection()
                    withAnimation(reduceMotion ? nil : BubuMotion.quick) {
                        picked = picked.count == queue.count ? [] : Set(queue.map(\.id))
                    }
                }
                .font(BubuTheme.Font.caption.weight(.semibold)).tint(BubuTheme.Color.deepRose)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                    ForEach(queue) { candidate in
                        let isPicked = picked.contains(candidate.id)
                        Button {
                            BubuHaptics.selection()
                            withAnimation(reduceMotion ? nil : BubuMotion.quick) {
                                if isPicked { picked.remove(candidate.id) } else { picked.insert(candidate.id) }
                            }
                        } label: {
                            Color.clear.frame(height: 124)
                                .overlay {
                                    LearningRemoteImage(path: candidate.previewUrl, client: client, label: candidate.description,
                                                        contentMode: .fill, diskCache: true)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous)
                                        .stroke(isPicked ? BubuTheme.Color.primary : .clear, lineWidth: 4)
                                }
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                                        .font(BubuTheme.Font.headline).symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, isPicked ? BubuTheme.Color.primary : .black.opacity(0.25))
                                        .padding(6)
                                }
                                .scaleEffect(isPicked && !reduceMotion ? 0.95 : 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(candidate.description.isEmpty ? "待确认的照片" : candidate.description)
                        .accessibilityAddTraits(isPicked ? .isSelected : [])
                    }
                }
            }
            HStack(spacing: BubuTheme.Spacing.m) {
                decisionButton("都不是", symbol: "xmark", tint: BubuTheme.Color.softFill, foreground: BubuTheme.Color.warmBrown) {
                    Task { await decideBatch(yes: false, client: client) }
                }
                .accessibilityIdentifier("recognition.batch.no")
                decisionButton("都是布布", symbol: "heart.fill", tint: BubuTheme.Color.actionFill, foreground: .white) {
                    Task { await decideBatch(yes: true, client: client) }
                }
                .accessibilityIdentifier("recognition.batch.yes")
            }
            .disabled(picked.isEmpty || batchBusy)
            .opacity(picked.isEmpty ? 0.5 : 1)
        }
    }

    // MARK: Network

    private nonisolated struct Decision: Encodable, Sendable { let decision: String }

    private func load(_ client: BubuLearningClient) async {
        loading = true
        defer { loading = false }
        do {
            let list = try await client.get("api/recognition/candidates",
                                            query: [URLQueryItem(name: "limit", value: String(Self.roundLimit))],
                                            as: RecognitionCandidateList.self)
            queue = list.items
            roundSize = list.items.count
            remaining = list.remaining ?? list.items.count
            picked = []
            errorText = nil
        } catch {
            errorText = learningErrorText(error)
        }
    }

    private func decide(_ candidate: RecognitionCandidateDTO, yes: Bool, client: BubuLearningClient) async {
        guard queue.first?.id == candidate.id, deciding.insert(candidate.id).inserted else { return }
        defer { deciding.remove(candidate.id) }
        yes ? BubuHaptics.success() : BubuHaptics.selection()
        if !reduceMotion {
            withAnimation(Self.swipe) { drag = CGSize(width: yes ? 700 : -700, height: 60) }
            try? await Task.sleep(for: .milliseconds(180))
        }
        withAnimation(motion) {
            queue.removeAll { $0.id == candidate.id }
            remaining = max(0, remaining - 1)
        }
        drag = .zero
        do {
            _ = try await client.send("POST", "api/recognition/\(candidate.id)", body: Decision(decision: yes ? "yes" : "no"),
                                      as: SecondBrainAck.self)
            if yes { decided += 1 }
            withAnimation(reduceMotion ? nil : BubuMotion.gentle) { lastDecision = LastDecision(candidate: candidate, yes: yes) }
        } catch {
            withAnimation(motion) {
                if !queue.contains(where: { $0.id == candidate.id }) {
                    queue.insert(candidate, at: 0)
                    remaining += 1
                }
            }
            errorText = learningErrorText(error, fallback: "没有保存成功（需要家长账号），请稍后再试。")
        }
    }

    private func undo(_ decision: LastDecision, client: BubuLearningClient) async {
        withAnimation(reduceMotion ? nil : BubuMotion.gentle) { lastDecision = nil }
        do {
            _ = try await client.send("POST", "api/recognition/\(decision.candidate.id)", body: Decision(decision: "undo"),
                                      as: SecondBrainAck.self)
            BubuHaptics.selection()
            if decision.yes { decided = max(0, decided - 1) }
            withAnimation(motion) {
                queue.removeAll { $0.id == decision.candidate.id }
                queue.insert(decision.candidate, at: 0)
                remaining += 1
            }
        } catch {
            errorText = learningErrorText(error, fallback: "没有撤销成功，可以在「认过的」里再试。")
        }
    }

    private func decideBatch(yes: Bool, client: BubuLearningClient) async {
        let chosen = queue.filter { picked.contains($0.id) }.prefix(50)
        guard !chosen.isEmpty, !batchBusy else { return }
        batchBusy = true
        defer { batchBusy = false }
        let body = RecognitionBatchBody(decisions: chosen.map { .init(id: $0.id, decision: yes ? "yes" : "no") })
        do {
            let result = try await client.send("POST", "api/recognition/batch", body: body, as: RecognitionBatchResult.self)
            let ids = Set(chosen.map(\.id))
            withAnimation(motion) {
                queue.removeAll { ids.contains($0.id) }
                remaining = max(0, remaining - result.applied)
                picked.subtract(ids)
            }
            if yes { decided += result.applied }
            errorText = result.applied < ids.count ? "有 \(ids.count - result.applied) 张没有保存，稍后再试。" : nil
            BubuHaptics.success()
        } catch {
            errorText = learningErrorText(error, fallback: "没有保存成功（需要家长账号），请稍后再试。")
        }
    }
}

// MARK: - 认过的（GET recognition/history）

struct RecognitionHistoryView: View {
    let client: BubuLearningClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var items: [RecognitionHistoryDTO] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var busy: Set<String> = []

    var body: some View {
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BubuTheme.Spacing.s) {
                    Text("最近认过的照片。撤销后恢复成第二大脑原来的判断。")
                        .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    if let errorText, !items.isEmpty {
                        SecondBrainErrorBanner(text: errorText) { self.errorText = nil }
                    }
                    if loading && items.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
                    } else if items.isEmpty {
                        Text(errorText ?? "还没有认过照片。").font(BubuTheme.Font.body)
                            .foregroundStyle(BubuTheme.Color.secondaryText).frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    ForEach(items) { item in
                        row(item).transition(.opacity)
                    }
                }
                .padding(BubuTheme.Spacing.item)
                .bubuContentColumn(720)
            }
        }
        .navigationTitle("认过的")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                items = try await client.get("api/recognition/history", query: [URLQueryItem(name: "limit", value: "50")],
                                             as: RecognitionHistoryList.self).items
                errorText = nil
            } catch is CancellationError {
            } catch {
                errorText = learningErrorText(error)
            }
            loading = false
        }
        .accessibilityIdentifier("recognition.history.list")
    }

    private func row(_ item: RecognitionHistoryDTO) -> some View {
        let yes = item.decision == "yes"
        return HStack(spacing: BubuTheme.Spacing.m) {
            Group {
                if let preview = item.previewUrl {
                    LearningRemoteImage(path: preview, client: client, label: yes ? "认作布布的照片" : "认作不是布布的照片",
                                        contentMode: .fill, diskCache: true)
                } else {
                    Image(systemName: "photo").foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Label(yes ? "是布布" : "不是布布", systemImage: yes ? "heart.fill" : "xmark")
                    .font(BubuTheme.Font.body.weight(.bold))
                    .foregroundStyle(yes ? BubuTheme.Color.deepRose : BubuTheme.Color.warmBrown)
                if let date = item.decidedAt.flatMap(BubuLearningDates.parseISO) {
                    Text(date.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "zh_CN"))))
                        .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            Spacer(minLength: 0)
            Button { Task { await undo(item) } } label: {
                if busy.contains(item.id) {
                    ProgressView()
                } else {
                    Label("撤销", systemImage: "arrow.uturn.backward").font(BubuTheme.Font.caption.weight(.semibold))
                }
            }
            .buttonStyle(.bordered).tint(BubuTheme.Color.deepRose)
            .disabled(busy.contains(item.id))
            .accessibilityLabel("撤销这次判断")
        }
        .padding(BubuTheme.Spacing.s)
        .background(BubuTheme.Color.card.opacity(0.95), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private nonisolated struct Decision: Encodable, Sendable { let decision: String }

    private func undo(_ item: RecognitionHistoryDTO) async {
        busy.insert(item.id)
        defer { busy.remove(item.id) }
        do {
            _ = try await client.send("POST", "api/recognition/\(item.id)", body: Decision(decision: "undo"), as: SecondBrainAck.self)
            BubuHaptics.selection()
            withAnimation(reduceMotion ? nil : BubuMotion.gentle) { items.removeAll { $0.id == item.id } }
        } catch {
            errorText = learningErrorText(error, fallback: "没有撤销成功，请稍后再试。")
        }
    }
}
