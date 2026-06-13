import WidgetKit
import SwiftUI
import AppIntents

// MARK: - 时间线
struct BubuEntry: TimelineEntry {
    let date: Date
    let snapshot: BubuSnapshot
}

struct BubuProvider: TimelineProvider {
    func placeholder(in context: Context) -> BubuEntry {
        BubuEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BubuEntry) -> Void) {
        Task { @MainActor in
            completion(BubuEntry(date: .now, snapshot: BubuWidgetData.loadSnapshot()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BubuEntry>) -> Void) {
        Task { @MainActor in
            let snapshot = BubuWidgetData.loadSnapshot()
            let entry = BubuEntry(date: .now, snapshot: snapshot)
            // 按天刷新：年龄/天数/倒计时是日粒度，明天零点后刷新一次足矣（不耗电）。
            let nextMidnight = Calendar.current.nextDate(
                after: .now, matching: DateComponents(hour: 0, minute: 5),
                matchingPolicy: .nextTime
            ) ?? Date.now.addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
        }
    }
}

// MARK: - 配色（与主 App 同源暖色，不引入 App 的 BubuTheme 以保持 widget 轻量）
private enum WidgetPalette {
    static let primary = Color(red: 0.95, green: 0.55, blue: 0.62)     // 珊瑚粉
    static let warmBrown = Color(red: 0.36, green: 0.28, blue: 0.24)
    static let cream = Color(red: 0.99, green: 0.96, blue: 0.92)
    static let secondary = Color(red: 0.55, green: 0.50, blue: 0.47)
}

// MARK: - Small：身份卡
struct BubuSmallView: View {
    let snapshot: BubuSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "heart.circle.fill").foregroundStyle(WidgetPalette.primary)
                Text(snapshot.name)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(WidgetPalette.warmBrown)
                    .lineLimit(1)
            }
            Spacer()
            Text(snapshot.ageText)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetPalette.warmBrown)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            if snapshot.hasProfile {
                Text("来到世界第 \(snapshot.daysSinceBirth) 天")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetPalette.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium：身份 + 生日倒计时
struct BubuMediumView: View {
    let snapshot: BubuSnapshot
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.name)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(WidgetPalette.warmBrown)
                Text(snapshot.ageText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetPalette.primary)
                if snapshot.hasProfile {
                    Text("第 \(snapshot.daysSinceBirth) 天")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(WidgetPalette.secondary)
                }
            }
            Spacer()
            if snapshot.hasProfile {
                VStack(spacing: 2) {
                    Text("\(snapshot.daysUntilBirthday)")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(WidgetPalette.primary)
                        .contentTransition(.numericText())
                    Text("天后生日 🎂")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetPalette.secondary)
                }
            } else {
                recordButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var recordButton: some View {
        // 交互按钮直接触发 App Intents 底座的 RecordMomentIntent。
        Button(intent: RecordMomentIntent()) {
            Label("记一笔", systemImage: "plus.circle.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
        }
        .tint(WidgetPalette.primary)
    }
}

// MARK: - 锁屏 Circular：生日倒计时环
struct BubuCircularView: View {
    let snapshot: BubuSnapshot
    var body: some View {
        Gauge(value: gaugeValue) {
            Image(systemName: "birthday.cake.fill")
        } currentValueLabel: {
            Text("\(snapshot.daysUntilBirthday)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
    }
    /// 距生日剩余比例（一年内）。
    private var gaugeValue: Double {
        guard snapshot.hasProfile else { return 0 }
        return Double(365 - min(snapshot.daysUntilBirthday, 365)) / 365.0
    }
}

// MARK: - 锁屏 Rectangular：年龄行
struct BubuRectangularView: View {
    let snapshot: BubuSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.name).font(.headline)
            Text(snapshot.ageText).font(.body)
            if snapshot.hasProfile {
                Text("距生日还有 \(snapshot.daysUntilBirthday) 天")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 容器：按 family 分发 + 背景
struct BubuWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: BubuEntry

    var body: some View {
        switch family {
        case .systemSmall:
            BubuSmallView(snapshot: entry.snapshot)
                .containerBackground(WidgetPalette.cream.gradient, for: .widget)
        case .systemMedium:
            BubuMediumView(snapshot: entry.snapshot)
                .containerBackground(WidgetPalette.cream.gradient, for: .widget)
        case .accessoryCircular:
            BubuCircularView(snapshot: entry.snapshot)
        case .accessoryRectangular:
            BubuRectangularView(snapshot: entry.snapshot)
        default:
            BubuSmallView(snapshot: entry.snapshot)
                .containerBackground(WidgetPalette.cream.gradient, for: .widget)
        }
    }
}

// MARK: - Widget 定义
struct BubuWidget: Widget {
    let kind = "BubuWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BubuProvider()) { entry in
            BubuWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("布布时光机")
        .description("随时看到布布长大：年龄、来到世界第几天、生日倒计时。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Bundle
@main
struct BubuWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BubuWidget()
        BubuLiveActivity()
    }
}
