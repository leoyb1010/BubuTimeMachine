import SwiftUI
import Charts

// MARK: - 学习周报数据

/// `GET api/attempts` 的单条记录（服务端公开字段的子集）。
nonisolated struct LearningAttemptRecordDTO: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let packId: String?
    let activityId: String?
    /// 秒级时间戳。
    let createdAt: Double?
    /// 活动类型（listen_choice / speak / music …）。
    let kind: String?
    /// 事件类型（choice / speaking_attempt / participation …）。
    let eventKind: String?
    let correct: Bool?
    let assistance: Bool?
    let note: String?
    let concept: String?

    init(id: String, packId: String? = nil, activityId: String? = nil, createdAt: Double? = nil, kind: String? = nil,
         eventKind: String? = nil, correct: Bool? = nil, assistance: Bool? = nil, note: String? = nil, concept: String? = nil) {
        self.id = id; self.packId = packId; self.activityId = activityId; self.createdAt = createdAt; self.kind = kind
        self.eventKind = eventKind; self.correct = correct; self.assistance = assistance; self.note = note; self.concept = concept
    }

    private enum CodingKeys: String, CodingKey {
        case id, packId, activityId, createdAt, kind, eventKind, correct, assistance, note, concept
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        packId = try c.decodeIfPresent(String.self, forKey: .packId)
        activityId = try c.decodeIfPresent(String.self, forKey: .activityId)
        // 时间戳可能是数字也可能是字符串，宽松解析，坏一条不影响整页。
        if let value = try? c.decodeIfPresent(Double.self, forKey: .createdAt) {
            createdAt = value
        } else if let text = try? c.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = Double(text) ?? BubuLearningDates.parseISO(text)?.timeIntervalSince1970
        } else {
            createdAt = nil
        }
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        eventKind = try? c.decodeIfPresent(String.self, forKey: .eventKind)
        correct = try? c.decodeIfPresent(Bool.self, forKey: .correct)
        assistance = try? c.decodeIfPresent(Bool.self, forKey: .assistance)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        concept = try? c.decodeIfPresent(String.self, forKey: .concept)
    }

    var date: Date? { createdAt.map(Date.init(timeIntervalSince1970:)) }

    /// 跟读分数：备注里的 `score:85`。
    var speakScore: Int? {
        guard let note, let range = note.range(of: #"score:\s*(\d{1,3})"#, options: .regularExpression) else { return nil }
        let digits = note[range].filter(\.isNumber)
        return Int(digits).map { min($0, 100) }
    }
}

nonisolated struct LearningAttemptRecordList: Decodable, Sendable { let items: [LearningAttemptRecordDTO] }

