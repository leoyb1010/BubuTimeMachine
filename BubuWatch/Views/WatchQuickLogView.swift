import SwiftUI
import WatchKit

// MARK: - 一键打卡（喝奶 / 睡觉 / 喝水 / 换尿布）
struct WatchQuickLogView: View {
    @Environment(WatchConnector.self) private var connector

    // healthKindRaw 对应 iOS 端 HealthRecordKind.rawValue；换尿布无健康类型，走文字记录。
    private let items: [QuickLogItem] = [
        .init(emoji: "🍼", title: "喝奶", kind: "meal", tint: WatchTheme.rose),
        .init(emoji: "😴", title: "睡觉", kind: "sleep", tint: WatchTheme.lav),
        .init(emoji: "💧", title: "喝水", kind: "water", tint: WatchTheme.sky),
        .init(emoji: "🧷", title: "换尿布", kind: nil, tint: WatchTheme.mint)
    ]
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { item in
                    Button {
                        log(item)
                        WKInterfaceDevice.current().play(.success)
                    } label: {
                        VStack(spacing: 4) {
                            Text(item.emoji).font(.system(size: 30))
                            Text(item.title)
                                .font(.system(size: 13, weight: .black, design: .rounded))
                        }
                        .frame(maxWidth: .infinity, minHeight: 70)
                    }
                    .buttonStyle(.plain)
                    .background(item.tint.opacity(0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("打卡")
        .containerBackground(WatchTheme.mint.opacity(0.18).gradient, for: .tabView)
    }

    private func log(_ item: QuickLogItem) {
        if let kind = item.kind {
            connector.sendHealth(kindRaw: kind, title: item.title)
        } else {
            connector.sendText("\(item.emoji) \(item.title)了")
        }
    }
}

private struct QuickLogItem: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let kind: String?
    let tint: Color
}
