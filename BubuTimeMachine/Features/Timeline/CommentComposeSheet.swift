import SwiftUI
import SwiftData

// MARK: - 家人合奏补充
/// 以当前身份对某条记录补充文字 + 可选语音，多视角合成完整故事。
struct CommentComposeSheet: View {
    let entry: Entry
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var voice: (fileName: String, duration: Double, waveform: [Float])?
    @State private var draftID = UUID()
    @State private var saveError: String?
    @State private var completed = false

    private var theme: Color { env.theme.theme.primary }
    private var role: String { env.config.currentRole.rawValue }

    var body: some View {
        NavigationStack {
            ZStack {
                BubuTheme.Color.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                        HStack(spacing: 10) {
                            Text(env.config.currentRole.rawValue)
                                .font(BubuTheme.Font.headline).foregroundStyle(theme)
                            Text("从你的视角说说这一刻")
                                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        }

                        TextField("这一刻，我记得……", text: $text, axis: .vertical)
                            .font(BubuTheme.Font.body)
                            .lineLimit(4...10)
                            .padding()
                            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))

                        if let v = voice {
                            HStack {
                                VoicePlayerBubble(fileName: v.fileName, duration: v.duration,
                                                  waveform: v.waveform, mediaStore: env.mediaStore, tint: theme)
                                Button { voice = nil } label: {
                                    Image(systemName: "trash.circle.fill").font(BubuTheme.Font.scaled(26))
                                        .foregroundStyle(BubuTheme.Color.secondaryText)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("删除这段语音")
                            }
                        } else {
                            VoiceRecorderBar(mediaStore: env.mediaStore) { fileName, duration, waveform in
                                voice = (fileName, duration, waveform)
                            }
                        }
                        Spacer(minLength: 10)
                    }
                    .padding()
                }
            }
            .navigationTitle("家人合奏")
            .navigationBarTitleDisplayMode(.inline)
            .alert("还没有添加成功", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("好") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { save() }.fontWeight(.bold)
                        .disabled(completed || (text.bubuTrimmed.isEmpty && voice == nil))
                }
            }
        }
    }

    private func save() {
        guard !completed else { return }
        let draft = CommentPersistence.Draft(id: draftID, parentID: entry.id, role: role, text: text, voice: voice)
        do {
            try CommentPersistence.save(draft, in: context) { _ in
                completed = true
                env.syncEngine.syncNow()
                dismiss()
            }
        } catch {
            saveError = "这段补充还没有保存：\(error.localizedDescription)。文字和录音仍留在这里，请稍后再试。"
        }
    }
}

@MainActor
enum CommentPersistence {
    struct Draft {
        let id: UUID
        let parentID: UUID
        let role: String
        let text: String
        var voice: (fileName: String, duration: Double, waveform: [Float])? = nil
    }
    enum SaveError: LocalizedError {
        case missingParent, changedDraft, emptyContent
        var errorDescription: String? {
            switch self {
            case .missingParent: "原记录还未保存或已被移除，请返回确认后再添加。"
            case .changedDraft: "这段补充的保存状态已变化，请重新打开后确认。"
            case .emptyContent: "请先写一点文字或录一段语音。"
            }
        }
    }

    static func save(_ draft: Draft, in uiContext: ModelContext,
                     persist: (ModelContext) throws -> Void = { try $0.save() },
                     didCommit: (ModelContext) -> Void = { _ in }) throws {
        let text = draft.text.bubuTrimmed
        guard !text.isEmpty || draft.voice != nil else { throw SaveError.emptyContent }
        let parentID = draft.parentID
        // An unsaved archive/delete in the caller is also an explicit removal intent.
        guard !uiContext.deletedModelsArray.contains(where: { ($0 as? Entry)?.id == parentID }),
              let visibleParent = try uiContext.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == parentID })).first,
              !visibleParent.isArchived else {
            throw SaveError.missingParent
        }
        let context = ModelContext(uiContext.container)
        context.autosaveEnabled = false
        do {
            // Fetch the durable parent in this transaction, never attach a shared or
            // uncommitted UI model to a comment in another context.
            guard let entry = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == parentID })).first,
                  !entry.isArchived else { throw SaveError.missingParent }
            let id = draft.id
            if let existing = try context.fetch(FetchDescriptor<Comment>(predicate: #Predicate { $0.id == id })).first {
                guard existing.entry?.id == parentID, existing.authorRole == draft.role,
                      existing.text == (text.isEmpty ? nil : text), existing.voiceFileName == draft.voice?.fileName,
                      existing.voiceDuration == (draft.voice?.duration ?? 0),
                      existing.voiceWaveform == (draft.voice?.waveform ?? []) else { throw SaveError.changedDraft }
                didCommit(context)
                return
            }
            let comment = Comment(authorRole: draft.role, text: text.isEmpty ? nil : text)
            comment.id = draft.id
            if let v = draft.voice {
                comment.voiceFileName = v.fileName
                comment.voiceDuration = v.duration
                comment.voiceWaveform = v.waveform
            }
            comment.entry = entry
            entry.editedAt = .now
            entry.syncState = .local
            context.insert(comment)
            context.insert(FeedEvent(kind: .commentAdded, actorRole: draft.role,
                summary: text.isEmpty ? "补充了一段语音" : "补充：\(text)", targetLocalId: entry.id.uuidString))
            try persist(context)
            didCommit(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}
