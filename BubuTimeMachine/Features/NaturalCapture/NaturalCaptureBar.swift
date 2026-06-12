import SwiftUI
import SwiftData

// MARK: - 全局一句话记录入口
/// 轻盈的「AI 记录卡」：写一句或说一句 → 转写 → 解析 → 确认页 → 各模块落库。
/// 不做聊天界面；失败温和降级，不暴露异常原文；转写失败不丢音频可重试。
struct NaturalCaptureBar: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var profiles: [ChildProfile]

    @State private var text = ""
    @State private var isParsing = false
    @State private var errorText: String?
    @State private var reviewPayload: ReviewPayload?

    @State private var recorder = AudioRecorder()
    @State private var isTranscribing = false
    @State private var pendingAudioURL: URL?

    private var profile: ChildProfile? { profiles.first }
    private var theme: Color { env.theme.theme.primary }
    private var isRecording: Bool { recorder.state == .recording }
    private var isBusy: Bool { isParsing || isTranscribing }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme)
                    .frame(width: 34, height: 34)
                    .background(theme.opacity(0.10), in: Circle())

                if isRecording {
                    recordingStrip
                } else if isTranscribing {
                    HStack(spacing: 8) {
                        ProgressView().tint(theme)
                        Text("正在听清布布说了什么…")
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                        Spacer()
                    }
                } else {
                    TextField("写一句或说一句：布布今天……", text: $text, axis: .vertical)
                        .font(BubuTheme.Font.body)
                        .lineLimit(1...3)
                        .submitLabel(.send)
                        .onSubmit { Task { await parseText() } }

                    Button {
                        Task { await parseText() }
                    } label: {
                        if isParsing {
                            ProgressView().tint(theme)
                                .frame(width: 28, height: 28)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(text.bubuTrimmed.isEmpty
                                                 ? BubuTheme.Color.secondaryText.opacity(0.5)
                                                 : theme)
                        }
                    }
                    .disabled(text.bubuTrimmed.isEmpty || isBusy)
                    .accessibilityLabel("识别并保存这句话")
                }

                Button {
                    Task { await toggleRecording() }
                } label: {
                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: isRecording ? 28 : 17, weight: .bold))
                        .foregroundStyle(isRecording ? .red : theme)
                }
                .disabled(isParsing || isTranscribing)
                .accessibilityLabel(isRecording ? "停止录音并识别" : "按一下开始说话")
            }
            .padding(12)
            .background(BubuTheme.Color.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .bubuGlassSurface(cornerRadius: 22, tint: theme, interactive: true)

            if let errorText {
                HStack(spacing: 10) {
                    Text(errorText)
                        .font(.system(size: 11))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                    if pendingAudioURL != nil, !isTranscribing {
                        Button("重试转写") {
                            Task {
                                if let url = pendingAudioURL { await transcribeAndParse(url: url) }
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
        .sheet(item: $reviewPayload) { payload in
            NaturalCaptureReviewSheet(result: payload.result, originalText: payload.originalText) {
                text = ""
            }
        }
    }

    private var recordingStrip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text("布布在听… \(Int(recorder.elapsed)) 秒")
                .font(BubuTheme.Font.caption.weight(.medium))
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .monospacedDigit()
            Spacer()
            Button("取消") {
                recorder.cancel()
            }
            .font(BubuTheme.Font.caption.weight(.semibold))
            .foregroundStyle(BubuTheme.Color.secondaryText)
        }
    }

    // MARK: 语音

    @MainActor
    private func toggleRecording() async {
        if isRecording {
            guard let result = recorder.stop() else { return }
            await transcribeAndParse(url: result.url)
        } else {
            errorText = nil
            guard await recorder.requestPermission() else {
                errorText = "需要麦克风权限，去系统设置里给布布开启吧。"
                return
            }
            if !recorder.start() {
                errorText = "录音启动失败，稍后再试试。"
            }
        }
    }

    @MainActor
    private func transcribeAndParse(url: URL) async {
        pendingAudioURL = url
        isTranscribing = true
        errorText = nil
        defer { isTranscribing = false }
        do {
            let transcript = try await env.aiService.transcribe(audioURL: url)
            guard !transcript.bubuTrimmed.isEmpty else {
                errorText = "没听清，可以再说一次或直接打字。"
                return
            }
            text = transcript          // 转写文本可在确认前继续编辑
            pendingAudioURL = nil
            try? FileManager.default.removeItem(at: url)
            await parseText()
        } catch {
            errorText = "转写失败了，可以重试或直接打字。"
            #if DEBUG
            print("[NaturalCapture] transcribe failed:", error)
            #endif
        }
    }

    // MARK: 文字解析

    @MainActor
    private func parseText() async {
        let input = text.bubuTrimmed
        guard !input.isEmpty, !isParsing else { return }

        isParsing = true
        errorText = nil
        defer { isParsing = false }

        do {
            let request = NaturalCaptureRequest(
                text: input,
                childName: profile?.name ?? "布布",
                timezone: TimeZone.current.identifier,
                referenceDate: .now
            )
            let result = try await env.aiService.parseNaturalCapture(request)
            reviewPayload = ReviewPayload(result: result, originalText: input)
        } catch {
            errorText = "智能识别暂时不可用，可以先用「记录此刻」保存。"
            #if DEBUG
            print("[NaturalCapture] parse failed:", error)
            #endif
        }
    }
}

private struct ReviewPayload: Identifiable {
    let id = UUID()
    let result: NaturalCaptureResult
    let originalText: String
}
