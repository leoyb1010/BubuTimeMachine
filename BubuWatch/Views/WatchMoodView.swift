import SwiftUI
import WatchKit

// MARK: - 心情快记（表冠轮盘）
/// 从"一屏小格子"改成表冠轮盘：拧表冠滚动心情，选中的放大居中、两侧渐隐，
/// 每过一档轻嗒。选好点一下，星尘迸发 + 发送。
/// 为什么是轮盘不是网格：手表屏太小，12 格网格每格只有 48pt，误触率高；
/// 轮盘一次只呈现一个选项 + 表冠精确步进，选择反而更快。
struct WatchMoodView: View {
    @Environment(WatchConnector.self) private var connector
    @Environment(\.dismiss) private var dismiss

    private let moods: [Mood] = [.happy, .laughing, .eating, .sleepy, .curious,
                                 .naughty, .crying, .cuddly, .brave, .love,
                                 .surprised, .milestone]

    @State private var crownValue: Double = 0
    @State private var index = 0
    @State private var burst = 0
    /// 防双发：确认后到 dismiss 的 450ms 窗口内再点/再双捏会重复落两条心情。
    @State private var sent = false

    var body: some View {
        VStack(spacing: 6) {
            wheel
            Text(moods[index].rawValue)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(WatchTheme.lav)
                .contentTransition(.opacity)

            Button {
                confirm()
            } label: {
                Label("就是这个", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .tint(WatchTheme.lav)
            .handGestureShortcut(.primaryAction)
        }
        .background(WatchSpaceBackground(accent: WatchTheme.lav))
        .navigationTitle("心情")
        .focusable()
        .digitalCrownRotation($crownValue,
                              from: 0, through: Double(moods.count - 1),
                              by: 1, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crownValue) { _, value in
            let next = min(max(Int(value.rounded()), 0), moods.count - 1)
            guard next != index else { return }
            withAnimation(.spring(duration: 0.25, bounce: 0.4)) { index = next }
        }
        .sensoryFeedback(.selection, trigger: index)
    }

    /// 当前 + 左右邻居三个 emoji：选中的 1.4x 居中，两侧缩小渐隐。
    private var wheel: some View {
        ZStack {
            ForEach(moods.indices, id: \.self) { i in
                let offset = i - index
                if abs(offset) <= 1 {
                    Text(moods[i].emoji)
                        .font(.system(size: 40))
                        .scaleEffect(offset == 0 ? 1.4 : 0.75)
                        .opacity(offset == 0 ? 1 : 0.35)
                        .offset(x: CGFloat(offset) * 58)
                        .animation(.spring(duration: 0.25, bounce: 0.4), value: index)
                }
            }
            StarBurst(trigger: burst)
        }
        .frame(height: 64)
    }

    private func confirm() {
        guard !sent else { return }
        sent = true
        burst += 1
        let mood = moods[index]
        connector.sendMood(rawValue: mood.rawValue, emoji: mood.emoji)
        WKInterfaceDevice.current().play(.success)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))   // 让星尘放完再走
            dismiss()
        }
    }
}

// MARK: - 星尘迸发（确认动作的统一母题）
struct StarBurst: View {
    let trigger: Int

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8 * 2 * .pi
                Text(i % 2 == 0 ? "✨" : "⭐️")
                    .font(.system(size: i % 2 == 0 ? 12 : 9))
                    .phaseAnimator([0, 1], trigger: trigger) { view, phase in
                        view.offset(x: phase == 1 ? cos(angle) * 42 : 0,
                                    y: phase == 1 ? sin(angle) * 42 : 0)
                            .opacity(phase == 1 ? 0 : (trigger > 0 ? 1 : 0))
                            .scaleEffect(phase == 1 ? 1.3 : 0.5)
                    } animation: { _ in .easeOut(duration: 0.5) }
            }
        }
        .allowsHitTesting(false)
    }
}
