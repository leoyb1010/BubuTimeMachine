import WidgetKit
import SwiftUI
import UIKit

// Preserve existing widget kinds/families and placements. Each is only a photo entry.
struct BubuPhotoWidgetEntry: TimelineEntry {
    let date: Date
    let memory: WatchMemory?
    let photo: UIImage?
    let avatar: UIImage?
}

struct BubuPhotoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BubuPhotoWidgetEntry {
        BubuPhotoWidgetEntry(date: .now, memory: nil, photo: nil, avatar: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (BubuPhotoWidgetEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BubuPhotoWidgetEntry>) -> Void) {
        // Receipt of a new photo batch explicitly reloads the timeline; no slideshow.
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(3600))))
    }
    private func entry() -> BubuPhotoWidgetEntry {
        let snapshot = WatchSnapshotStore.load()
        for card in WatchReadModel.memories(from: snapshot) {
            if let data = WatchPhotoStore.data(for: card.photoFileName), let image = UIImage(data: data) {
                return BubuPhotoWidgetEntry(date: .now, memory: card, photo: image, avatar: nil)
            }
        }
        return BubuPhotoWidgetEntry(date: .now, memory: nil, photo: nil,
                                   avatar: snapshot?.avatarData.flatMap { UIImage(data: $0) })
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
                Image(systemName: "photo").widgetLabel("布布")
            case .accessoryInline:
                Label("布布", systemImage: "photo")
            default:
                HStack(spacing: 8) {
                    if let image = entry.photo, renderingMode == .fullColor {
                        Image(uiImage: image).resizable().scaledToFit().frame(width: 56)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.memory?.dateText ?? "布布").font(.caption2).foregroundStyle(.secondary)
                        Text(entry.memory?.note ?? "打开看照片").font(.caption).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .widgetURL(URL(string: "bubuwatch://photos"))
        .containerBackground(for: .widget) { Color.black.opacity(0.25) }
        .accessibilityLabel("打开布布的照片")
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
