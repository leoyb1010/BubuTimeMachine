import SwiftUI
import SwiftData

// MARK: - 问问布布（RAG 问答）
/// 三年记录变成能对话的记忆。检索在 App 端做（离线优先），把相关记录发给自托管 AI 组织答案带出处。
/// 「布布第一次叫妈妈是什么时候？」「她 6 个月多重？」「去年今天在干嘛？」
struct BubuQAView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt, order: .reverse)
    private var entries: [Entry]
    @Query private var profiles: [ChildProfile]
    @Query private var milestones: [Milestone]
    @Query(sort: \GrowthMeasurement.measuredAt) private var measurements: [GrowthMeasurement]

    @State private var input = ""
    @State private var messages: [QAMessage] = []
    @State private var thinking = false
    @State private var jumpEntry: Entry?

    private var childName: String { profiles.first?.name ?? env.config.childName }
    private let samples = ["第一次叫妈妈是什么时候？", "最近有什么新变化？", "去年今天在干嘛？", "最开心的一天是哪天？"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty { intro }
                        ForEach(messages) { msg in bubble(msg).id(msg.id) }
                        if thinking { thinkingBubble.id("thinking") }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
            }
            inputBar
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("问问\(childName)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $jumpEntry) { EntryDetailView(entry: $0) }
    }

    /// 出处可查证（H-5）：点出处芯片直接跳到那条时光（里程碑/测量出处暂不跳转）。
    private func jump(to sourceID: String) {
        guard let uuid = UUID(uuidString: sourceID),
              let entry = entries.first(where: { $0.id == uuid }) else { return }
        jumpEntry = entry
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("💬 关于\(childName)的成长，问我都行")
                .font(BubuTheme.Font.scaled(17, weight: .heavy))
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text("我会翻遍你记录的时光来回答，还会告诉你依据哪条记录。")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            FlowLayout(spacing: 8) {
                ForEach(samples, id: \.self) { s in
                    Button { ask(s) } label: {
                        Text(s)
                            .font(BubuTheme.Font.scaled(13, weight: .semibold))
                            .foregroundStyle(BubuTheme.Color.primary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(BubuTheme.Color.primary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }

    private func bubble(_ msg: QAMessage) -> some View {
        HStack {
            if msg.isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                Text(msg.text)
                    .font(BubuTheme.Font.scaled(15, weight: .medium))
                    .foregroundStyle(msg.isUser ? .white : BubuTheme.Color.warmBrown)
                if !msg.sources.isEmpty {
                    ForEach(msg.sources) { src in
                        Button { jump(to: src.id) } label: {
                            Label(src.dateText + " · " + src.snippet, systemImage: "text.quote")
                                .font(BubuTheme.Font.scaled(11, weight: .medium))
                                .foregroundStyle(msg.isUser ? .white.opacity(0.85) : BubuTheme.Color.secondaryText)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(msg.isUser ? BubuTheme.Color.primary : BubuTheme.Color.card,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !msg.isUser { Spacer(minLength: 40) }
        }
    }

    private var thinkingBubble: some View {
        HStack {
            ProgressView().tint(BubuTheme.Color.primary)
            Text("正在翻\(childName)的时光…")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("问问关于\(childName)的…", text: $input, axis: .vertical)
                .font(BubuTheme.Font.body)
                .padding(10)
                .background(BubuTheme.Color.softFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Button {
                ask(input)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(BubuTheme.Font.scaled(30))
                    .foregroundStyle(canSend ? BubuTheme.Color.primary : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespaces).isEmpty && !thinking
    }

    // MARK: 问答逻辑
    private func ask(_ raw: String) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !thinking else { return }
        input = ""
        messages.append(QAMessage(isUser: true, text: question, sources: []))
        thinking = true
        let retrieved = retrieve(for: question)
        Task {
            do {
                let ans = try await env.aiService.ask(question: question, childName: childName,
                                                      records: retrieved.map(\.context))
                let usedSet = Set(ans.usedIDs)
                let cited = retrieved.filter { usedSet.contains($0.context.id) }.prefix(3)
                let sources = (cited.isEmpty ? retrieved.prefix(2) : cited).map {
                    QASource(id: $0.context.id, dateText: $0.context.dateText, snippet: $0.snippet)
                }
                await MainActor.run {
                    thinking = false
                    messages.append(QAMessage(isUser: false, text: ans.answer, sources: Array(sources)))
                }
            } catch {
                await MainActor.run {
                    thinking = false
                    messages.append(QAMessage(isUser: false,
                                              text: "现在连不上 AI 服务，等会儿再问我吧。（可在设置里配置自托管 AI）",
                                              sources: []))
                }
            }
        }
    }

    /// 本地检索（跨数据域 + 日期意图感知，R4 P2-27）：
    /// ① 「去年今天/前年今天/生日」等先转成时间窗直接取该窗记录；
    /// ② 关键词（含 2-gram，过滤疑问停用词）命中时光、里程碑、成长测量；
    /// ③ 命中不足补最近时光。最多 12 条给 AI。
    private func retrieve(for question: String) -> [(context: QAContextRecord, snippet: String)] {
        let birthday = profiles.first?.birthday
        func dateText(_ d: Date) -> String { BubuDateFormat.yearMonthDay(d) }
        func ageText(_ d: Date) -> String {
            birthday.map { AgeCalculator.ageDescription(birthday: $0, at: d) } ?? ""
        }

        // 统一候选池：时光 + 已点亮里程碑 + 成长测量（都能被问到）
        struct Candidate { let id: String; let date: Date; let text: String }
        var pool: [Candidate] = entries.map { e in
            var parts = [e.note, e.title, e.firstPersonNote].compactMap { $0 }
            parts += e.voiceNotes.compactMap(\.transcript)   // 语音转写也可被问到（R4 E-1）
            return Candidate(id: e.id.uuidString, date: e.happenedAt,
                             text: parts.joined(separator: " "))
        }
        pool += milestones.compactMap { m in
            guard let d = m.happenedAt else { return nil }
            return Candidate(id: m.id.uuidString, date: d,
                             text: "里程碑：\(m.title) \(m.detail ?? "")")
        }
        pool += measurements.map { m in
            let parts = [m.heightCm.map { "身高\($0)cm" }, m.weightKg.map { "体重\($0)kg" },
                         m.headCircumferenceCm.map { "头围\($0)cm" }].compactMap { $0 }
            return Candidate(id: m.id.uuidString, date: m.measuredAt,
                             text: "成长测量：" + parts.joined(separator: " "))
        }

        var picked: [Candidate] = []

        // ① 日期意图：去年今天 / 前年今天 / 生日
        if let windows = Self.dateWindows(for: question, birthday: birthday) {
            picked = pool.filter { c in windows.contains { $0.contains(c.date) } }
                .sorted { $0.date > $1.date }
        }

        // ② 关键词打分
        if picked.count < 6 {
            let keys = Self.keywords(from: question)
            let scored = pool
                .map { c in (c, keys.reduce(0) { $0 + (c.text.lowercased().contains($1) ? 1 : 0) }) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
            for c in scored where !picked.contains(where: { $0.id == c.id }) { picked.append(c) }
        }

        // ③ 补最近时光
        if picked.count < 6 {
            for e in entries.prefix(8) {
                let id = e.id.uuidString
                if !picked.contains(where: { $0.id == id }) {
                    picked.append(Candidate(id: id, date: e.happenedAt,
                                            text: e.note ?? e.title ?? "一个瞬间"))
                }
            }
        }

        return picked.prefix(12).map { c in
            let text = c.text.isEmpty ? "一个瞬间" : c.text
            let ctx = QAContextRecord(id: c.id, dateText: dateText(c.date),
                                      ageText: ageText(c.date), text: String(text.prefix(200)))
            return (ctx, String(text.prefix(20)))
        }
    }

    /// 问题里的日期意图 → 时间窗（±3 天）。生日会展开为每一年的生日窗。
    private static func dateWindows(for question: String, birthday: Date?) -> [ClosedRange<Date>]? {
        let cal = Calendar.current
        func window(around day: Date) -> ClosedRange<Date> {
            let start = cal.date(byAdding: .day, value: -3, to: cal.startOfDay(for: day)) ?? day
            let end = cal.date(byAdding: .day, value: 4, to: cal.startOfDay(for: day)) ?? day
            return start...end
        }
        if question.contains("去年今天") || question.contains("去年的今天") {
            if let d = cal.date(byAdding: .year, value: -1, to: .now) { return [window(around: d)] }
        }
        if question.contains("前年今天") || question.contains("前年的今天") {
            if let d = cal.date(byAdding: .year, value: -2, to: .now) { return [window(around: d)] }
        }
        if question.contains("生日"), let birthday {
            // 出生那天起，每年生日一个窗
            var windows: [ClosedRange<Date>] = []
            let thisYear = cal.component(.year, from: .now)
            let birthYear = cal.component(.year, from: birthday)
            for year in birthYear...thisYear {
                var comps = cal.dateComponents([.month, .day], from: birthday)
                comps.year = year
                if let d = cal.date(from: comps) { windows.append(window(around: d)) }
            }
            return windows.isEmpty ? nil : windows
        }
        return nil
    }

    /// 问题 → 关键词：ASCII 词整取，中文取 2-gram（廉价而有效的中文召回，避免整句变一个 token）。
    private static func keywords(from question: String) -> [String] {
        var words: [String] = []
        var cjk: [Character] = []
        var current = ""
        for ch in question {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                current.append(Character(ch.lowercased()))
            } else {
                if !current.isEmpty { words.append(current); current = "" }
                if ch.isLetter { cjk.append(ch) }   // 中日韩表意字
            }
        }
        if !current.isEmpty { words.append(current) }
        var grams: [String] = []
        if cjk.count == 1 {
            grams.append(String(cjk[0]))
        } else if cjk.count >= 2 {
            for i in 0..<(cjk.count - 1) { grams.append(String([cjk[i], cjk[i + 1]])) }
        }
        // 疑问停用词不参与打分：否则「什么时候」会命中一堆无关记录
        let stopGrams: Set<String> = ["什么", "时候", "么时", "怎么", "哪天", "干嘛", "多少",
                                      "是不", "不是", "有没", "没有", "去年", "前年", "今天",
                                      "年今", "的今", "在干", "呢", "吗", "啊"]
        return Array(Set(words + grams.filter { !stopGrams.contains($0) }))
    }
}

private struct QAMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
    let sources: [QASource]
}

private struct QASource: Identifiable {
    let id: String
    let dateText: String
    let snippet: String
}
