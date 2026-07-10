import SwiftUI

// MARK: - 最近时光（iPhone 推来的几条）
struct WatchRecentView: View {
    @Environment(WatchConnector.self) private var connector

    private var recent: [WatchRecent] { connector.snapshot?.recent ?? [] }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if recent.isEmpty {
                    VStack(spacing: 6) {
                        Text("🌱").font(.system(size: 34))
                        Text("还没有记录\n去「记录」页留下第一条")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 30)
                } else {
                    ForEach(recent) { item in
                        HStack(spacing: 8) {
                            Text(item.moodEmoji ?? "✨").font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.dateText)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(WatchTheme.rose)
                                Text(item.note)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("最近")
        .containerBackground(WatchTheme.lav.opacity(0.18).gradient, for: .tabView)
    }
}
