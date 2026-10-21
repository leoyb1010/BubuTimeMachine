import SwiftUI

struct LearningPlayItem: Hashable, Identifiable {
    let packID: String
    let activity: LearningActivityDTO
    var id: String { packID + "/" + activity.id }
}

/// 布布的互动页：先播放老师这道题的原声（不是开场介绍），点选后再听老师的答案。
/// 不给孩子打分；只记录互动，供周/月复习挑选需要再玩一次的内容。
struct LearningPlayView: View {
    let client: BubuLearningClient
    let childID: String?
    let items: [LearningPlayItem]
    let title: String
    @State private var index = 0
    @State private var chosen: String?
    @State private var answered = false
    @State private var player = NativeLearningAudioPlayer()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private var current: LearningPlayItem? { items.indices.contains(index) ? items[index] : nil }

    var body: some View {
        NavigationStack {
            ZStack {
                BubuThemedBackground().ignoresSafeArea()
                if let current {
                    ScrollView {
                        activityView(current)
                            .padding(BubuTheme.Spacing.l)
                            .bubuContentColumn(820)
                    }
                    .id(current.id)
                } else {
                    finished
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("结束") { player.stop(); dismiss() }.accessibilityIdentifier("learning.play.close")
                }
                ToolbarItem(placement: .principal) { progressDots }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { player.stop() } }
        .onDisappear { player.stop() }
        .task(id: index) {
            chosen = nil; answered = false
            guard let current else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            player.play(clip: current.activity.prompt, activityKind: current.activity.kind, isAnswer: false, client: client)
        }
    }

    // MARK: Activity

    @ViewBuilder
    private func activityView(_ item: LearningPlayItem) -> some View {
        let activity = item.activity
        VStack(spacing: BubuTheme.Spacing.l) {
            Text(activity.kindLabel).font(BubuTheme.Font.caption.weight(.bold))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(BubuTheme.Color.pinkSurface, in: Capsule())
                .foregroundStyle(BubuTheme.Color.deepRose)
            Text(activity.title).font(BubuTheme.Font.hugeTitle).foregroundStyle(BubuTheme.Color.warmBrown)
                .multilineTextAlignment(.center)
            if let image = activity.prompt?.imageUrl, !activity.isChoice || activity.kind == "speak" {
                LearningRemoteImage(path: image, client: client, label: "老师上课时的画面", maxHeight: 280)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            }
            listenButton(activity)
            if activity.isChoice {
                choices(item)
            } else if activity.kind == "speak" {
                speak(item)
            } else {
                participation(item, label: "一起唱完啦")
            }
            if answered { nextButton }
            if let error = player.errorText {
                Text(error).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.danger)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func listenButton(_ activity: LearningActivityDTO) -> some View {
        Button {
            player.play(clip: activity.prompt, activityKind: activity.kind, isAnswer: false, client: client)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: player.isPlaying && !player.playingAnswer ? "speaker.wave.3.fill" : "ear.fill")
                    .font(.title).symbolEffect(.variableColor.iterative, isActive: player.isPlaying && !player.playingAnswer)
                Text(activity.kind == "music" ? "听老师唱" : "再听老师说").font(BubuTheme.Font.headline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28).padding(.vertical, 16)
            .background(BubuTheme.Gradient.primaryButton, in: Capsule())
            .shadow(color: BubuTheme.Color.primary.opacity(0.3), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("learning.play.listen")
    }

    private func choices(_ item: LearningPlayItem) -> some View {
        let activity = item.activity
        return VStack(spacing: BubuTheme.Spacing.m) {
            // Column count follows the choices so two or three cards stay centred on iPad too.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(maximum: 280), spacing: 14),
                                     count: max(1, min(activity.choices.count, 3))), spacing: 14) {
                ForEach(activity.choices) { choice in
                    Button {
                        guard !answered else { return }
                        chosen = choice.id
                        answered = true
                        record(item, choice: choice.id, assistance: nil)
                        if let answer = activity.answer {
                            player.play(clip: answer, activityKind: activity.kind, isAnswer: true, client: client)
                        }
                    } label: {
                        ChoiceTile(choice: choice, client: client,
                                   highlighted: answered && choice.id == activity.correctChoice,
                                   dimmed: answered && choice.id != activity.correctChoice && choice.id == chosen)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("learning.play.choice")
                }
            }
            if answered {
                let right = chosen == activity.correctChoice
                Label(right ? "找对啦！" : "没关系，听老师说答案", systemImage: right ? "star.fill" : "heart.fill")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(right ? BubuTheme.Color.deepRose : BubuTheme.Color.warmBrown)
                Button {
                    player.play(clip: activity.answer, activityKind: activity.kind, isAnswer: true, client: client)
                } label: { Label("听老师说答案", systemImage: "speaker.wave.2") }
                    .buttonStyle(.bordered).tint(BubuTheme.Color.deepRose)
            }
        }
    }

    private func speak(_ item: LearningPlayItem) -> some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            Text("轮到布布说一说啦").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            if answered {
                Button {
                    player.play(clip: item.activity.answer, activityKind: item.activity.kind, isAnswer: true, client: client)
                } label: { Label("听老师的示范", systemImage: "speaker.wave.2") }
                    .buttonStyle(.bordered).tint(BubuTheme.Color.deepRose)
            } else {
                HStack(spacing: BubuTheme.Spacing.m) {
                    bigChoice("说出来啦", symbol: "face.smiling.fill", tint: BubuTheme.Color.primary) {
                        answered = true; record(item, choice: nil, assistance: false)
                    }
                    bigChoice("要听提示", symbol: "lightbulb.fill", tint: SchoolPalette.orange) {
                        answered = true; record(item, choice: nil, assistance: true)
                        player.play(clip: item.activity.answer, activityKind: item.activity.kind, isAnswer: true, client: client)
                    }
                }
            }
        }
    }

    private func participation(_ item: LearningPlayItem, label: String) -> some View {
        Group {
            if !answered {
                bigChoice(label, symbol: "music.note", tint: SchoolPalette.green) {
                    answered = true; record(item, choice: nil, assistance: nil)
                }
            }
        }
    }

    private func bigChoice(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 36))
                Text(title).font(BubuTheme.Font.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(tint, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var nextButton: some View {
        Button {
            player.stop()
            withAnimation(BubuMotion.gentle) { index += 1 }
        } label: {
            Text(index + 1 < items.count ? "下一个" : "完成").font(BubuTheme.Font.headline)
                .frame(maxWidth: 320).padding(.vertical, 14)
                .foregroundStyle(BubuTheme.Color.deepRose)
                .background(BubuTheme.Color.card, in: Capsule())
                .overlay(Capsule().stroke(BubuTheme.Color.primary, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("learning.play.next")
    }

    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(items.indices, id: \.self) { i in
                Circle().fill(i <= index ? BubuTheme.Color.primary : BubuTheme.Color.hairline)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("第 \(min(index + 1, items.count)) 个，共 \(items.count) 个")
    }

    private var finished: some View {
        VStack(spacing: BubuTheme.Spacing.l) {
            Image(systemName: "star.circle.fill").font(.system(size: 88))
                .symbolRenderingMode(.palette).foregroundStyle(.white, BubuTheme.Color.primary)
            Text("今天学完啦！").font(BubuTheme.Font.hugeTitle).foregroundStyle(BubuTheme.Color.warmBrown)
            Text("和老师一起玩了 \(items.count) 个小互动").font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            Button("回到课程") { dismiss() }.buttonStyle(.borderedProminent).tint(BubuTheme.Color.primary)
                .accessibilityIdentifier("learning.play.done")
        }
        .padding()
    }

    private func record(_ item: LearningPlayItem, choice: String?, assistance: Bool?) {
        guard let childID else { return }
        let body = LearningAttemptBody(id: UUID().uuidString, childId: childID, packId: item.packID,
                                       activityId: item.activity.id, kind: item.activity.kind,
                                       choice: choice, assistance: assistance)
        Task { await LearningAttemptOutbox.shared.submit(body, client: client) }
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
        .accessibilityElement(children: .combine)
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
                            SchoolPanel(title: "这次复习", symbol: "sparkles") {
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

/// 先落盘再上传；同一 UUID 重试由服务端幂等去重。按服务+账号隔离，不依赖网页存储。
actor LearningAttemptOutbox {
    static let shared = LearningAttemptOutbox()
    private nonisolated struct Pending: Codable { let scope: String; let body: LearningAttemptBody }
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

    func submit(_ body: LearningAttemptBody, client: BubuLearningClient) async {
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
