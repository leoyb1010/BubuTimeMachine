import SwiftUI

struct WatchRecentView: View {
    @Environment(WatchConnector.self) private var connector
    private var recent: [WatchMemory] {
        var seen = Set<String>()
        return (connector.snapshot?.recent ?? []).compactMap { item in
            guard seen.insert(item.id).inserted else { return nil }
            let age = connector.snapshot?.memories?.first(where: { $0.id == item.id })?.ageText ?? ""
            return WatchMemory(id: item.id, dateText: item.dateText, note: item.note, ageText: age,
                               moodEmoji: item.moodEmoji, photoFileName: item.photoFileName)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if recent.isEmpty {
                    WatchReadingEmptyState(title: "这里会有她的故事", message: "在 iPhone 留下时光，最近的故事就会来到手表。")
                } else {
                    ForEach(recent) { item in
                        NavigationLink(value: WatchReadingRoute.story(item)) {
                            HStack(alignment: .top, spacing: 8) {
                                WatchPhotoSurface(fileName: item.photoFileName, emoji: item.moodEmoji ?? "🌷")
                                    .frame(width: 42, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.dateText).font(.caption).foregroundStyle(WatchTheme.rose)
                                    Text(item.note).font(.footnote).lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.dateText)，\(item.note)，阅读完整故事")
                    }
                }
            }.padding(.horizontal, 4).padding(.bottom, 10)
        }
        .navigationTitle("最近")
        .background(WatchReadingBackground())
    }
}
