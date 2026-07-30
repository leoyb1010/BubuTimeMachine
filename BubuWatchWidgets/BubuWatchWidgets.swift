import WidgetKit
import SwiftUI
import UIKit

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

// MARK: - 年龄计算
// 直接调用共享 AgeCalculator（已加入本 target 的 sources）：
// 内联副本没吃到"生日当天=0天"修复，会显示"365天后生日"、"生日快乐🎂"分支永不可达，
// 且与手表 App / iPhone 小组件口径不一致。改为薄封装统一到 AgeCalculator。
private func daysUntilBirthday(_ birthday: Date) -> Int {
    AgeCalculator.daysUntilNextBirthday(birthday: birthday)
}
private func daysSinceBirth(_ birthday: Date) -> Int {
    AgeCalculator.daysSinceBirth(birthday: birthday)
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
            HStack(spacing: 7) {
                if let data = snap?.avatarData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                }
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

// MARK: - 布布此刻（Smart Stack 照片卡）
/// 转表冠进 Smart Stack 时的一张全彩照片卡：照片铺满 + 日期与一句话。
/// 靠 TimelineEntryRelevance 决定何时浮到栈顶：
/// 早晨 7–9 点（早安布布）、生日前 3 天、有「那年今日」的日子分数拉满，
/// 其余时间低分沉底——不打扰，但在对的时刻出现。
struct BubuMomentStackEntry: TimelineEntry {
    let date: Date
    let memory: WatchMemory?
    let photo: UIImage?
    let relevance: TimelineEntryRelevance?
}

struct BubuMomentStackProvider: TimelineProvider {
    func placeholder(in context: Context) -> BubuMomentStackEntry {
        BubuMomentStackEntry(date: .now, memory: nil, photo: nil, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BubuMomentStackEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BubuMomentStackEntry>) -> Void) {
        // 未来 6 小时每小时一entry（照片随小时轮换），之后重建。
        var entries: [BubuMomentStackEntry] = []
        let cal = Calendar.current
        let hourStart = cal.dateInterval(of: .hour, for: .now)?.start ?? .now
        entries.append(entry(at: .now))
        for offset in 1...6 {
            if let date = cal.date(byAdding: .hour, value: offset, to: hourStart) {
                entries.append(entry(at: date))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> BubuMomentStackEntry {
        let snap = WatchSnapshotStore.load()
        let memories = snap?.memories ?? []
        let withPhotos = memories.filter { $0.photoFileName != nil }

        // 优先「那年今日」，否则按小时轮换。
        let chosen: WatchMemory?
        if let onThisDay = withPhotos.first(where: { $0.isOnThisDay }) {
            chosen = onThisDay
        } else if !withPhotos.isEmpty {
            let hourIndex = Int(date.timeIntervalSince1970 / 3600)
            chosen = withPhotos[hourIndex % withPhotos.count]
        } else {
            chosen = memories.first
        }
        var photo: UIImage?
        if let name = chosen?.photoFileName, let data = WatchPhotoStore.data(for: name) {
            photo = UIImage(data: data)
        }
        return BubuMomentStackEntry(date: date, memory: chosen, photo: photo,
                                    relevance: relevance(at: date, snap: snap, memory: chosen))
    }

    private func relevance(at date: Date, snap: WatchSnapshot?, memory: WatchMemory?) -> TimelineEntryRelevance {
        let hour = Calendar.current.component(.hour, from: date)
        var score: Float = 20
        if (7...9).contains(hour) { score = 85 }                                   // 早安布布
        if memory?.isOnThisDay == true { score = 95 }                              // 那年今日
        if let b = snap?.birthday, daysUntilBirthday(b) <= 3 { score = 100 }       // 生日临近
        return TimelineEntryRelevance(score: score, duration: 3600)
    }
}

struct BubuMomentStackView: View {
    let entry: BubuMomentStackEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let photo = entry.photo, renderingMode == .fullColor {
                // Smart Stack 全彩：照片铺满。
                GeometryReader { geo in
                    Image(uiImage: photo)
                        .resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                LinearGradient(colors: [.clear, .black.opacity(0.62)],
                               startPoint: .center, endPoint: .bottom)
            }
            VStack(alignment: .leading, spacing: 0) {
                if let memory = entry.memory {
                    HStack(spacing: 4) {
                        if memory.isOnThisDay {
                            Text("✨ 那年今日")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.yellow)
                        } else {
                            Text(memory.dateText)
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.yellow)
                        }
                        if !memory.ageText.isEmpty {
                            Text(memory.ageText)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    Text(memory.note)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                } else {
                    Text("布布时光机")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                    Text("打开手机 App 装填回忆")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .containerBackground(for: .widget) { Color.black.opacity(0.25) }
    }
}

struct BubuWatchMomentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BubuWatchMoment", provider: BubuMomentStackProvider()) { entry in
            BubuMomentStackView(entry: entry)
        }
        .configurationDisplayName("布布此刻")
        .description("Smart Stack 里的一张布布照片卡：早晨、生日和那年今日会自己浮上来。")
        .supportedFamilies([.accessoryRectangular])
    }
}

@main
struct BubuWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BubuWatchComplication()
        BubuWatchMomentWidget()
    }
}
