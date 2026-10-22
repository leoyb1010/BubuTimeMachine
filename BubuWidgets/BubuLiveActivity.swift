import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

// MARK: - Live Activity UI（锁屏 + 灵动岛）
/// 渲染几个场景：录音中（时长跳动；录音一进后台就自动收尾，所以锁屏上不放停止键）、
/// 哄睡计时（带「醒啦」按钮，锁屏一点就结束并记下睡了多久）、时间胶囊倒计时（系统自走倒计时）、
/// 课程上传（压缩/上传/解析进度，奶油底粉色进度条；过期时显示灰态「打开 App 看看结果」）。
/// 每个场景都带 widgetURL 深链：课程 → 那天的每日学习，哄睡 → 成长，其余 → 首页。
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
                    .widgetURL(context.attributes.widgetURL)
            } else {
                lockScreen(context)
                    .padding()
                    // 视图内文字为固定白字：底衬要压得够深，浅色壁纸锁屏下白字才保底可读（P3-48）。
                    .activityBackgroundTint(Color.black.opacity(0.55))
                    .widgetURL(context.attributes.widgetURL)
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
                        CourseUploadProgressBar(value: context.isStale ? 1 : overall(context, phase),
                                                track: .white.opacity(0.18), muted: context.isStale)
                            .padding(.horizontal, 4)
                    } else if context.attributes.kind == .sleepTimer {
                        WakeUpButton()
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
            .widgetURL(context.attributes.widgetURL)
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
            if context.attributes.kind == .sleepTimer {
                WakeUpButton()
            }
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
    /// 过期 = 主 App 很久没来更新（多半被挂起），不能再显示「解析中 90%」装作还在推进。
    private var stale: Bool { context.isStale && !phase.isTerminal }
    private var hint: String {
        stale ? CourseUploadActivityPhase.staleHint : phase.hint(childName: context.attributes.childName)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().fill(stale ? Color.gray.opacity(0.18) : phase == .failed ? LAPalette.butter : LAPalette.primary.opacity(0.22))
                Image(systemName: stale ? "hourglass" : phase.symbol)
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
                    Text(stale ? "去 App 看看" : stateText)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(stale ? LAPalette.warmBrown : LAPalette.deepRose)
                        .monospacedDigit()
                }
                CourseUploadProgressBar(
                    value: phase.overallProgress(progress: context.state.progress, step: context.state.step,
                                                 steps: context.state.steps),
                    track: LAPalette.primary.opacity(0.18), muted: stale)
                Text(hint)
                    .font(.system(.caption, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(LAPalette.warmBrown)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(context.attributes.title)，\(stale ? "有一阵没更新" : stateText)，\(hint)")
    }
}

private struct CourseUploadProgressBar: View {
    let value: Double
    let track: Color
    var muted = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(LinearGradient(colors: muted ? [Color.gray.opacity(0.35), Color.gray.opacity(0.5)]
                                                        : [LAPalette.primary, LAPalette.deepRose],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

// MARK: - 哄睡：锁屏「醒啦」

/// 点一下就结束哄睡计时并记下睡了多久（EndSleepActivityIntent 在主 App 进程里写库）。
private struct WakeUpButton: View {
    var body: some View {
        Button(intent: EndSleepActivityIntent()) {
            Label("醒啦", systemImage: "sun.max.fill")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LAPalette.warmBrown)
        .background(LAPalette.butter, in: Capsule())
        .accessibilityLabel("布布醒啦，结束哄睡计时")
    }
}