/// 一周学习的汇总（纯计算，便于测试）。
nonisolated struct LearningWeeklySummary: Sendable, Equatable {
    struct Day: Sendable, Equatable, Identifiable {
        let date: Date
        let label: String
        let count: Int
        var id: Date { date }
    }
    struct KindAccuracy: Sendable, Equatable, Identifiable {
        let kind: String
        let label: String
        let correct: Int
        let total: Int
        var percent: Int { total == 0 ? 0 : Int((Double(correct) / Double(total) * 100).rounded()) }
        var id: String { kind }
    }
    struct SpeakPoint: Sendable, Equatable, Identifiable {
        let date: Date
        let label: String
        let score: Int
        var id: Date { date }
    }
    struct Suggestion: Sendable, Equatable, Identifiable {
        let title: String
        let reason: String
        var id: String { title }
    }

    let weekStart: Date
    let lessonsPublished: Int
    let lessonsPracticed: Int
    let activitiesDone: Int
    let days: [Day]
    let accuracy: [KindAccuracy]
    let speakScores: [SpeakPoint]
    let words: [String]
    let suggestions: [Suggestion]

    var isEmpty: Bool { lessonsPublished == 0 && activitiesDone == 0 && suggestions.isEmpty }
    var activeDays: Int { days.filter { $0.count > 0 }.count }
    var averageSpeakScore: Int? {
        speakScores.isEmpty ? nil : speakScores.map(\.score).reduce(0, +) / speakScores.count
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    /// 包含 date 的那一周的周一 0 点（上海时区，和课程日期一致）。
    static func weekStart(containing date: Date) -> Date {
        let calendar = calendar
        let day = calendar.startOfDay(for: date)
        let weekday = (calendar.component(.weekday, from: day) + 5) % 7  // Monday = 0
        return calendar.date(byAdding: .day, value: -weekday, to: day) ?? day
    }

    static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "listen_choice": "听一听，找一找"
        case "color_choice": "认颜色"
        case "sort": "放一放"
        case "speak": "跟老师说"
        case "music": "一起唱"
        default: "互动"
        }
    }

    static func make(weekStart: Date, courses: [LearningCourseDTO], attempts: [LearningAttemptRecordDTO],
                     review: [LearningReviewDTO.Item]) -> LearningWeeklySummary {
        let calendar = calendar
        let start = calendar.startOfDay(for: weekStart)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
        let inWeek = attempts.filter { attempt in
            guard let date = attempt.date else { return false }
            return date >= start && date < end
        }
        let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]
        func dayIndex(_ date: Date) -> Int {
            min(max(calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0, 0), 6)
        }

        var perDay = [Int](repeating: 0, count: 7)
        for attempt in inWeek { if let date = attempt.date { perDay[dayIndex(date)] += 1 } }
        let days = (0..<7).map { index in
            Day(date: calendar.date(byAdding: .day, value: index, to: start) ?? start,
                label: "周" + weekdayLabels[index], count: perDay[index])
        }

        var accuracy: [String: (correct: Int, total: Int)] = [:]
        for attempt in inWeek where attempt.eventKind == "choice" {
            guard let correct = attempt.correct, let kind = attempt.kind, kind != "unknown" else { continue }
            var value = accuracy[kind] ?? (0, 0)
            value.total += 1
            if correct { value.correct += 1 }
            accuracy[kind] = value
        }
        let kindOrder = ["listen_choice", "color_choice", "sort"]
        let accuracyRows = accuracy.map { KindAccuracy(kind: $0.key, label: kindLabel($0.key), correct: $0.value.correct, total: $0.value.total) }
            .sorted { (kindOrder.firstIndex(of: $0.kind) ?? 99, $0.kind) < (kindOrder.firstIndex(of: $1.kind) ?? 99, $1.kind) }

        var scoresByDay: [Int: [Int]] = [:]
        for attempt in inWeek {
            guard let score = attempt.speakScore, let date = attempt.date else { continue }
            scoresByDay[dayIndex(date), default: []].append(score)
        }
        let speak = scoresByDay.keys.sorted().map { index in
            let values = scoresByDay[index] ?? []
            return SpeakPoint(date: days[index].date, label: days[index].label,
                              score: values.reduce(0, +) / max(values.count, 1))
        }

        var wordCounts: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        for (offset, attempt) in inWeek.enumerated() {
            let word = (attempt.concept ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            wordCounts[word, default: 0] += 1
            if firstSeen[word] == nil { firstSeen[word] = offset }
        }
        let words = wordCounts.keys.sorted {
            (wordCounts[$0] ?? 0, -(firstSeen[$0] ?? 0)) > (wordCounts[$1] ?? 0, -(firstSeen[$1] ?? 0))
        }

        var seen = Set<String>()
        let suggestions = review.compactMap { item -> Suggestion? in
            let concept = item.concept.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = concept.isEmpty ? item.activity.title : concept
            guard !title.isEmpty, seen.insert(title).inserted else { return nil }
            return Suggestion(title: title, reason: item.reason)
        }

        let startKey = BubuLearningDates.dayString(start)
        let endKey = BubuLearningDates.dayString(end.addingTimeInterval(-1))
        let weekCourses = courses.filter { $0.schoolDate >= startKey && $0.schoolDate <= endKey }
        let packs = Set(inWeek.compactMap(\.packId))

        return LearningWeeklySummary(
            weekStart: start,
            lessonsPublished: weekCourses.filter { $0.state == "published" }.count,
            lessonsPracticed: packs.count,
            activitiesDone: inWeek.count,
            days: days,
            accuracy: accuracyRows,
            speakScores: speak,
            words: Array(words.prefix(24)),
            suggestions: Array(suggestions.prefix(6)))
    }
}

