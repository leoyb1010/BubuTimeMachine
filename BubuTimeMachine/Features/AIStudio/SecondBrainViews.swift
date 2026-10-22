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

// MARK: - 每月成长小报

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
                            ProgressView("正在翻开成长小报…").frame(maxWidth: .infinity).padding(.vertical, 60)
                        } else if reports.isEmpty {
                            Text(errorText ?? "第一期小报会在下个月 1 号自动生成。")
                                .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
                                .frame(maxWidth: .infinity).padding(.vertical, 60)
                        }
                        ForEach(Array(reports.enumerated()), id: \.element.id) { index, report in
                            MonthlyReportCard(report: report, client: client).entranceEffect(index: index)
                        }
                    } else {
                        SecondBrainUnavailable(title: "每月成长小报")
                    }
                }
                .padding(BubuTheme.Spacing.item)
                .bubuContentColumn(860)
            }
        }
        .navigationTitle("每月成长小报")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: client?.scope) {
            guard let client else { loading = false; return }
            do { reports = try await client.get("api/monthly", as: MonthlyReportList.self).items; errorText = nil }
            catch { errorText = learningErrorText(error) }
            loading = false
        }
        .accessibilityIdentifier("brain.monthly")
    }
}

private struct MonthlyReportCard: View {
    let report: MonthlyReportDTO
    let client: BubuLearningClient
    @State private var items: [OnlineTimelineItem] = []
    @State private var selected: OnlineTimelineItem?

    var body: some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(OnlineTimelineBrowser.monthTitle(report.month)).font(BubuTheme.Font.caption.weight(.bold))
                    .foregroundStyle(BubuTheme.Color.deepRose)
                Spacer()
                Text("照片 \(report.photos) · 视频 \(report.videos)").font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            Text(report.title).font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(items) { item in
                            Button { selected = item } label: {
                                Color.clear.frame(width: 112, height: 140)
                                    .overlay { LearningRemoteImage(path: item.previewUrl, client: client, label: item.description, contentMode: .fill, diskCache: true) }
                                    .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))
                            }.buttonStyle(BubuPressableStyle())
                        }
                    }
                }
            }
            Text(report.summary).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
            if !report.firsts.isEmpty {
                Label("这个月的第一次：" + report.firsts.joined(separator: "、"), systemImage: "star.fill")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.deepRose)
            }
            if !report.places.isEmpty {
                Label("去过：" + report.places.joined(separator: "、"), systemImage: "mappin.and.ellipse")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
        .padding(BubuTheme.Spacing.l)
        .background(BubuTheme.Color.card.opacity(0.95), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .navigationDestination(item: $selected) { item in
            OnlineTimelineDetailPager(client: client, items: items, initial: item, loadMore: {}, hasMore: false)
        }
        .task {
            guard items.isEmpty, !report.highlightIds.isEmpty else { return }
            items = (try? await client.get("api/online-timeline/items",
                                           query: [URLQueryItem(name: "ids", value: report.highlightIds.prefix(12).joined(separator: ","))],
                                           as: OnlineTimelineItems.self).items) ?? []
        }
    }
}

// MARK: - 布布的声音

