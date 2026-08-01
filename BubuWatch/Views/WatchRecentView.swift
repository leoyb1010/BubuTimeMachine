import SwiftUI
import UIKit

// MARK: - 最近时光（iPhone 推来的几条）
/// 有照片的记录带 52pt 圆角缩略图；进场卡片依次浮起（scrollTransition）。
struct WatchRecentView: View {
    @Environment(WatchConnector.self) private var connector

    private var recent: [WatchRecent] { connector.snapshot?.recent ?? [] }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if recent.isEmpty {
                    emptyState
                } else {
                    ForEach(recent) { item in
                        row(item)
                            .scrollTransition { view, phase in
                                view.opacity(phase.isIdentity ? 1 : 0.4)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.92)
                            }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("最近")
        .background(WatchSpaceBackground(accent: WatchTheme.sky))
    }

    private func row(_ item: WatchRecent) -> some View {
        HStack(spacing: 8) {
            if let name = item.photoFileName,
               let data = WatchPhotoStore.data(for: name),
               let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text(item.moodEmoji ?? "✨")
                    .font(.system(size: 20))
                    .frame(width: 34)
            }
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
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("🌱").font(.system(size: 34))
            Text("还没有记录\n打开手机上的布布时光机就好")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 30)
    }
}
