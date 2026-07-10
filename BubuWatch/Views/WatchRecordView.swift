import SwiftUI
import WatchKit

// MARK: - 快速记录：说一句 / 写一句 / 心情
struct WatchRecordView: View {
    @Environment(WatchConnector.self) private var connector
    @State private var recorder = WatchVoiceRecorder()
    @State private var text = ""
    @State private var showMood = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                voiceButton
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
        .containerBackground(WatchTheme.deepRose.opacity(0.2).gradient, for: .tabView)
        .sheet(isPresented: $showMood) { WatchMoodView() }
    }

    private var voiceButton: some View {
        Button {
            Task {
                if let result = await recorder.toggle() {
                    connector.sendVoice(fileURL: result.url, duration: result.duration)
                    WKInterfaceDevice.current().play(.success)
                } else if recorder.isRecording {
                    WKInterfaceDevice.current().play(.start)
                }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 26, weight: .black))
                Text(recorder.isRecording ? "说完点一下" : "说一句")
                    .font(.system(size: 15, weight: .black, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 62)
        }
        .tint(recorder.isRecording ? WatchTheme.deepRose : WatchTheme.rose)
        .overlay(alignment: .bottom) {
            if recorder.permissionDenied {
                Text("请在手表上允许麦克风")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
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
}
