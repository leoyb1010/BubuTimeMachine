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
                            .background(.white, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))

                        if let v = voice {
                            HStack {
                                VoicePlayerBubble(fileName: v.fileName, duration: v.duration,
                                                  waveform: v.waveform, mediaStore: env.mediaStore, tint: theme)
                                Button { voice = nil } label: {
                                    Image(systemName: "trash.circle.fill").font(.system(size: 26))
                                        .foregroundStyle(BubuTheme.Color.secondaryText)
                                }
                                .buttonStyle(.plain)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { save() }.fontWeight(.bold)
                        .disabled(text.isEmpty && voice == nil)
                }
            }
        }
    }

    private func save() {
        let comment = Comment(authorRole: role, text: text.isEmpty ? nil : text)
        if let v = voice {
            comment.voiceFileName = v.fileName
            comment.voiceDuration = v.duration
            comment.voiceWaveform = v.waveform
        }
        comment.entry = entry
        context.insert(comment)
        try? context.save()
        dismiss()
    }
}
