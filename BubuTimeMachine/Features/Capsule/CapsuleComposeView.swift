import SwiftUI
import SwiftData

// MARK: - 时间胶囊 · 写信
/// 写文字 + 录语音 + 选解锁时间（提供「18岁生日」「明年今天」等快捷项）。
/// 保存时加密落盘，UI 立刻锁定。
struct CapsuleComposeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [ChildProfile]
    let editing: TimeCapsule?

    @State private var title = ""
    @State private var emoji = "💌"
    @State private var letter = ""
    @State private var unlockAt = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var pendingVoice: (fileName: String, duration: Double, waveform: [Float])?
    @State private var saving = false
    @State private var errorText: String?

    private var theme: Color { env.theme.theme.primary }
    private var profile: ChildProfile? { profiles.first }
    private let emojiChoices = ["💌","🎁","🌟","🎂","🧸","🌷","📮","🕰️","💝","🍼"]

    init(editing: TimeCapsule? = nil) {
        self.editing = editing
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                        emojiPicker
                        titleField
                        letterField
                        voiceSection
                        unlockSection
                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
            .navigationTitle(editing == nil ? "写给未来的布布" : "修改时间胶囊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView() }
                        else { Text("封存").font(BubuTheme.Font.headline.weight(.bold)) }
                    }
                    .disabled(!canSave || saving)
                }
            }
            .alert("封存失败", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("好") { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
            .onAppear(perform: loadEditing)
        }
    }

    @ViewBuilder
    private var background: some View {
        BubuThemedBackground()
    }

    private var emojiPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(emojiChoices, id: \.self) { e in
                    Text(e).font(.system(size: 30))
                        .frame(width: 50, height: 50)
                        .background(emoji == e ? theme.opacity(0.18) : BubuTheme.Color.softFill, in: Circle())
                        .overlay { Circle().stroke(emoji == e ? theme : .clear, lineWidth: 2) }
                        .onTapGesture { emoji = e }
                }
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("给这封信起个名字").font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
            TextField("如：写给18岁的你", text: $title)
                .font(BubuTheme.Font.headline)
                .padding()
                .background(BubuTheme.Color.card.opacity(0.70), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
                .bubuGlassSurface(cornerRadius: BubuTheme.Radius.small, tint: theme, interactive: true)
        }
    }

    private var letterField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("想对她说的话").font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
            TextField("亲爱的布布……", text: $letter, axis: .vertical)
                .font(BubuTheme.Font.body)
                .lineLimit(6...14)
                .padding()
                .background(BubuTheme.Color.card.opacity(0.70), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
                .bubuGlassSurface(cornerRadius: BubuTheme.Radius.small, tint: theme, interactive: true)
        }
    }

    @ViewBuilder
    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("也可以录一段话（可不录）").font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
            if let v = pendingVoice {
                HStack {
                    VoicePlayerBubble(fileName: v.fileName, duration: v.duration,
                                      waveform: v.waveform, mediaStore: env.mediaStore, tint: theme)
                    Button { pendingVoice = nil } label: {
                        Image(systemName: "trash.circle.fill").font(.system(size: 26))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }.buttonStyle(.plain)
                }
            } else {
                VoiceRecorderBar(mediaStore: env.mediaStore) { fileName, duration, waveform in
                    pendingVoice = (fileName, duration, waveform)
                }
            }
        }
    }

    private var unlockSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("什么时候可以打开").font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(quickOptions, id: \.0) { label, date in
                        Button {
                            withAnimation(.snappy) { unlockAt = date }
                        } label: {
                            Text(label)
                                .font(BubuTheme.Font.caption.weight(.medium))
                                .foregroundStyle(isSelected(date) ? .white : BubuTheme.Color.warmBrown)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(isSelected(date) ? theme : BubuTheme.Color.softFill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            DatePicker("精确到天", selection: $unlockAt, in: Date.now..., displayedComponents: .date)
                .disabled(editing != nil && !canRewritePayload)
                .padding()
                .background(BubuTheme.Color.card.opacity(0.70), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
                .bubuGlassSurface(cornerRadius: BubuTheme.Radius.small, tint: theme, interactive: true)
            Text(editing != nil && !canRewritePayload ? "未到期的胶囊只能改标题和封面；内容与解锁日保持封存。" : "封存后，到 \(BubuDateFormat.longDate(unlockAt)) 之前都打不开。")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(theme)
        }
    }

    private var quickOptions: [(String, Date)] {
        let cal = Calendar.current
        var opts: [(String, Date)] = []
        if let next = cal.date(byAdding: .year, value: 1, to: .now) { opts.append(("明年今天", next)) }
        if let profile {
            for age in [6, 12, 18] {
                if let d = cal.date(byAdding: .year, value: age, to: profile.birthday), d > .now {
                    opts.append(("\(age)岁生日", d))
                }
            }
        }
        return opts
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: unlockAt)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        (editing != nil || !letter.trimmingCharacters(in: .whitespaces).isEmpty || pendingVoice != nil)
    }

    private var canRewritePayload: Bool {
        editing == nil || (editing?.unlockAt ?? .now) <= .now
    }

    private func loadEditing() {
        guard let editing, title.isEmpty else { return }
        title = editing.title
        emoji = editing.coverEmoji ?? "💌"
        unlockAt = max(editing.unlockAt, .now)
        if let blob = editing.encryptedBlobFileName,
           editing.unlockAt <= .now,
           let payload = try? env.vault.unseal(fileName: blob, unlockAt: editing.unlockAt,
                                               salt: editing.id.uuidString,
                                               recoveryCode: CapsuleRecovery.current()) {
            letter = payload.letter
            if let voice = payload.voiceFileName {
                pendingVoice = (voice, payload.voiceDuration, payload.voiceWaveform)
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }

        // 规整到整秒：密钥派生与服务器存储格式一致，同步往返不会破坏解密。
        let sealedUnlockAt = CapsuleCrypto.normalized(unlockAt)
        let capsule = editing ?? TimeCapsule(title: title, fromRole: env.config.currentRole.rawValue, unlockAt: sealedUnlockAt)
        capsule.title = title
        capsule.coverEmoji = emoji

        if editing != nil, !canRewritePayload {
            capsule.syncState = .local
            try? context.save()
            env.syncEngine.syncNow()
            dismiss()
            return
        }

        capsule.unlockAt = sealedUnlockAt

        let payload = CapsulePayload(
            letter: letter,
            voiceFileName: pendingVoice?.fileName,
            voiceDuration: pendingVoice?.duration ?? 0,
            voiceWaveform: pendingVoice?.waveform ?? []
        )
        do {
            // v3 真 E2E：用家庭恢复码派生密钥加密，密钥不随记录同步。
            let recoveryCode = CapsuleRecovery.currentOrCreate()
            let blobName = try env.vault.sealV3(payload, recoveryCode: recoveryCode, salt: capsule.id.uuidString)
            capsule.encryptedBlobFileName = blobName
            capsule.isLocked = true
            capsule.syncState = .local
            if editing == nil { context.insert(capsule) }
            try context.save()
            // 封存要有「盖章」的确定感
            BubuHaptics.stamp()
            env.syncEngine.syncNow()
            dismiss()
        } catch {
            errorText = "这封信还没有封存成功：\(error.localizedDescription)。录好的语音仍保留在手机里，可以稍后再试。"
        }
    }
}
