import WidgetKit
import SwiftUI

// MARK: - 手表复杂功能（表盘小部件）+ 智能叠放卡片
/// 数据来自手表本地 App Group（手表 App 收到 iPhone 快照后写入）。
/// accessory 系列可放到系统表盘四角/单行，也充当 Smart Stack 卡片（带 relevance：生日临近置顶）。

struct BubuComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot?
}

struct BubuComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> BubuComplicationEntry {
        BubuComplicationEntry(date: .now, snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (BubuComplicationEntry) -> Void) {
        completion(BubuComplicationEntry(date: .now, snapshot: WatchSnapshotStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BubuComplicationEntry>) -> Void) {
        let entry = BubuComplicationEntry(date: .now, snapshot: WatchSnapshotStore.load())
        // 按天刷新（年龄/倒计时是日粒度）。
        let next = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 3),
                                             matchingPolicy: .nextTime) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - 年龄计算（复用共享 AgeCalculator 需要它在扩展 target；这里内联极简版避免拉更多文件）
private func daysUntilBirthday(_ birthday: Date) -> Int {
    let cal = Calendar.current
    let now = Date()
    guard let next = cal.nextDate(after: now, matching: cal.dateComponents([.month, .day], from: birthday),
                                  matchingPolicy: .nextTimePreservingSmallerComponents) else { return 0 }
    return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: next)).day ?? 0)
}
private func daysSinceBirth(_ birthday: Date) -> Int {
    max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: birthday),
                                           to: Calendar.current.startOfDay(for: Date())).day ?? 0)
}

// MARK: - 复杂功能视图
struct BubuComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BubuComplicationEntry

    private var snap: WatchSnapshot? { entry.snapshot }
    private var name: String { snap?.childName ?? "布布" }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if let b = snap?.birthday {
                    Gauge(value: birthdayProgress(b)) {
                        Image(systemName: "birthday.cake.fill")
                    } currentValueLabel: {
                        Text("\(daysUntilBirthday(b))")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                    }
                    .gaugeStyle(.accessoryCircular)
                } else {
                    Image(systemName: "figure.child").font(.system(size: 18))
                }
            }
            .widgetURL(URL(string: "bubuwatch://record"))

        case .accessoryCorner:
            if let b = snap?.birthday {
                Text("\(daysSinceBirth(b))")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .widgetLabel("陪伴 \(daysSinceBirth(b)) 天")
            } else {
                Image(systemName: "figure.child").widgetLabel(name)
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 15, weight: .black, design: .rounded)).widgetAccentable()
                if let b = snap?.birthday {
                    Text(ageText(b)).font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("🎂 \(daysUntilBirthday(b)) 天后生日")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text("打开手表 App 看布布").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "bubuwatch://overview"))

        case .accessoryInline:
            if let b = snap?.birthday {
                Label("\(name) \(ageText(b)) · 生日 \(daysUntilBirthday(b)) 天", systemImage: "sparkles")
            } else {
                Label("布布时光机", systemImage: "sparkles")
            }

        default:
            Text(name)
        }
    }

    private func birthdayProgress(_ b: Date) -> Double {
        let d = Double(daysUntilBirthday(b))
        return max(0, min(1, (365 - d) / 365))
    }

    private func ageText(_ birthday: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: birthday, to: Date())
        let y = comps.year ?? 0, m = comps.month ?? 0
        if y == 0 { return "\(m) 个月" }
        return "\(y)岁\(m)个月"
    }
}

// MARK: - Widget 定义
struct BubuWatchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BubuWatchComplication", provider: BubuComplicationProvider()) { entry in
            BubuComplicationView(entry: entry)
        }
        .configurationDisplayName("布布")
        .description("表盘上看布布的年龄和生日倒计时，点击直达。")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct BubuWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BubuWatchComplication()
    }
}
