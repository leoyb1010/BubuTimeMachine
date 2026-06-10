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
    @State private var errorText: String?

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
        .toolbar { ToolbarItem(placement: .topBarLeading) { Text("← 右滑返回").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText) } }
    }

    @ViewBuilder
    private var background: some View {
        BubuThemedBackground()
    }

    private var intro: some View {
        HStack(spacing: 12) {
            BubuMascotBadge(size: 54, expression: .love)
            VStack(alignment: .leading, spacing: 5) {
                Text("让布布亲口讲这一刻")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("选一条你写的记录，布布会像聊天一样，把它变成自己的小日记。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
        .padding()
        .background(BubuTheme.Color.card.opacity(0.84), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
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
            withAnimation { selected = entry; output = ""; displayed = ""; errorText = nil }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                entryAvatar(entry, size: 42)
                VStack(alignment: .leading, spacing: 6) {
                    Text(BubuDateFormat.shortDate(entry.happenedAt))
                        .font(.system(size: 11)).foregroundStyle(BubuTheme.Color.secondaryText)
                    Text(entry.note ?? "")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .lineLimit(3)
                }
            }
            .frame(width: 190, height: 96, alignment: .topLeading)
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
    private func entryAvatar(_ entry: Entry, size: CGFloat) -> some View {
        if let media = entry.media.first(where: { $0.type == .photo }) {
            MediaThumbnail(media: media, mediaStore: env.mediaStore, cornerRadius: size / 2)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay { Circle().stroke(.white, lineWidth: 2) }
        } else {
            BubuMascotBadge(size: size, mood: entry.mood)
        }
    }

    @ViewBuilder
    private var generateArea: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                Task { await generate() }
            } label: {
                HStack {
                    if generating { ProgressView().tint(.white) }
                    else { Image(systemName: "wand.and.stars") }
                    Text(generating ? "布布正在想……" : "让布布说出来")
                }
                .font(BubuTheme.Font.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(theme, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(generating)

            if generating && displayed.isEmpty {
                thinkingBubble
            }

            if let errorText {
                HStack(alignment: .top, spacing: 10) {
                    BubuMascotBadge(size: 44, expression: .shy)
                    Text(errorText)
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
            }

            if !displayed.isEmpty, let selected {
                bubuMessage(entry: selected)
            }
        }
    }

    private var thinkingBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            BubuMascotBadge(size: 52, expression: .thinking)
                .bubuFloating()
            Text("我在想，怎么把这一天讲给未来的自己听……")
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .padding()
                .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func bubuMessage(entry: Entry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            entryAvatar(entry, size: 54)

            VStack(alignment: .leading, spacing: 8) {
                Text("布布说")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme)
                Text(displayed)
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineSpacing(6)

                if displayed == output && !output.isEmpty {
                    Button {
                        saveBack()
                    } label: {
                        Label("保存到这条记录", systemImage: "tray.and.arrow.down")
                            .font(BubuTheme.Font.caption.weight(.semibold))
                            .foregroundStyle(theme)
                            .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(theme.opacity(0.10), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .leading) {
                DiaryBubbleTail()
                    .fill(theme.opacity(0.10))
                    .frame(width: 16, height: 22)
                    .offset(x: -9, y: -18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func generate() async {
        guard let entry = selected else { return }
        generating = true
        displayed = ""
        errorText = nil
        defer { generating = false }
        let note = entry.note ?? ""
        if let sparse = sparseRewrite(for: note) {
            output = sparse
            await typewriter(sparse)
            return
        }
        do {
            let text = try await env.aiService.rewriteFirstPerson(
                note: note, childName: env.config.childName)
            output = text
            await typewriter(text)
        } catch {
            output = ""
            errorText = "AI 暂时没想好，稍后再试一次。"
        }
    }

    private func sparseRewrite(for note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let compact = trimmed.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let laughingScalars = CharacterSet(charactersIn: "哈呵嘿嘻hHaAlLoO~～!！.。")
        let isMostlyLaughing = compact.unicodeScalars.allSatisfy { laughingScalars.contains($0) }
        if compact.count <= 8 || isMostlyLaughing {
            return "这一刻小小的、软软的，我把它收进心里，留给长大的自己慢慢看。"
        }
        return nil
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
        selected?.editedAt = .now
        selected?.syncState = .local
        try? context.save()
    }
}

private struct DiaryBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                          control: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.16))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                          control: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.maxY - rect.height * 0.16))
        path.closeSubpath()
        return path
    }
}