// MARK: - 学习周报（家长看）

struct LearningWeeklyReportView: View {
    let client: BubuLearningClient
    let childID: String?
    @State private var weekStart: Date
    @State private var summary: LearningWeeklySummary?
    @State private var loading = false
    @State private var errorText: String?

    init(client: BubuLearningClient, childID: String?, day: Date) {
        self.client = client
        self.childID = childID
        _weekStart = State(initialValue: LearningWeeklySummary.weekStart(containing: day))
    }

    private var weekEnd: Date {
        LearningWeeklySummary.calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
    }
    private var isCurrentWeek: Bool { weekStart >= LearningWeeklySummary.weekStart(containing: .now) }

    var body: some View {
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
                    weekSwitcher
                    if let summary {
                        summaryCard(summary)
                        dailyChart(summary)
                        accuracySection(summary)
                        speakSection(summary)
                        wordsSection(summary)
                        suggestionsSection(summary)
                    } else if let errorText {
                        ContentUnavailableView {
                            Label("周报暂时打不开", systemImage: "exclamationmark.triangle")
                        } description: { Text(errorText) } actions: {
                            Button("重新加载") { Task { await load() } }.buttonStyle(.borderedProminent)
                                .tint(BubuTheme.Color.deepRose)
                        }
                    } else {
                        ProgressView("正在整理这一周…").frame(maxWidth: .infinity).padding(.vertical, 60)
                    }
                }
                .padding(BubuTheme.Spacing.item)
                .bubuContentColumn(820)
            }
            .refreshable { await load() }
        }
        .navigationTitle("本周学习报告")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: weekStart) { await load() }
        .accessibilityIdentifier("learning.weekly")
    }

    // MARK: Sections

    private var weekSwitcher: some View {
        HStack {
            Button { shift(-7) } label: { Label("上一周", systemImage: "chevron.left") }
            Spacer()
            Text("\(dayLabel(weekStart)) – \(dayLabel(weekEnd))")
                .font(BubuTheme.Font.body.weight(.semibold))
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Spacer()
            Button { shift(7) } label: { Label("下一周", systemImage: "chevron.right").labelStyle(.titleAndIcon) }
                .disabled(isCurrentWeek)
        }
        .font(BubuTheme.Font.caption)
        .tint(BubuTheme.Color.deepRose)
    }

    private func summaryCard(_ summary: LearningWeeklySummary) -> some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
            HStack(alignment: .top, spacing: BubuTheme.Spacing.m) {
                BubuMascotBadge(size: 56, expression: summary.activitiesDone > 0 ? .yeah : .happy)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(summary)).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary.activeDays > 0 ? "这周有 \(summary.activeDays) 天一起学习" : "这周还没有开始学习，挑一节课一起玩吧")
                        .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            // 大字号时四个数字自动换成两行两列。
            ViewThatFits(in: .horizontal) {
                HStack(spacing: BubuTheme.Spacing.s) { stats(summary) }
                Grid(horizontalSpacing: BubuTheme.Spacing.s, verticalSpacing: BubuTheme.Spacing.s) {
                    let items = statItems(summary)
                    GridRow { statTile(items[0]); statTile(items[1]) }
                    GridRow { statTile(items[2]); statTile(items[3]) }
                }
            }
        }
        .padding(BubuTheme.Spacing.l)
        .background(
            LinearGradient(colors: [BubuTheme.Color.pinkSurface, BubuTheme.Color.butterSurface],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func headline(_ summary: LearningWeeklySummary) -> String {
        if summary.activitiesDone == 0 { return "新的一周，等布布来玩" }
        if summary.activitiesDone >= 20 { return "布布这周超级认真！" }
        return "布布这周学得很开心"
    }

    private struct StatItem { let value: String; let label: String; let tint: Color }

    private func statItems(_ summary: LearningWeeklySummary) -> [StatItem] {
        [StatItem(value: "\(summary.lessonsPublished)", label: "开放课程", tint: BubuTheme.Color.card),
         StatItem(value: "\(summary.lessonsPracticed)", label: "学过的课", tint: BubuTheme.Color.card),
         StatItem(value: "\(summary.activitiesDone)", label: "小互动", tint: BubuTheme.Color.card),
         StatItem(value: summary.averageSpeakScore.map { "\($0)" } ?? "–", label: "跟读平均", tint: BubuTheme.Color.card)]
    }

    @ViewBuilder
    private func stats(_ summary: LearningWeeklySummary) -> some View {
        ForEach(Array(statItems(summary).enumerated()), id: \.offset) { _, item in statTile(item) }
    }

    private func statTile(_ item: StatItem) -> some View {
        VStack(spacing: 2) {
            Text(item.value).font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.deepRose).monospacedDigit()
            Text(item.label).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.warmBrown)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10).padding(.horizontal, 6)
        .background(item.tint.opacity(0.85), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.label) \(item.value)")
    }

    private func dailyChart(_ summary: LearningWeeklySummary) -> some View {
        LearningPanel(title: "每天的小互动", symbol: "chart.bar.fill") {
            Chart(summary.days) { day in
                BarMark(x: .value("日期", day.label), y: .value("互动", day.count))
                    .foregroundStyle(BubuTheme.Color.primary.gradient)
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        if day.count > 0 {
                            Text("\(day.count)").font(.caption2.weight(.bold)).foregroundStyle(BubuTheme.Color.warmBrown)
                        }
                    }
            }
            .chartYAxis(.hidden)
            .frame(height: 170)
            .accessibilityLabel("每天的小互动次数")
        }
    }

    @ViewBuilder
    private func accuracySection(_ summary: LearningWeeklySummary) -> some View {
        if !summary.accuracy.isEmpty {
            LearningPanel(title: "找一找答对了多少", symbol: "target", subtitle: "只看自己选的题") {
                ForEach(summary.accuracy) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.label).font(BubuTheme.Font.body.weight(.semibold))
                            Spacer()
                            Text("\(row.correct)/\(row.total) · \(row.percent)%").font(BubuTheme.Font.caption).monospacedDigit()
                        }
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        ProgressView(value: Double(row.correct), total: Double(max(row.total, 1)))
                            .tint(BubuTheme.Color.deepRose)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.label)，答对 \(row.correct) 题，共 \(row.total) 题")
                }
            }
        }
    }

    @ViewBuilder
    private func speakSection(_ summary: LearningWeeklySummary) -> some View {
        LearningPanel(title: "跟读", symbol: "mouth.fill", subtitle: summary.speakScores.isEmpty ? "" : "每天平均分") {
            if summary.speakScores.isEmpty {
                Text("这周还没有跟读。在互动里点麦克风，就能跟老师说一说。")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            } else {
                Chart(summary.speakScores) { point in
                    LineMark(x: .value("日期", point.label), y: .value("分数", point.score))
                        .foregroundStyle(BubuTheme.Color.deepRose)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("日期", point.label), y: .value("分数", point.score))
                        .foregroundStyle(BubuTheme.Color.primary)
                        .annotation(position: .top) {
                            Text("\(point.score)").font(.caption2.weight(.bold)).foregroundStyle(BubuTheme.Color.warmBrown)
                        }
                }
                .chartYScale(domain: 0...100)
                .chartXScale(domain: summary.days.map(\.label))
                .frame(height: 150)
                .accessibilityLabel("跟读分数：" + summary.speakScores.map { "\($0.label) \($0.score) 分" }.joined(separator: "，"))
            }
        }
    }

    @ViewBuilder
    private func wordsSection(_ summary: LearningWeeklySummary) -> some View {
        if !summary.words.isEmpty {
            LearningPanel(title: "练过的词", symbol: "textformat.abc", subtitle: "\(summary.words.count) 个") {
                LearningWordFlow(words: summary.words)
            }
        }
    }

    private func suggestionsSection(_ summary: LearningWeeklySummary) -> some View {
        LearningPanel(title: "下周建议复习", symbol: "arrow.triangle.2.circlepath", accent: BubuTheme.Color.deepRose) {
            if summary.suggestions.isEmpty {
                Text("暂时没有需要特别复习的内容，保持现在的节奏就很好。")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            } else {
                ForEach(summary.suggestions) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "heart.fill").foregroundStyle(BubuTheme.Color.primary).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(BubuTheme.Font.body.weight(.semibold)).foregroundStyle(BubuTheme.Color.warmBrown)
                            if !item.reason.isEmpty {
                                Text(item.reason).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Data

    private func dayLabel(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.month().day().locale(Locale(identifier: "zh_CN"))
        style.timeZone = LearningWeeklySummary.calendar.timeZone
        return date.formatted(style)
    }

    private func shift(_ days: Int) {
        weekStart = LearningWeeklySummary.calendar.date(byAdding: .day, value: days, to: weekStart) ?? weekStart
    }

    private func load() async {
        let requested = weekStart
        loading = true
        defer { loading = false }
        var base = [URLQueryItem]()
        if let childID { base.append(URLQueryItem(name: "child_id", value: childID)) }
        let reviewDay = min(weekEnd, .now)
        let courseQuery = base + [URLQueryItem(name: "start", value: BubuLearningDates.dayString(weekStart)),
                                  URLQueryItem(name: "end", value: BubuLearningDates.dayString(weekEnd))]
        let reviewQuery = base + [URLQueryItem(name: "period", value: "week"),
                                  URLQueryItem(name: "date", value: BubuLearningDates.dayString(reviewDay))]
        do {
            async let courseList = client.get("api/courses", query: courseQuery, as: LearningCourseList.self)
            async let attemptList = client.get("api/attempts", query: base, as: LearningAttemptRecordList.self)
            async let reviewList = client.get("api/reviews", query: reviewQuery, as: LearningReviewDTO.self)
            let (courses, attempts) = try await (courseList, attemptList)
            // 复习建议拿不到不影响周报其他部分。
            let review = (try? await reviewList)?.items ?? []
            guard requested == weekStart else { return }
            summary = LearningWeeklySummary.make(weekStart: weekStart, courses: courses.items,
                                                 attempts: attempts.items, review: review)
            errorText = nil
        } catch is CancellationError {
        } catch {
            if summary == nil { errorText = learningErrorText(error) }
        }
    }
}

/// 词语小胶囊，自动换行。
private struct LearningWordFlow: View {
    let words: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(words, id: \.self) { word in
                Text(word)
                    .font(BubuTheme.Font.body.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(BubuTheme.Color.mintSurface, in: Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("练过的词：" + words.joined(separator: "，"))
    }

    private struct FlowLayout: Layout {
        var spacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
            let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
            let width = rows.map(\.width).max() ?? 0
            return CGSize(width: proposal.width ?? width, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            var y = bounds.minY
            for row in arrange(width: bounds.width, subviews: subviews) {
                var x = bounds.minX
                for index in row.indices {
                    let size = subviews[index].sizeThatFits(.unspecified)
                    subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                    x += size.width + spacing
                }
                y += row.height + spacing
            }
        }

        private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

        private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
            var rows = [Row()]
            for index in subviews.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
                if needed > width, !rows[rows.count - 1].indices.isEmpty {
                    rows.append(Row())
                }
                var row = rows[rows.count - 1]
                row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
                row.height = max(row.height, size.height)
                row.indices.append(index)
                rows[rows.count - 1] = row
            }
            return rows.filter { !$0.indices.isEmpty }
        }
    }
}
