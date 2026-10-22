import WidgetKit
import SwiftUI
import UIKit

// Preserve existing widget kinds/families and placements. Each is only a photo entry.
struct BubuPhotoWidgetEntry: TimelineEntry {
    let date: Date
    let memory: WatchMemory?
    let photo: UIImage?
    let avatar: UIImage?
    var name = "布布"
    var ageText: String?
}

/// 布布现在多大：「2岁5个月」「5个月12天」「18天」。手表侧自己算，跟随当天自动变。
enum WatchAgeText {
    static func text(birthday: Date, now: Date = .now, calendar: Calendar = .current) -> String? {
        let start = calendar.startOfDay(for: birthday), end = calendar.startOfDay(for: now)
        guard end >= start else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: start, to: end)
        let years = parts.year ?? 0, months = parts.month ?? 0, days = parts.day ?? 0
        if years > 0 { return months > 0 ? "\(years)岁\(months)个月" : "\(years)岁" }
        if months > 0 { return days > 0 ? "\(months)个月\(days)天" : "\(months)个月" }
        return "\(days)天"
    }
}

struct BubuPhotoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BubuPhotoWidgetEntry {
        BubuPhotoWidgetEntry(date: .now, memory: nil, photo: nil, avatar: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (BubuPhotoWidgetEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BubuPhotoWidgetEntry>) -> Void) {
        // Receipt of a new photo batch explicitly reloads the timeline; no slideshow.
        // Age is day-granular: refresh shortly after midnight so「2岁5个月」rolls over on time.
        let midnight = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 2),
                                                 matchingPolicy: .nextTime) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry()], policy: .after(min(midnight, .now.addingTimeInterval(3600)))))
    }
    private func entry() -> BubuPhotoWidgetEntry {
        let snapshot = WatchSnapshotStore.load()
        let name = snapshot.map { $0.childName.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "布布"
        let age = snapshot?.birthday.flatMap { WatchAgeText.text(birthday: $0) }
        let avatar = snapshot?.avatarData.flatMap { UIImage(data: $0) }
        // 今日精选优先，其次本机照片。
        for card in WatchReadModel.dailyPicks(from: snapshot) + WatchReadModel.memories(from: snapshot) {
            if let data = WatchPhotoStore.data(for: card.photoFileName), let image = UIImage(data: data) {
                return BubuPhotoWidgetEntry(date: .now, memory: card, photo: image, avatar: avatar,
                                            name: name, ageText: age)
            }
        }
        return BubuPhotoWidgetEntry(date: .now, memory: nil, photo: nil, avatar: avatar, name: name, ageText: age)
    }
}

struct BubuPhotoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: BubuPhotoWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    if let image = entry.avatar ?? entry.photo {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(Circle())
                    } else { Image(systemName: "photo") }
                }
            case .accessoryCorner:
                Image(systemName: "heart.fill").widgetLabel(entry.ageText ?? entry.name)
            case .accessoryInline:
                Label(entry.ageText.map { "\(entry.name) \($0)" } ?? entry.name, systemImage: "heart.fill")
            default:
                HStack(spacing: 8) {
                    if let image = entry.photo, renderingMode == .fullColor {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.ageText.map { "\(entry.name) · \($0)" } ?? entry.name)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(Color(red: 0.949, green: 0.471, blue: 0.624))
                            .widgetAccentable()
                        Text([entry.memory?.reason, entry.memory?.dateText].compactMap { $0 }
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Text(entry.memory.flatMap { $0.note.isEmpty ? nil : $0.note } ?? "打开看照片")
                            .font(.caption2).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .widgetURL(URL(string: "bubuwatch://photos"))
        .containerBackground(for: .widget) { Color.black.opacity(0.25) }
        .accessibilityLabel(entry.ageText.map { "\(entry.name)\($0)，打开照片" } ?? "打开\(entry.name)的照片")
    }
}

struct BubuWatchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BubuWatchComplication", provider: BubuPhotoWidgetProvider()) { entry in
            BubuPhotoWidgetView(entry: entry)
        }
        .configurationDisplayName("布布")
        .description("点一下，看一眼布布。")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct BubuWatchMomentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BubuWatchMoment", provider: BubuPhotoWidgetProvider()) { entry in
            BubuPhotoWidgetView(entry: entry)
        }
        .configurationDisplayName("布布此刻")
        .description("一张照片，一句她的故事。")
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
