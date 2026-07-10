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

    @State private var input = ""
    @State private var messages: [QAMessage] = []
    @State private var thinking = false

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
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("💬 关于\(childName)的成长，问我都行")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text("我会翻遍你记录的时光来回答，还会告诉你依据哪条记录。")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            FlowLayout(spacing: 8) {
                ForEach(samples, id: \.self) { s in
                    Button { ask(s) } label: {
                        Text(s)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(msg.isUser ? .white : BubuTheme.Color.warmBrown)
                if !msg.sources.isEmpty {
                    ForEach(msg.sources) { src in
                        Label(src.dateText + " · " + src.snippet, systemImage: "text.quote")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(msg.isUser ? .white.opacity(0.85) : BubuTheme.Color.secondaryText)
                            .lineLimit(1)
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
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
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

    /// 本地检索：按问题关键词命中 note/title，命中不足则补最近记录。最多 12 条给 AI。
    private func retrieve(for question: String) -> [(context: QAContextRecord, snippet: String)] {
        let birthday = profiles.first?.birthday
        let keys = Self.keywords(from: question)
        func score(_ e: Entry) -> Int {
            let hay = ((e.note ?? "") + (e.title ?? "") + (e.firstPersonNote ?? "")).lowercased()
            return keys.reduce(0) { $0 + (hay.contains($1) ? 1 : 0) }
        }
        let scored = entries.map { ($0, score($0)) }
        var picked = scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map { $0.0 }
        if picked.count < 6 {   // 命中不够，补最近的
            let recent = entries.prefix(8).filter { e in !picked.contains { $0.id == e.id } }
            picked.append(contentsOf: recent)
        }
        return picked.prefix(12).map { e in
            let text = (e.note?.isEmpty == false ? e.note! : (e.title ?? "一个瞬间"))
            let dateText = BubuDateFormat.yearMonthDay(e.happenedAt)
            let age = birthday.map { AgeCalculator.ageDescription(birthday: $0, at: e.happenedAt) } ?? ""
            let ctx = QAContextRecord(id: e.id.uuidString, dateText: dateText, ageText: age, text: text)
            return (ctx, String(text.prefix(20)))
        }
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
        return Array(Set(words + grams))
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
