import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity UI（锁屏 + 灵动岛）
/// 渲染几个场景：录音中（时长跳动 + 停止）、时间胶囊倒计时（系统自走倒计时）、
/// 课程上传（压缩/上传/解析进度，奶油底粉色进度条）。
/// 用 Text(timerInterval:) / Text(_, style: .timer) 让系统自驱，避免主 App 频繁 update 耗电。
private enum LAPalette {
    static let primary = Color(red: 0.95, green: 0.55, blue: 0.62)
    static let deepRose = Color(red: 0.78, green: 0.33, blue: 0.43)
    static let warmBrown = Color(red: 0.36, green: 0.28, blue: 0.24)
    static let cream = Color(red: 1.0, green: 0.97, blue: 0.93)
    static let butter = Color(red: 1.0, green: 0.886, blue: 0.627)
}

struct BubuLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BubuActivityAttributes.self) { context in
            // 锁屏 / 横幅
            if context.attributes.kind == .courseUpload {
                CourseUploadLockScreen(context: context)
                    .padding()
                    // 奶油底 + 暖棕字：浅色深色壁纸都保证对比度。
                    .activityBackgroundTint(LAPalette.cream)
                    .activitySystemActionForegroundColor(LAPalette.deepRose)
            } else {
                lockScreen(context)
                    .padding()
                    // 视图内文字为固定白字：底衬要压得够深，浅色壁纸锁屏下白字才保底可读（P3-48）。
                    .activityBackgroundTint(Color.black.opacity(0.55))
            }
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开态
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: icon(context))
                        .font(.title2)
                        .foregroundStyle(LAPalette.primary)
                        .accessibilityHidden(true)
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
                DynamicIslandExpandedRegion(.bottom) {
                    if context.attributes.kind == .courseUpload, let phase = context.state.uploadPhase {
                        CourseUploadProgressBar(value: overall(context, phase), track: .white.opacity(0.18))
                            .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                Image(systemName: icon(context)).foregroundStyle(LAPalette.primary)
            } compactTrailing: {
                if context.attributes.kind == .courseUpload, let phase = context.state.uploadPhase {
                    Text(phase.shortText(progress: context.state.progress, step: context.state.step, steps: context.state.steps))
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(LAPalette.primary)
                } else {
                    trailingValue(context).font(.system(.caption2, design: .rounded).weight(.bold))
                }
            } minimal: {
                if context.attributes.kind == .courseUpload, let phase = context.state.uploadPhase, !phase.isTerminal {
                    ProgressView(value: overall(context, phase)) {
                        Image(systemName: icon(context))
                    }
                    .progressViewStyle(.circular)
                    .tint(LAPalette.primary)
                } else {
                    Image(systemName: icon(context)).foregroundStyle(LAPalette.primary)
                }
            }
        }
    }

    private func overall(_ context: ActivityViewContext<BubuActivityAttributes>, _ phase: CourseUploadActivityPhase) -> Double {
        phase.overallProgress(progress: context.state.progress, step: context.state.step, steps: context.state.steps)
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
        case .courseUpload: return context.state.uploadPhase?.symbol ?? "graduationcap.fill"
        }
    }

    /// 右侧主数值：录音→自走时长；胶囊→自走倒计时；课程→阶段文案。
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
        case .courseUpload:
            Text((context.state.uploadPhase ?? .uploading)
                .text(progress: context.state.progress, step: context.state.step, steps: context.state.steps))
                .monospacedDigit()
        }
    }
}

// MARK: - 课程上传：锁屏卡片

private struct CourseUploadLockScreen: View {
    let context: ActivityViewContext<BubuActivityAttributes>

    private var phase: CourseUploadActivityPhase { context.state.uploadPhase ?? .uploading }
    private var stateText: String {
        phase.text(progress: context.state.progress, step: context.state.step, steps: context.state.steps)
    }
    private var hint: String {
        switch phase {
        case .compressing, .uploading: "请保持在每日学习页面，传完就好啦"
        case .parsing: "家里的服务器正在听老师的原声"
        case .ready: "去 App 里核对一下，就能开放给\(context.attributes.childName)"
        case .failed: "这次没传上，回到 App 再试一次吧"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().fill(phase == .failed ? LAPalette.butter : LAPalette.primary.opacity(0.22))
                Image(systemName: phase.symbol)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(LAPalette.deepRose)
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(context.attributes.title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(stateText)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(LAPalette.deepRose)
                        .monospacedDigit()
                }
                CourseUploadProgressBar(
                    value: phase.overallProgress(progress: context.state.progress, step: context.state.step,
                                                 steps: context.state.steps),
                    track: LAPalette.primary.opacity(0.18))
                Text(hint)
                    .font(.system(.caption, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(LAPalette.warmBrown)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(context.attributes.title)，\(stateText)，\(hint)")
    }
}

private struct CourseUploadProgressBar: View {
    let value: Double
    let track: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(LinearGradient(colors: [LAPalette.primary, LAPalette.deepRose],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}
