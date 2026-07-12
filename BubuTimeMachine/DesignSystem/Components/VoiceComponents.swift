import SwiftUI

// MARK: - 波形视图
/// 把 0...1 的采样画成一排圆角竖条。可选高亮进度（播放时）。
struct WaveformView: View {
    let samples: [Float]
    var progress: Double = 1            // 0...1，已播放比例高亮
    var color: Color = BubuTheme.Color.primary
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                    let played = Double(index) / Double(max(samples.count - 1, 1)) <= progress
                    Capsule()
                        .fill(played ? color : color.opacity(0.25))
                        .frame(width: barWidth,
                               height: max(3, CGFloat(sample) * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - 语音录制条
/// 一键录音 → 实时波形 + 计时 → 停止。回调返回（沙盒文件名、时长、波形）。
struct VoiceRecorderBar: View {
    @State private var recorder = AudioRecorder()
    @State private var denied = false
    let mediaStore: MediaStore
    var onFinished: (_ fileName: String, _ duration: Double, _ waveform: [Float]) -> Void

    private var theme = BubuTheme.Color.primary

    init(mediaStore: MediaStore,
         onFinished: @escaping (_ fileName: String, _ duration: Double, _ waveform: [Float]) -> Void) {
        self.mediaStore = mediaStore
        self.onFinished = onFinished
    }

    var body: some View {
        HStack(spacing: 14) {
            recordButton
            if recorder.state == .recording {
                liveWaveform
                Text(timeString(recorder.elapsed))
                    .font(BubuTheme.Font.scaled(16, weight: .medium, design: .monospaced))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            } else {
                Text("点一下开始，再点一下收好")
                    .font(BubuTheme.Font.body)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                Spacer()
            }
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
        .alert("需要麦克风权限", isPresented: $denied) {
            Button("好") {}
        } message: {
            Text("请到系统设置里允许布布时光机使用麦克风。")
        }
        // 来电等中断自动收尾的录音：当作正常停止处理，已录部分不丢（R4 P2-37）
        .onChange(of: recorder.state) { _, newState in
            guard newState == .finished,
                  let result = recorder.consumeInterruptedResult() else { return }
            defer { try? FileManager.default.removeItem(at: result.url) }
            if let fileName = try? mediaStore.importFile(from: result.url, preferredExtension: "m4a") {
                onFinished(fileName, result.duration, result.waveform)
            }
        }
        .onDisappear {
            if recorder.state == .recording {
                recorder.cancel()
            }
        }
    }

    private var recordButton: some View {
        Button {
            toggle()
        } label: {
            Image(systemName: recorder.state == .recording ? "stop.circle.fill" : "mic.circle.fill")
                .font(BubuTheme.Font.scaled(44))
                .foregroundStyle(recorder.state == .recording ? .red : theme)
                .symbolEffect(.pulse, isActive: recorder.state == .recording)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recorder.state == .recording ? "停止录音" : "开始录音")
    }

    private var liveWaveform: some View {
        WaveformView(samples: recorder.levels.suffix(30).map { $0 }, color: theme)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
    }

    private func toggle() {
        if recorder.state == .recording {
            guard let result = recorder.stop() else { return }
            // 结束：双击感（两次轻触觉）
            BubuHaptics.tapLight()
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                BubuHaptics.tapLight()
            }
            defer { try? FileManager.default.removeItem(at: result.url) }
            if let fileName = try? mediaStore.importFile(from: result.url, preferredExtension: "m4a") {
                onFinished(fileName, result.duration, result.waveform)
            }
        } else {
            Task {
                let granted = await recorder.requestPermission()
                if granted {
                    BubuHaptics.tapLight()
                    recorder.start()
                } else { denied = true }
            }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%01d:%02d", s / 60, s % 60)
    }
}

// MARK: - 语音播放气泡
/// 展示已录语音：播放按钮 + 波形 + 时长。
struct VoicePlayerBubble: View {
    let fileName: String
    let duration: Double
    let waveform: [Float]
    let mediaStore: MediaStore
    var tint: Color = BubuTheme.Color.primary

    @State private var player = AudioPlayer()

    var body: some View {
        // playbackURL：胶囊解封语音在临时目录，普通录音在媒体目录——统一在此解析。
        let url = mediaStore.playbackURL(for: fileName)
        let isThis = player.playingURL == url
        return HStack(spacing: 12) {
            Button {
                player.toggle(url: url)
            } label: {
                Image(systemName: isThis && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(BubuTheme.Font.scaled(36))
                    .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isThis && player.isPlaying ? "暂停语音" : "播放语音")

            WaveformView(samples: waveform.isEmpty ? Array(repeating: 0.3, count: 20) : waveform,
                         progress: isThis ? player.progress : 0, color: tint)
                .frame(height: 30)

            Text(timeString(duration))
                .font(BubuTheme.Font.scaled(14, weight: .medium, design: .monospaced))
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(tint.opacity(0.08), in: Capsule())
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%01d:%02d", s / 60, s % 60)
    }
}
