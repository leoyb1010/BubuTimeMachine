import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity UI（锁屏 + 灵动岛）
/// 渲染两个场景：录音中（时长跳动 + 停止）、时间胶囊倒计时（系统自走倒计时）。
/// 用 Text(timerInterval:) / Text(_, style: .timer) 让系统自驱，避免主 App 频繁 update 耗电。
private enum LAPalette {
    static let primary = Color(red: 0.95, green: 0.55, blue: 0.62)
    static let warmBrown = Color(red: 0.36, green: 0.28, blue: 0.24)
}

struct BubuLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BubuActivityAttributes.self) { context in
            // 锁屏 / 横幅
            lockScreen(context)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.25))
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开态
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: icon(context))
                        .font(.title2)
                        .foregroundStyle(LAPalette.primary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    trailingValue(context)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: icon(context)).foregroundStyle(LAPalette.primary)
            } compactTrailing: {
                trailingValue(context).font(.system(.caption2, design: .rounded).weight(.bold))
            } minimal: {
                Image(systemName: icon(context)).foregroundStyle(LAPalette.primary)
            }
        }
    }

    // MARK: 锁屏视图
    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<BubuActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(context))
                .font(.title)
                .foregroundStyle(LAPalette.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                trailingValue(context)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
    }

    private func icon(_ context: ActivityViewContext<BubuActivityAttributes>) -> String {
        switch context.attributes.kind {
        case .voiceRecording: return "waveform.circle.fill"
        case .capsuleCountdown: return "envelope.circle.fill"
        case .sleepTimer: return "moon.zzz.fill"
        }
    }

    /// 右侧主数值：录音→自走时长；胶囊→自走倒计时。
    @ViewBuilder
    private func trailingValue(_ context: ActivityViewContext<BubuActivityAttributes>) -> some View {
        switch context.attributes.kind {
        case .voiceRecording, .sleepTimer:
            Text(context.state.startedAt, style: .timer)
                .monospacedDigit()
        case .capsuleCountdown:
            if let unlock = context.attributes.unlockAt {
                if unlock > Date.now {
                    Text(timerInterval: Date.now...unlock, countsDown: true)
                        .monospacedDigit()
                } else {
                    Text("可开启")
                }
            } else {
                Text("未设置")
            }
        }
    }
}
