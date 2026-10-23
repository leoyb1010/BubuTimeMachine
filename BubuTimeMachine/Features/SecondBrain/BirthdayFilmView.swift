import SwiftUI
import AVKit

// MARK: - 生日影片
/// 过去一年每个月挑 1–2 张（已确认的“第一次”优先，其次是成长小报的精选），
/// 家长可以先去掉不想要的，再在手机上合成一段 60–90 秒的竖版短片。
/// 不上传任何东西；分享/存相册都走系统分享面板，不新增权限。
struct BirthdayFilmView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.bubuLayout) private var layout

    private struct Moment: Identifiable, Hashable {
        let plan: FilmMomentPlan
        let item: OnlineTimelineItem
        var id: String { plan.itemId }
    }

    private enum Phase: Equatable {
        case loading, picking, downloading(Double), rendering(Double), done(URL), failed(String)
    }

    @State private var moments: [Moment] = []
    @State private var removed: Set<String> = []
    @State private var phase: Phase = .loading
    @State private var player: AVPlayer?
    @State private var job: Task<Void, Never>?
    /// Set when the app went to the background mid-render: the encoder stops there, so the job is cancelled on purpose.
    @State private var interruptedByBackground = false

    private var isWorking: Bool {
        switch phase {
        case .downloading, .rendering: true
        default: false
        }
    }

    private var kept: [Moment] { moments.filter { !removed.contains($0.id) } }

    var body: some View {
        let client = BubuLearningClient(env: env)
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
                    if let client {
                        header
                        content(client: client)
                    } else {
                        SecondBrainNotConnected(title: "生日影片")
                    }
                }
                .padding(BubuTheme.Spacing.item)
                .bubuContentColumn(860)
            }
        }
        .navigationTitle("生日影片")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: client?.scope) { if let client, moments.isEmpty { await load(client) } }
        .onDisappear { job?.cancel(); player?.pause() }
        .onChange(of: scenePhase) { _, newPhase in
            // The video encoder is unavailable in the background; stop cleanly instead of stalling.
            if newPhase == .background, isWorking {
                interruptedByBackground = true
                job?.cancel()
            }
        }
        .accessibilityIdentifier("brain.birthday-film")
    }

    private var header: some View {
        HStack(spacing: BubuTheme.Spacing.m) {
            BubuMascotBadge(size: 64, expression: .cheer)
            VStack(alignment: .leading, spacing: 4) {
                Text("布布的又一年").font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
                Text("每个月挑出最好的瞬间，在手机上合成一段竖版小影片。轻点照片可以去掉它。")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
        .padding(BubuTheme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.card.opacity(0.95), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private func content(client: BubuLearningClient) -> some View {
        switch phase {
        case .loading:
            ProgressView("正在翻这一年的相册…").frame(maxWidth: .infinity).padding(.vertical, 60)
        case .failed(let message):
            VStack(spacing: BubuTheme.Spacing.m) {
                SecondBrainErrorBanner(text: message)
                if kept.count >= 3 {
                    // Rendering failed: keep the photos the parent picked and try again directly.
                    Button("再试一次") { start(client) }.buttonStyle(.borderedProminent).tint(BubuTheme.Color.deepRose)
                        .accessibilityIdentifier("film.retry")
                    Button("重新挑选") {
                        withAnimation(reduceMotion ? nil : BubuMotion.gentle) { phase = .picking }
                    }
                    .buttonStyle(.bordered).tint(BubuTheme.Color.deepRose)
                } else {
                    Button("再试一次") { Task { await load(client) } }.buttonStyle(.bordered).tint(BubuTheme.Color.deepRose)
                        .accessibilityIdentifier("film.retry")
                }
            }
        case .picking:
            picker(client: client)
        case .downloading(let value):
            progressCard(title: "正在取回照片…", value: value * 0.25)
        case .rendering(let value):
            progressCard(title: "正在一帧一帧地拼影片…", value: 0.25 + value * 0.75)
        case .done(let url):
            result(url)
        }
    }

    private func picker(client: BubuLearningClient) -> some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
            if moments.isEmpty {
                Text("这一年还没有成长小报或确认过的“第一次”，先去「成长小报」和「可能的第一次」看看吧。")
                    .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
                    ForEach(moments) { moment in
                        let isRemoved = removed.contains(moment.id)
                        Button {
                            BubuHaptics.selection()
                            withAnimation(reduceMotion ? nil : BubuMotion.quick) {
                                if isRemoved { removed.remove(moment.id) } else { removed.insert(moment.id) }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                SecondBrainThumb(item: moment.item, client: client, height: 132)
                                    .opacity(isRemoved ? 0.35 : 1)
                                    .overlay(alignment: .topTrailing) {
                                        Image(systemName: isRemoved ? "plus.circle.fill" : "checkmark.circle.fill")
                                            .font(BubuTheme.Font.headline).symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, isRemoved ? BubuTheme.Color.secondaryText : BubuTheme.Color.actionFill)
                                            .padding(6)
                                    }
                                Text(moment.plan.caption).font(BubuTheme.Font.scaled(11, weight: .semibold))
                                    .foregroundStyle(BubuTheme.Color.warmBrown).lineLimit(2)
                            }
                        }
                        .buttonStyle(BubuPressableStyle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(moment.plan.caption)
                        .accessibilityValue(isRemoved ? "已去掉" : "已选中")
                        .accessibilityHint(isRemoved ? "轻点放回影片" : "轻点从影片里去掉")
                    }
                }
                let count = kept.count
                Text("已选 \(count) 张 · 约 \(Int(BirthdayFilmRenderer.duration(photoCount: count).rounded())) 秒 · 无背景音乐")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    .contentTransition(.numericText())
                Button { start(client) } label: {
                    Label("生成影片", systemImage: "film.fill").font(BubuTheme.Font.headline)
                        .frame(maxWidth: .infinity).padding(.vertical, 14).foregroundStyle(.white)
                        .background(BubuTheme.Gradient.primaryButton,
                                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.button, style: .continuous))
                }
                .buttonStyle(BubuPressableStyle())
                .disabled(count < 3)
                .opacity(count < 3 ? 0.5 : 1)
                .accessibilityIdentifier("film.render")
            }
        }
    }

    private func progressCard(title: String, value: Double) -> some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            BubuMascotBadge(size: 96, expression: .drawing).bubuFloating()
            Text(title).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            ProgressView(value: min(max(value, 0), 1)).tint(BubuTheme.Color.primary)
            Text("\(Int((min(max(value, 0), 1) * 100).rounded()))%").font(BubuTheme.Font.caption.monospacedDigit())
                .foregroundStyle(BubuTheme.Color.secondaryText).contentTransition(.numericText())
            Label("大约 1 分钟，请停在这一页，屏幕会保持常亮", systemImage: "iphone")
                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
            Button("取消", role: .cancel) { job?.cancel() }.font(BubuTheme.Font.caption)
        }
        .padding(BubuTheme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(BubuTheme.Color.card.opacity(0.95), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// 竖版预览的最高高度：常规 560；矮屏 / 横拿不超过安全区高度减一点边距（至少 240），一屏看全。
    private var filmMaxHeight: CGFloat {
        guard layout.size.height > 0 else { return 560 }
        return min(560, max(240, layout.safeRect.height - 24))
    }

    private func result(_ url: URL) -> some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            VideoPlayer(player: player)
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                // 用宽度封顶来限高（滚动容器里高度提案为 nil，maxHeight 管不住 fit）：
                // 常规最高 560pt；矮屏按可用高度撑满一屏，竖版片子不会高出屏幕。
                .frame(maxWidth: filmMaxHeight * 9.0 / 16.0)
                .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                .accessibilityLabel("生日影片预览")
            ShareLink(item: url, preview: SharePreview("布布的又一年", image: Image(systemName: "film"))) {
                Label("分享或存到相册", systemImage: "square.and.arrow.up").font(BubuTheme.Font.headline)
                    .frame(maxWidth: .infinity).padding(.vertical, 14).foregroundStyle(.white)
                    .background(BubuTheme.Gradient.primaryButton,
                                in: RoundedRectangle(cornerRadius: BubuTheme.Radius.button, style: .continuous))
            }
            .buttonStyle(BubuPressableStyle())
            .accessibilityIdentifier("film.share")
            Button("重新挑选") {
                player?.pause(); player = nil
                withAnimation(reduceMotion ? nil : BubuMotion.gentle) { phase = .picking }
            }
            .buttonStyle(.bordered).tint(BubuTheme.Color.deepRose)
        }
    }

    // MARK: Work

    private func load(_ client: BubuLearningClient) async {
        phase = .loading
        do {
            async let reportsTask = client.get("api/monthly", as: MonthlyReportList.self)
            async let firstsTask = client.get("api/firsts", query: [URLQueryItem(name: "status", value: "all")], as: GrowthFirstListDTO.self)
            let reportsResult: Result<MonthlyReportList, Error>
            let firstsResult: Result<GrowthFirstListDTO, Error>
            do { reportsResult = .success(try await reportsTask) } catch { reportsResult = .failure(error) }
            do { firstsResult = .success(try await firstsTask) } catch { firstsResult = .failure(error) }
            // Both sources unreachable (offline, server down): show a retryable error, not "no material yet".
            if case .failure(let error) = reportsResult, case .failure = firstsResult { throw error }
            let reports = (try? reportsResult.get())?.items ?? []
            let firsts = (try? firstsResult.get())?.items ?? []
            let plans = BirthdayFilmPlanner.select(months: SecondBrainMonths.trailing(12, endingAt: .now),
                                                   reports: reports, firsts: firsts, perMonth: 2)
            let items = try await client.timelineItems(ids: plans.map(\.itemId))
            let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            moments = plans.compactMap { plan in byID[plan.itemId].map { Moment(plan: plan, item: $0) } }
            removed = []
            phase = .picking
        } catch let error where isCancellation(error) {
        } catch {
            phase = .failed(learningErrorText(error))
        }
    }

    private func start(_ client: BubuLearningClient) {
        let chosen = kept
        let months = chosen.map(\.plan.month).sorted()
        let subtitle = [months.first, months.last].compactMap { $0 }.map(SecondBrainMonths.caption)
            .reduce("") { $0.isEmpty ? $1 : $0 + " – " + $1 }
        BubuHaptics.tapLight()
        job?.cancel()
        interruptedByBackground = false
        job = Task {
            // Keep the screen awake and ask for background time while the film is assembled.
            let keepAlive = LearningUploadKeepAlive()
            defer { keepAlive.end() }
            phase = .downloading(0)
            do {
                // Large preview of a photo, or the poster frame of a video; LearningMediaGate caps concurrency.
                let paths = chosen.map(\.item.largeUrl)
                var downloaded = [Data?](repeating: nil, count: paths.count)
                try await withThrowingTaskGroup(of: (Int, Data?).self) { group in
                    for (index, path) in paths.enumerated() {
                        group.addTask { (index, try? await client.mediaData(path)) }
                    }
                    var finished = 0
                    for try await (index, data) in group {
                        try Task.checkCancellation()
                        downloaded[index] = data
                        finished += 1
                        phase = .downloading(Double(finished) / Double(paths.count))
                    }
                }
                let frames = zip(chosen, downloaded).compactMap { moment, data in
                    data.map { FilmFrameInput(imageData: $0, caption: moment.plan.caption) }
                }
                guard frames.count >= 3 else { throw LearningServiceError.unavailableMedia }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("布布的又一年.mp4")
                phase = .rendering(0)
                try await BirthdayFilmRenderer.render(
                    moments: frames, title: "布布的又一年", subtitle: subtitle,
                    closing: "生日快乐，布布", closingSubtitle: "下一年，也一起慢慢记下来", to: url,
                    progress: { value in phase = .rendering(value) })
                player = AVPlayer(url: url)
                BubuHaptics.success()
                withAnimation(reduceMotion ? nil : BubuMotion.gentle) { phase = .done(url) }
            } catch let error where isCancellation(error) {
                if interruptedByBackground {
                    interruptedByBackground = false
                    phase = .failed("离开这一页后影片就停下来了。挑好的照片都还在，点「再试一次」接着做。")
                } else {
                    phase = .picking
                }
            } catch {
                phase = .failed(learningErrorText(error, fallback: "影片没有生成成功，请稍后再试。"))
            }
        }
    }
}
