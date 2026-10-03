import SwiftUI
import SwiftData

// MARK: - 第一人称日记
/// 选一条记录 → AI 把父母视角改写成布布第一人称（打字机动效）→ 可保存回 Entry。
struct FirstPersonDiaryView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Entry> { !$0.isArchived },
           sort: \Entry.happenedAt, order: .reverse) private var entries: [Entry]

    @State private var selected: Entry?
    @State private var typeTask: Task<Void, Never>?
    @State private var rewriteState = DiaryRewriteState()
    @State private var generationTasks: [UUID: (id: UUID, task: Task<Void, Never>)] = [:]

    private var selectedDraft: DiaryRewriteState.Draft {
        selected.map { rewriteState.draft(for: $0.id) } ?? .init()
    }
    private var generating: Bool { selectedDraft.activeRequest != nil }
    private var output: String { selectedDraft.output }
    private var displayed: String { selectedDraft.displayed }
    private var errorText: String? { selectedDraft.error }

    #if DEBUG
    private var auditRewrite: (@MainActor (String, String) async throws -> String)?
    private var auditDidHandleReply: (@MainActor () -> Void)?

    init(auditRewrite: @escaping @MainActor (String, String) async throws -> String,
         auditDidHandleReply: (@MainActor () -> Void)? = nil) {
        self.auditRewrite = auditRewrite
        self.auditDidHandleReply = auditDidHandleReply
    }
    #endif

    init() {}

    private var rewriteAvailable: Bool {
        #if DEBUG
        if auditRewrite != nil { return true }
        #endif
        return env.config.isAIConfigured
    }

    private func requestRewrite(note: String, childName: String) async throws -> String {
        #if DEBUG
        if let auditRewrite { return try await auditRewrite(note, childName) }
        #endif
        return try await env.aiService.rewriteFirstPerson(note: note, childName: childName)
    }

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
        .alert("没有保存成功", isPresented: Binding(
            get: { selectedDraft.saveError != nil },
            set: { shown in if !shown, let selected { rewriteState.saveFailed(for: selected.id, message: nil) } })) {
                Button("好", role: .cancel) {}
            } message: { Text(selectedDraft.saveError ?? "") }
        .onDisappear {
            typeTask?.cancel()
            if let selected { rewriteState.finishPresentation(for: selected.id) }
            for entryID in Array(generationTasks.keys) { cancelRewrite(for: entryID) }
        }
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
            typeTask?.cancel()
            if let previous = selected { rewriteState.finishPresentation(for: previous.id) }
            withAnimation(reduceMotion ? nil : .default) { selected = entry }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                entryAvatar(entry, size: 42)
                VStack(alignment: .leading, spacing: 6) {
                    Text(BubuDateFormat.shortDate(entry.happenedAt))
                        .font(BubuTheme.Font.scaled(11)).foregroundStyle(BubuTheme.Color.secondaryText)
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
        .accessibilityIdentifier("diary.entry.\(entry.id.uuidString)")
        .accessibilityAddTraits(isSel ? .isSelected : [])
    }

    @ViewBuilder
    private func entryAvatar(_ entry: Entry, size: CGFloat) -> some View {
        if let media = entry.sortedMedia.first(where: { $0.type == .photo }) {
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
                startRewrite()
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
            .accessibilityIdentifier("diary.generate")

            if generating, let selected {
                Button("停止等待") { cancelRewrite(for: selected.id) }
                    .accessibilityIdentifier("diary.cancel")
            }

            if generating && displayed.isEmpty {
                thinkingBubble
            }

            if let errorText {
                HStack(alignment: .top, spacing: 10) {
                    BubuMascotBadge(size: 44, expression: .shy)
                    Text(errorText)
                        .accessibilityIdentifier("diary.error")
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
                .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        }
    }

    private func bubuMessage(entry: Entry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            entryAvatar(entry, size: 54)

            VStack(alignment: .leading, spacing: 8) {
                Text("布布说")
                    .font(BubuTheme.Font.scaled(12, weight: .semibold))
                    .foregroundStyle(theme)
                Text(displayed)
                    .accessibilityIdentifier("diary.output")
                    .font(BubuTheme.Font.scaled(18, weight: .regular))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineSpacing(6)

                if displayed == output && !output.isEmpty {
                    Button {
                        saveBack()
                    } label: {
                        Label(selectedDraft.saved ? "已保存到这条记录" : "保存到这条记录", systemImage: selectedDraft.saved ? "checkmark.circle" : "tray.and.arrow.down")
                            .font(BubuTheme.Font.caption.weight(.semibold))
                            .foregroundStyle(theme)
                            .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("diary.save")
                    .disabled(selectedDraft.saved)
                }
            }
            .padding(16)
            .background(theme.opacity(0.10), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
            .overlay(alignment: .leading) {
                DiaryBubbleTail()
                    .fill(theme.opacity(0.10))
                    .frame(width: 16, height: 22)
                    .offset(x: -9, y: -18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func startRewrite() {
        guard let entry = selected else { return }
        let entryID = entry.id
        let note = entry.note ?? ""
        // Admit synchronously. Two taps in the same render cannot issue two AI requests.
        guard let request = rewriteState.begin(for: entryID) else { return }
        typeTask?.cancel()
        guard rewriteAvailable else {
            rewriteState.fail("先在设置里连接家里的 AI 服务，再来写第一人称日记。", for: entryID, request: request)
            return
        }
        let task = Task { await generate(entryID: entryID, note: note, request: request) }
        generationTasks[entryID] = (request, task)
    }

    private func cancelRewrite(for entryID: UUID) {
        // Invalidate the token first; cancellation alone cannot stop every IO callback.
        rewriteState.cancel(for: entryID)
        generationTasks.removeValue(forKey: entryID)?.task.cancel()
    }

    private func generate(entryID: UUID, note: String, request: UUID) async {
        defer {
            if generationTasks[entryID]?.id == request { generationTasks[entryID] = nil }
            #if DEBUG
            auditDidHandleReply?()
            #endif
        }
        do {
            let text = try await requestRewrite(note: note, childName: env.config.childName)
            let immediate = reduceMotion || selected?.id != entryID
            guard rewriteState.succeed(text, for: entryID, request: request,
                                       revealImmediately: immediate) else { return }
            if !immediate { typewriter(text, entryID: entryID, presentation: request) }
        } catch {
            rewriteState.fail("AI 暂时没想好，稍后再试一次。", for: entryID, request: request)
        }
    }

    /// Each animation also carries its origin; a late tick cannot change another draft.
    private func typewriter(_ text: String, entryID: UUID, presentation: UUID) {
        typeTask?.cancel()
        typeTask = Task {
            for ch in text {
                guard !Task.isCancelled,
                      rewriteState.append(ch, for: entryID, presentation: presentation) else { return }
                try? await Task.sleep(for: .milliseconds(18))
            }
        }
    }

    private func saveBack() {
        guard let entry = selected else { return }
        let draft = rewriteState.draft(for: entry.id)
        guard !draft.saved, !draft.output.isEmpty, draft.displayed == draft.output else { return }
        do {
            let savedAt = try DiaryRewriteMutation.save(entryID: entry.id, text: draft.output,
                                                        container: context.container) { transaction in
                #if DEBUG
                try DiaryRewriteUITestFault.injectOnce(in: transaction.container)
                #endif
                try transaction.save()
            }
            entry.firstPersonNote = draft.output
            entry.editedAt = savedAt
            entry.syncState = .local
            rewriteState.saved(for: entry.id)
        } catch {
            rewriteState.saveFailed(for: entry.id, message: "改写内容还在这里，尚未保存到记录。请检查可用存储空间后重试。")
        }
    }
}

private nonisolated struct DiaryBubbleTail: Shape {
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
