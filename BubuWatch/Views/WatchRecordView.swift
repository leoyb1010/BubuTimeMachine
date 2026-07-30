import SwiftUI
import WatchKit

// MARK: - 快速记录：说一句 / 写一句 / 心情
/// 录音重做：按下后长成全屏录音态——中央计时 + 实时波形环（36 根放射短棒随声音起伏），
/// 按下去终于"像在录"。停止键挂双指互点（Ultra 2 捏两下手指 = 停止并发送），
/// 抱着布布单手也能收尾。
struct WatchRecordView: View {
    @Environment(WatchConnector.self) private var connector
    @State private var recorder = WatchVoiceRecorder()
    @State private var text = ""
    @State private var showMood = false

    var body: some View {
        Group {
            if recorder.isRecording {
                recordingStage
            } else {
                idleList
            }
        }
        .background(WatchSpaceBackground(accent: WatchTheme.deepRose))
        // 来电/Siri 打断自动收尾的录音：当作正常停止发送，已录部分不丢（W-P2）。
        .onChange(of: recorder.isRecording) { _, nowRecording in
            guard !nowRecording, let result = recorder.consumeInterruptedResult() else { return }
            connector.sendVoice(fileURL: result.url, duration: result.duration)
            WKInterfaceDevice.current().play(.success)
        }
        .onDisappear { recorder.cancel() }
        .sheet(isPresented: $showMood) { WatchMoodView() }
    }

    // MARK: 待机态

    private var idleList: some View {
        ScrollView {
            VStack(spacing: 10) {
                Button {
                    Task { _ = await recorder.toggle() }
                    WKInterfaceDevice.current().play(.start)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 26, weight: .black))
                        Text("说一句")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                }
                .tint(WatchTheme.rose)
                .overlay(alignment: .bottom) {
                    if recorder.permissionDenied {
                        Text("请在手表上允许麦克风")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }

                textField

                Button {
                    showMood = true
                } label: {
                    Label("心情", systemImage: "face.smiling.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(WatchTheme.lav)
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("记录")
    }

    private var textField: some View {
        HStack(spacing: 6) {
            TextField("写一句…", text: $text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
            Button {
                connector.sendText(text)
                text = ""
                WKInterfaceDevice.current().play(.success)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 22))
            }
            .buttonStyle(.plain)
            .foregroundStyle(text.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : WatchTheme.mint)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.white.opacity(0.10), in: Capsule())
    }

    // MARK: 录音态（全屏波形环）

    private var recordingStage: some View {
        VStack(spacing: 8) {
            ZStack {
                WaveformRing(recorder: recorder)
                VStack(spacing: 1) {
                    // 计时读 recorder.elapsed（真实录音时长，挂起不虚增）。
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        Text(timeText(recorder.elapsed))
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                    Text("在听…")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(WatchTheme.rose)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                stopAndSend()
            } label: {
                Label("说完了", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .tint(WatchTheme.deepRose)
            // Ultra 2 双指互点 = 主操作：抱着布布单手收尾。
            .handGestureShortcut(.primaryAction)
        }
        .navigationBarBackButtonHidden(true)
    }

    private func stopAndSend() {
        Task {
            if let result = await recorder.toggle() {
                connector.sendVoice(fileURL: result.url, duration: result.duration)
                WKInterfaceDevice.current().play(.success)
            }
        }
    }

    private func timeText(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - 实时波形环
/// 36 根从圆心放射的短棒，长度跟随电平历史——环是一圈"最近 36 帧声音"，
/// 说话时像涟漪一圈圈荡开。采样 15fps 写环形缓冲，Canvas 一层画完。
private struct WaveformRing: View {
    let recorder: WatchVoiceRecorder
    @State private var history = [Double](repeating: 0, count: 36)
    @State private var head = 0

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let innerR = min(size.width, size.height) * 0.30
            let maxBar = min(size.width, size.height) * 0.16
            for i in 0..<36 {
                let angle = Double(i) / 36 * 2 * .pi - .pi / 2
                // 越靠近写入头的帧越新，越亮。
                let ago = (head - i + 36) % 36
                let bar = 2.5 + history[i] * maxBar
                let alpha = 0.25 + 0.75 * (1 - Double(ago) / 36)
                var path = Path()
                path.move(to: CGPoint(x: center.x + cos(angle) * innerR,
                                      y: center.y + sin(angle) * innerR))
                path.addLine(to: CGPoint(x: center.x + cos(angle) * (innerR + bar),
                                         y: center.y + sin(angle) * (innerR + bar)))
                context.stroke(path, with: .color(WatchTheme.rose.opacity(alpha)),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .task {
            // 15fps 采样电平写入环形缓冲；@State 变更自然触发 Canvas 重绘。
            // View 离屏 task 自动取消，不留常驻定时器。
            while !Task.isCancelled {
                let level = recorder.currentLevel()
                head = (head + 1) % 36
                history[head] = level
                try? await Task.sleep(for: .milliseconds(66))
            }
        }
    }
}
