import SwiftUI
import Charts

// MARK: - 语言成长线（GET words）
/// 只用声音档案里已确认是布布自己说的话：累计词数曲线 + 每月新词 + “第一次说”。
struct WordsGrowthView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var data: WordsResponseDTO?
    @State private var loading = true
    @State private var errorText: String?
    @State private var selectedMonth: String?
    @State private var chartSelection: Date?
    @State private var voice = SecondBrainVoicePlayer()
    @State private var route: TimelinePagerRoute?
    @State private var opening: String?

    var body: some View {
        let client = BubuLearningClient(env: env)
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
                    if let client {
                        if let error = voice.errorText {
                            SecondBrainErrorBanner(text: error) { voice.errorText = nil }
                        }
                        if loading && data == nil {
                            ProgressView("正在数布布说过的词…").frame(maxWidth: .infinity).padding(.vertical, 60)
                        } else if let data, !data.months.isEmpty || !data.firsts.isEmpty {
                            summary(data)
                            if !data.months.isEmpty { chartCard(data) }
                            if !data.firsts.isEmpty { firstsCard(data, client: client) }
                        } else {
                            VStack(spacing: BubuTheme.Spacing.m) {
                                BubuMascotBadge(size: 96, expression: .thinking)
                                Text(errorText ?? "还没有确认过的布布说的话。等「布布的声音」整理出来，这里就会长出一条线。")
                                    .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 50)
                        }
                    } else {
                        SecondBrainNotConnected(title: "语言成长线")
                    }
                }
                .padding(BubuTheme.Spacing.item)
                .bubuContentColumn(860)
            }
        }
        .navigationTitle("语言成长线")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: client?.scope) {
            guard let client else { loading = false; return }
            do {
                let response = try await client.get("api/words", as: WordsResponseDTO.self)
                data = response
                selectedMonth = response.months.last?.month
                errorText = nil
            } catch is CancellationError {
            } catch {
                errorText = learningErrorText(error)
            }
            loading = false
        }
        .onDisappear { voice.stop() }
        .navigationDestination(item: $route) { route in
            if let client {
                OnlineTimelineDetailPager(client: client, items: route.items, initial: route.initial, loadMore: {}, hasMore: false)
            }
        }
        .accessibilityIdentifier("brain.words")
    }

    private func summary(_ data: WordsResponseDTO) -> some View {
        HStack(spacing: BubuTheme.Spacing.m) {
            BubuMascotBadge(size: 60, expression: .happy)
            VStack(alignment: .leading, spacing: 4) {
                Text("会说 \(data.months.last?.total ?? data.firsts.count) 个词啦")
                    .font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
                if let count = data.sourceCount, count > 0 {
                    Text("来自 \(count) 段确认过的布布说的话").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
                if let pending = data.pending, pending > 0 {
                    Label("还有 \(pending) 段声音在整理", systemImage: "hourglass")
                        .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.deepRose)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(BubuTheme.Spacing.l)
        .background(BubuTheme.Color.card.opacity(0.95), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func chartCard(_ data: WordsResponseDTO) -> some View {
        let points = data.months.filter { $0.date != nil }
        let selected = data.months.first { $0.month == selectedMonth }
        return VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
            Text("累计会说的词").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            Chart(points) { month in
                AreaMark(x: .value("月份", month.date!, unit: .month), y: .value("累计", month.total))
                    .foregroundStyle(LinearGradient(colors: [BubuTheme.Color.primary.opacity(0.35), BubuTheme.Color.primary.opacity(0.03)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("月份", month.date!, unit: .month), y: .value("累计", month.total))
                    .foregroundStyle(BubuTheme.Color.deepRose)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("月份", month.date!, unit: .month), y: .value("累计", month.total))
                    .foregroundStyle(month.month == selectedMonth ? BubuTheme.Color.deepRose : BubuTheme.Color.primary)
                    .symbolSize(month.month == selectedMonth ? 140 : 60)
            }
            .chartXSelection(value: $chartSelection)
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: max(1, points.count / 6))) { _ in
                    AxisValueLabel(format: .dateTime.year(.twoDigits).month(.defaultDigits), centered: true)
                }
            }
            .frame(height: 220)
            .onChange(of: chartSelection) { _, date in
                guard let date else { return }
                let nearest = points.min { abs($0.date!.timeIntervalSince(date)) < abs($1.date!.timeIntervalSince(date)) }
                if let nearest, nearest.month != selectedMonth {
                    BubuHaptics.selection()
                    withAnimation(reduceMotion ? nil : BubuMotion.quick) { selectedMonth = nearest.month }
                }
            }
            .accessibilityLabel("累计词数曲线")
            .accessibilityValue(points.map { "\(SecondBrainMonths.caption($0.month)) \($0.total) 个" }.joined(separator: "，"))
            // VoiceOver / Switch Control can't scrub the chart; offer the months as buttons.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(data.months) { month in
                        Button {
                            BubuHaptics.selection()
                            withAnimation(reduceMotion ? nil : BubuMotion.quick) { selectedMonth = month.month }
                        } label: {
                            Text(SecondBrainMonths.caption(month.month)).font(BubuTheme.Font.caption)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .foregroundStyle(month.month == selectedMonth ? .white : BubuTheme.Color.warmBrown)
                                .background(month.month == selectedMonth ? BubuTheme.Color.deepRose : BubuTheme.Color.softFill, in: Capsule())
                        }
                        .buttonStyle(BubuPressableStyle())
                        .accessibilityAddTraits(month.month == selectedMonth ? .isSelected : [])
                    }
                }
            }
            if let selected {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(SecondBrainMonths.caption(selected.month)) · 新学会 \(selected.newWords.count) 个，累计 \(selected.total) 个")
                        .font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(BubuTheme.Color.deepRose)
                    if selected.newWords.isEmpty {
                        Text("这个月没有新词，在练习已经会的。").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading, spacing: 6) {
                            ForEach(selected.newWords, id: \.self) { word in
                                Text(word).font(BubuTheme.Font.body.weight(.semibold)).foregroundStyle(BubuTheme.Color.warmBrown)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .frame(maxWidth: .infinity)
                                    .background(BubuTheme.Color.pinkSurface, in: Capsule())
                            }
                        }
                    }
                }
                .id(selected.month)
                .transition(.opacity)
            }
        }
        .padding(BubuTheme.Spacing.l)
        .background(BubuTheme.Color.card.opacity(0.95), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    private func firstsCard(_ data: WordsResponseDTO, client: BubuLearningClient) -> some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
            Text("第一次说").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            ForEach(Array(data.firsts.enumerated()), id: \.element.id) { index, first in
                Button { Task { await tap(first, client: client) } } label: {
                    HStack(spacing: BubuTheme.Spacing.m) {
                        Text(first.word).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.deepRose)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .frame(minWidth: 64)
                            .padding(.horizontal, 8).padding(.vertical, 8)
                            .background(BubuTheme.Color.pinkSurface, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            if let text = first.text, !text.isEmpty {
                                Text("“\(text)”").font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown).lineLimit(2)
                            }
                            if let date = first.date {
                                Text(date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))
                                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                            }
                        }
                        Spacer(minLength: 0)
                        icon(first)
                    }
                    .padding(BubuTheme.Spacing.s)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BubuPressableStyle())
                .entranceEffect(index: index)
                .accessibilityElement(children: .combine)
                .accessibilityHint(first.voiceId != nil ? "播放她说这个词的声音" : "打开那段素材")
                .accessibilityIdentifier("words.first")
            }
        }
        .padding(BubuTheme.Spacing.l)
        .background(BubuTheme.Color.card.opacity(0.95), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private func icon(_ first: WordFirstDTO) -> some View {
        if let voiceID = first.voiceId {
            let playing = voice.playing == voiceID
            if voice.loading == voiceID {
                ProgressView().frame(width: 36, height: 36)
            } else {
                Image(systemName: playing ? "speaker.wave.3.fill" : "play.circle.fill")
                    .font(.system(size: 28, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.deepRose)
                    .symbolEffect(.variableColor.iterative, isActive: playing && !reduceMotion)
                    .frame(width: 36, height: 36)
            }
        } else if first.itemId != nil {
            if opening == first.itemId {
                ProgressView().frame(width: 36, height: 36)
            } else {
                Image(systemName: "photo.on.rectangle").font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.secondaryText).frame(width: 36, height: 36)
            }
        }
    }

    private func tap(_ first: WordFirstDTO, client: BubuLearningClient) async {
        if let voiceID = first.voiceId {
            await voice.toggle(id: voiceID, path: SecondBrainVoicePlayer.audioPath(voiceID: voiceID), client: client)
        } else if let itemID = first.itemId, opening == nil {
            opening = itemID
            defer { opening = nil }
            do {
                if let item = try await client.timelineItems(ids: [itemID]).first {
                    route = TimelinePagerRoute(items: [item], initial: item)
                } else {
                    voice.errorText = "这段素材已经不在布布的时光里了。"
                }
            } catch {
                voice.errorText = learningErrorText(error)
            }
        }
    }
}
