import SwiftUI
import SwiftData

// MARK: - 成长之声（声纹长卷）
/// 按"岁"归档布布的声音 + 家人对她说的话。未来可对比她各年龄的声音——最难复制的情感资产。
/// 录制时按布布生日自动算 ageYears 归档；可选转写（调 AIService.transcribe）。
struct VoiceArchiveView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query(sort: \VoiceMemo.recordedAt, order: .reverse) private var memos: [VoiceMemo]
    @Query private var profiles: [ChildProfile]

    @State private var showRecorder = false
    @State private var recordKind: VoiceMemo.Kind = .childVoice

    private var theme: Color { env.theme.theme.primary }
    private var profile: ChildProfile? { profiles.first }

    /// 按岁分组（降序）。
    private var grouped: [(age: Int, memos: [VoiceMemo])] {
        let dict = Dictionary(grouping: memos) { $0.ageYears ?? 0 }
        return dict.map { (age: $0.key, memos: $0.value) }.sorted { $0.age > $1.age }
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            if memos.isEmpty { emptyState }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                        intro
                        ForEach(grouped, id: \.age) { group in
                            yearSection(group.age, group.memos)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("成长之声")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { recordKind = .childVoice; showRecorder = true } label: {
                        Label("录布布的声音", systemImage: "person.wave.2")
                    }
                    Button { recordKind = .familyVoice; showRecorder = true } label: {
                        Label("家人对她说", systemImage: "heart.text.square")
                    }
                } label: { Image(systemName: "mic.badge.plus") }
            }
        }
        .sheet(isPresented: $showRecorder) {
            VoiceMemoRecorderSheet(kind: recordKind)
        }
    }

    @ViewBuilder
    private var background: some View {
        BubuThemedBackground()
    }

    private var intro: some View {
        Text("把布布的咿呀、第一声「妈妈」、家人想对她说的话，按一岁一岁收好。多年以后，听得见时间。")
            .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
    }

    private func yearSection(_ age: Int, _ items: [VoiceMemo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(age == 0 ? "0 岁" : "\(age) 岁")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(theme)
                Rectangle().fill(theme.opacity(0.2)).frame(height: 1)
            }
            ForEach(items) { memo in memoRow(memo) }
        }
    }

    private func memoRow(_ memo: VoiceMemo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: memo.kind == .childVoice ? "person.wave.2.fill" : "heart.fill")
                    .foregroundStyle(theme)
                Text(memo.kind == .childVoice ? "布布的声音" : "家人对她说")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer()
                Text(BubuDateFormat.shortDate(memo.recordedAt))
                    .font(.system(size: 11)).foregroundStyle(BubuTheme.Color.secondaryText)
            }
            if let fileName = memo.localFileName {
                VoicePlayerBubble(fileName: fileName, duration: memo.durationSeconds ?? 0,
                                  waveform: [], mediaStore: env.mediaStore, tint: theme)
            }
            if let t = memo.transcript, !t.isEmpty {
                Text(t).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    .italic()
            }
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            BubuMascotBadge(size: 84, expression: .music)
            Text("还没有声音").font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
            Text("点右上角，录下布布此刻的声音。").font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .padding(40)
    }
}

// MARK: - 成长之声 · 录制

struct VoiceMemoRecorderSheet: View {
    let kind: VoiceMemo.Kind
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [ChildProfile]

    @State private var pending: (fileName: String, duration: Double, waveform: [Float])?
    @State private var transcribing = false
    @State private var transcript: String?

    private var theme: Color { env.theme.theme.primary }
    private var profile: ChildProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ZStack {
                BubuTheme.Color.background.ignoresSafeArea()
                VStack(spacing: 24) {
                    Text(kind == .childVoice ? "录下布布的声音" : "对布布说点什么")
                        .font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)

                    if let p = pending {
                        VoicePlayerBubble(fileName: p.fileName, duration: p.duration,
                                          waveform: p.waveform, mediaStore: env.mediaStore, tint: theme)
                        if env.config.isAIConfigured {
                            Button {
                                Task { await runTranscribe(p.fileName) }
                            } label: {
                                HStack {
                                    if transcribing { ProgressView() }
                                    else { Image(systemName: "text.bubble") }
                                    Text(transcribing ? "转写中…" : "转成文字")
                                }
                                .font(BubuTheme.Font.body).foregroundStyle(theme)
                            }
                            .disabled(transcribing)
                        }
                        if let t = transcript {
                            Text(t).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
                                .padding().background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                    } else {
                        VoiceRecorderBar(mediaStore: env.mediaStore) { fileName, duration, waveform in
                            pending = (fileName, duration, waveform)
                        }
                    }
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("成长之声")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("收好") { save() }.fontWeight(.bold).disabled(pending == nil)
                }
            }
        }
    }

    private func runTranscribe(_ fileName: String) async {
        transcribing = true
        defer { transcribing = false }
        let url = env.mediaStore.mediaURL(for: fileName)
        transcript = try? await env.aiService.transcribe(audioURL: url)
    }

    private func save() {
        guard let p = pending else { return }
        let memo = VoiceMemo(kind: kind, recordedAt: .now)
        memo.localFileName = p.fileName
        memo.durationSeconds = p.duration
        memo.transcript = transcript
        memo.syncState = .local
        if let profile {
            memo.ageYears = AgeCalculator.ageYears(birthday: profile.birthday, at: .now)
        }
        context.insert(memo)
        try? context.save()
        dismiss()
    }
}