struct BubuVoicesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var clips: [VoiceClipDTO] = []
    @State private var loading = true
    @State private var playing: String?
    @State private var player: AVPlayer?
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
                        if loading && clips.isEmpty {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 50)
                        } else if clips.isEmpty {
                            Text(errorText ?? "还没有整理出声音片段，稍后再来看看。").font(BubuTheme.Font.body)
                                .foregroundStyle(BubuTheme.Color.secondaryText).frame(maxWidth: .infinity).padding(.vertical, 40)
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
        .onDisappear { stop() }
        .accessibilityIdentifier("brain.voices")
    }

    private func clipRow(_ clip: VoiceClipDTO, client: BubuLearningClient) -> some View {
        Button { Task { await toggle(clip, client: client) } } label: {
            HStack(spacing: BubuTheme.Spacing.m) {
                ZStack {
                    Circle().fill(playing == clip.id ? BubuTheme.Color.primary : BubuTheme.Color.pinkSurface)
                    Image(systemName: playing == clip.id ? "speaker.wave.3.fill" : "play.fill")
                        .foregroundStyle(playing == clip.id ? .white : BubuTheme.Color.deepRose)
                        .symbolEffect(.variableColor.iterative, isActive: playing == clip.id)
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
        .accessibilityIdentifier("brain.voice")
    }

    private func toggle(_ clip: VoiceClipDTO, client: BubuLearningClient) async {
        if playing == clip.id { stop(); return }
        stop()
        do {
            let data = try await client.mediaData(clip.audioUrl, cache: true)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("bubu-voice-\(clip.id).m4a")
            try data.write(to: file, options: .atomic)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            let player = AVPlayer(url: file)
            self.player = player
            playing = clip.id
            player.play()
            BubuHaptics.tapLight()
            let duration = max(1, clip.end - clip.start) + 0.5
            try? await Task.sleep(for: .seconds(duration))
            if playing == clip.id { stop() }
        } catch {
            errorText = learningErrorText(error, fallback: "这段声音暂时放不出来。")
        }
    }

    private func stop() {
        player?.pause(); player = nil; playing = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - 认一认

/// Swipe-to-confirm queue for photos the library wasn't sure about. Decisions stay on
/// the 布布 side: yes adds the photo to 布布的时光, no keeps it out. Nothing is written back.
struct RecognitionView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var queue: [RecognitionCandidateDTO] = []
    @State private var remaining = 0
    @State private var loading = true
    @State private var drag: CGSize = .zero
    @State private var decided = 0
    @State private var errorText: String?

    var body: some View {
        let client = BubuLearningClient(env: env)
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            VStack(spacing: BubuTheme.Spacing.l) {
                Text("第二大脑不太确定这些照片里有没有布布。右滑“是布布”，左滑“不是”。只影响布布的时光，不改第二大脑。")
                    .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText).multilineTextAlignment(.center)
                if let client {
                    if loading && queue.isEmpty {
                        ProgressView().frame(maxHeight: .infinity)
                    } else if let top = queue.first {
                        ZStack {
                            ForEach(queue.prefix(3).reversed()) { candidate in
                                card(candidate, client: client, isTop: candidate.id == top.id)
                            }
                        }
                        .frame(maxHeight: .infinity)
                        HStack(spacing: BubuTheme.Spacing.l) {
                            decisionButton("不是", symbol: "xmark", tint: BubuTheme.Color.softFill, foreground: BubuTheme.Color.warmBrown) {
                                Task { await decide(top, yes: false, client: client) }
                            }
                            .accessibilityIdentifier("recognition.no")
                            decisionButton("是布布", symbol: "heart.fill", tint: BubuTheme.Color.primary, foreground: .white) {
                                Task { await decide(top, yes: true, client: client) }
                            }
                            .accessibilityIdentifier("recognition.yes")
                        }
                        Text("本轮还剩 \(queue.count) 张 · 全部待确认约 \(max(remaining, queue.count)) 张")
                            .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                            .contentTransition(.numericText())
                    } else {
                        VStack(spacing: BubuTheme.Spacing.m) {
                            BubuMascotBadge(size: 110, expression: .yeah)
                            Text(decided > 0 ? "这一轮认完啦，确认了 \(decided) 张" : (errorText ?? "现在没有需要确认的照片"))
                                .font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                            Button("再来一轮") { Task { await load(client) } }.buttonStyle(.bordered).tint(BubuTheme.Color.deepRose)
                        }
                        .frame(maxHeight: .infinity)
                    }
                } else {
                    SecondBrainUnavailable(title: "认一认")
                }
            }
            .padding(BubuTheme.Spacing.l)
            .bubuContentColumn(640)
        }
        .navigationTitle("认一认")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: client?.scope) { if let client { await load(client) } else { loading = false } }
        .accessibilityIdentifier("brain.recognition")
    }

    private func card(_ candidate: RecognitionCandidateDTO, client: BubuLearningClient, isTop: Bool) -> some View {
        VStack(spacing: 0) {
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
        .shadow(color: BubuTheme.Color.deepRose.opacity(0.15), radius: 12, y: 6)
        .overlay(alignment: .topLeading) {
            if isTop && drag.width > 40 { stamp("是布布", color: BubuTheme.Color.primary) }
        }
        .overlay(alignment: .topTrailing) {
            if isTop && drag.width < -40 { stamp("不是", color: BubuTheme.Color.warmBrown) }
        }
        .offset(isTop ? drag : .zero)
        .rotationEffect(.degrees(isTop ? Double(drag.width / 18) : 0))
        .scaleEffect(isTop ? 1 : 0.95)
        .gesture(isTop ? DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if abs(value.translation.width) > 110 {
                    Task { await decide(candidate, yes: value.translation.width > 0, client: client) }
                } else {
                    withAnimation(BubuMotion.gentle) { drag = .zero }
                }
            } : nil)
        .accessibilityElement(children: .combine)
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

    private nonisolated struct Decision: Encodable, Sendable { let decision: String }
    private nonisolated struct Decided: Decodable, Sendable {}

    private func load(_ client: BubuLearningClient) async {
        loading = true
        defer { loading = false }
        do {
            let list = try await client.get("api/recognition/candidates", query: [URLQueryItem(name: "limit", value: "20")],
                                            as: RecognitionCandidateList.self)
            queue = list.items
            remaining = list.remaining ?? list.items.count
            errorText = nil
        } catch {
            errorText = learningErrorText(error)
        }
    }

    private func decide(_ candidate: RecognitionCandidateDTO, yes: Bool, client: BubuLearningClient) async {
        withAnimation(BubuMotion.quick) { drag = CGSize(width: yes ? 600 : -600, height: 40) }
        yes ? BubuHaptics.success() : BubuHaptics.selection()
        do {
            _ = try await client.send("POST", "api/recognition/\(candidate.id)", body: Decision(decision: yes ? "yes" : "no"), as: Decided.self)
            if yes { decided += 1 }
            withAnimation(BubuMotion.gentle) {
                queue.removeAll { $0.id == candidate.id }
                remaining = max(0, remaining - 1)
            }
        } catch {
            errorText = learningErrorText(error, fallback: "没有保存成功（需要家长账号），请稍后再试。")
        }
        drag = .zero
    }
}
