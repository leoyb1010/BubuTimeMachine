import SwiftUI
import SwiftData

// MARK: - 家人合奏
/// 找出有多位家人补充（Comment）的记录，把多视角"合成"成一段完整的故事。
struct FamilyEnsembleView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Entry> { !$0.isArchived },
           sort: \Entry.happenedAt, order: .reverse) private var entries: [Entry]

    @State private var selected: Entry?
    @State private var generating = false
    @State private var story = ""
    @State private var displayed = ""

    private var theme: Color { env.theme.theme.primary }
    /// 至少有两个视角（原记录作者 + 补充）才值得合奏。
    private var candidates: [Entry] {
        entries.filter { !$0.comments.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("当爸爸、妈妈、姥姥都为同一刻留下只言片语，AI 把它们编织成一个完整的故事。")
                    .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)

                if candidates.isEmpty {
                    ContentUnavailableView("还没有合奏素材",
                        systemImage: "person.3",
                        description: Text("在某条记录的详情页里，让家人各自「补充」几句，就能在这里合成。"))
                        .frame(height: 260)
                } else {
                    picker
                    if let entry = selected { ensembleArea(entry) }
                }
            }
            .padding()
        }
        .background(background.ignoresSafeArea())
        .navigationTitle("家人合奏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Text("← 右滑返回").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText) } }
    }

    @ViewBuilder
    private var background: some View {
        BubuThemedBackground()
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选一个有家人补充的瞬间").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            ForEach(candidates.prefix(8)) { entry in
                Button {
                    withAnimation { selected = entry; story = ""; displayed = "" }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(BubuDateFormat.shortDate(entry.happenedAt))
                                .font(.system(size: 11)).foregroundStyle(BubuTheme.Color.secondaryText)
                            Text(entry.note ?? "（无文字）").font(BubuTheme.Font.body)
                                .foregroundStyle(BubuTheme.Color.warmBrown).lineLimit(1)
                        }
                        Spacer()
                        Text("\(entry.comments.count + 1) 个视角")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme)
                    }
                    .padding()
                    .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous)
                            .stroke(selected?.id == entry.id ? theme : .clear, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func ensembleArea(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // 多视角原料
            VStack(alignment: .leading, spacing: 8) {
                voiceLine(role: entry.authorRole, text: entry.note ?? "（记录了这一刻）")
                ForEach(entry.comments.sorted { $0.createdAt < $1.createdAt }) { c in
                    voiceLine(role: c.authorRole, text: c.text ?? "（一段语音）")
                }
            }

            Button {
                Task { await synthesize(entry) }
            } label: {
                HStack {
                    if generating { ProgressView().tint(.white) } else { Image(systemName: "wand.and.stars") }
                    Text(generating ? "正在合奏……" : "合成完整的故事")
                }
                .font(BubuTheme.Font.headline.weight(.bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(theme, in: Capsule())
            }
            .buttonStyle(.plain).disabled(generating)

            if !displayed.isEmpty {
                Text(displayed)
                    .font(.system(size: 18, design: .serif))
                    .foregroundStyle(BubuTheme.Color.warmBrown).lineSpacing(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(theme.opacity(0.07), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            }
        }
    }

    private func voiceLine(role: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(role).font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(theme)
                .frame(width: 44, alignment: .leading)
            Text(text).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.warmBrown)
            Spacer()
        }
    }

    private func synthesize(_ entry: Entry) async {
        generating = true
        displayed = ""
        defer { generating = false }
        // Mock 合成：把多视角拼成一段温暖叙述
        try? await Task.sleep(for: .seconds(1))
        let perspectives = [entry.authorRole + "说：" + (entry.note ?? "记录了这一刻")]
            + entry.comments.compactMap { c in c.text.map { "\(c.authorRole)说：\($0)" } }
        story = """
        那是 \(BubuDateFormat.longDate(entry.happenedAt))。
        \(perspectives.joined(separator: "；"))。
        同一个瞬间，在每个人心里留下了不一样的温柔。这就是属于布布的、被全家人一起记住的一天。
        """
        await typewriter(story)
    }

    private func typewriter(_ text: String) async {
        for ch in text { displayed.append(ch); try? await Task.sleep(for: .milliseconds(22)) }
    }
}
