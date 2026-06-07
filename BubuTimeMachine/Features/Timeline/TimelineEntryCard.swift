import SwiftUI

// MARK: - 时光轴卡片
/// 一条 Entry 的卡片：媒体缩略图网格 + 日期 + 备注摘要 + 同步状态。
struct TimelineEntryCard: View {
    let entry: Entry
    let mediaStore: MediaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !entry.media.isEmpty {
                mediaGrid
            }

            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(BubuTheme.Font.body)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineLimit(3)
            }

            footer
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var header: some View {
        HStack {
            Text(entry.happenedAt.formatted(date: .abbreviated, time: .shortened))
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            Spacer()
            Text(entry.authorRole)
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(BubuTheme.Color.primary.opacity(0.12), in: Capsule())
        }
    }

    private var mediaGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(entry.media.prefix(9)) { media in
                MediaThumbnail(media: media, mediaStore: mediaStore)
                    .aspectRatio(1, contentMode: .fill)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: syncSymbol)
                .font(.system(size: 12))
            Text(entry.syncState.friendlyText)
                .font(BubuTheme.Font.caption)
        }
        .foregroundStyle(BubuTheme.Color.secondaryText)
    }

    private var syncSymbol: String {
        switch entry.syncState {
        case .local:     return "iphone"
        case .uploading: return "arrow.up.circle"
        case .synced:    return "checkmark.icloud"
        case .failed:    return "exclamationmark.circle"
        }
    }
}
