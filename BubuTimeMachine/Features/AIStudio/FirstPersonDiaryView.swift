import SwiftUI
import SwiftData

// MARK: - 第一人称日记
/// 选一条记录 → AI 把父母视角改写成布布第一人称（打字机动效）→ 可保存回 Entry。
struct FirstPersonDiaryView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Entry> { !$0.isArchived },
           sort: \Entry.happenedAt, order: .reverse) private var entries: [Entry]

    @State private var selected: Entry?
    @State private var generating = false
    @State private var output = ""
    @State private var displayed = ""

    private var theme: Color { env.theme.theme.primary }
    private var candidates: [Entry] { entries.filter { ($0.note?.isEmpty == false) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro
                entryPicker
                if selected != nil { generateArea }
            }
            .padding()
        }
        .background(background.ignoresSafeArea())
        .navigationTitle("第一人称日记")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var background: some View {
        switch env.theme.theme.backgroundStyle {
        case .solid(let hex): Color(hex: hex)
        case .gradient(let a, let b):
            LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var intro: some View {
        Text("选一条你写的记录，让布布用自己的口吻，重新讲一遍这一刻。")
            .font(BubuTheme.Font.body)
            .foregroundStyle(BubuTheme.Color.secondaryText)
    }

    @ViewBuilder
    private var entryPicker: some View {
        if candidates.isEmpty {
            ContentUnavailableView("还没有可改写的记录",
                                   systemImage: "text.book.closed",
                                   description: Text("先在「记录此刻」写下一句父母视角的话吧。"))
                .frame(height: 240)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("选择一条记录").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(candidates.prefix(12)) { entry in
                            entryChip(entry)
                        }
                    }
                }
            }
        }
    }

    private func entryChip(_ entry: Entry) -> some View {
        let isSel = selected?.id == entry.id
        return Button {
            withAnimation { selected = entry; output = ""; displayed = "" }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.happenedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11)).foregroundStyle(BubuTheme.Color.secondaryText)
                Text(entry.note ?? "")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineLimit(3)
            }
            .frame(width: 150, height: 90, alignment: .topLeading)
            .padding(10)
            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous)
                    .stroke(isSel ? theme : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var generateArea: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                Task { await generate() }
            } label: {
                HStack {
                    if generating { ProgressView().tint(.white) }
                    else { Image(systemName: "wand.and.stars") }
                    Text(generating ? "布布正在想……" : "改写成布布的话")
                }
                .font(BubuTheme.Font.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(theme, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(generating)

            if !displayed.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(displayed)
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .lineSpacing(7)
                    if displayed == output && !output.isEmpty {
                        Button {
                            saveBack()
                        } label: {
                            Label("保存到这条记录", systemImage: "tray.and.arrow.down")
                                .font(BubuTheme.Font.body.weight(.medium))
                                .foregroundStyle(theme)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(theme.opacity(0.07), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            }
        }
    }

    private func generate() async {
        guard let entry = selected else { return }
        generating = true
        displayed = ""
        defer { generating = false }
        let text = (try? await env.aiService.rewriteFirstPerson(
            note: entry.note ?? "", childName: env.config.childName)) ?? ""
        output = text
        await typewriter(text)
    }

    /// 打字机动效逐字显示。
    private func typewriter(_ text: String) async {
        displayed = ""
        for ch in text {
            displayed.append(ch)
            try? await Task.sleep(for: .milliseconds(28))
        }
    }

    private func saveBack() {
        selected?.firstPersonNote = output
        try? context.save()
    }
}
