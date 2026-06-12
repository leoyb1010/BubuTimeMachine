import SwiftUI
import SwiftData

// MARK: - 布布的相册
/// 首页「张照片」入口的落地页：自动整理的系统相册（全部/最近/小视频/有地点/按月份/按月龄）。
struct AlbumHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt, order: .reverse)
    private var entries: [Entry]
    @Query private var profiles: [ChildProfile]

    private var theme: Color { env.theme.theme.primary }

    private var allItems: [AlbumMediaItem] {
        entries.flatMap { entry in
            entry.media
                .filter { $0.type == .photo || $0.type == .video }
                .sorted { $0.createdAt < $1.createdAt }
                .map { AlbumMediaItem(media: $0, entry: entry) }
        }
    }

    var body: some View {
        let items = allItems
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard

                if items.isEmpty {
                    emptyState
                } else {
                    let featured = SystemAlbumFactory.featured(from: items)
                    featuredRow(featured)

                    let monthly = SystemAlbumFactory.monthly(from: items)
                    if !monthly.isEmpty {
                        albumSection(title: "按月份", albums: monthly)
                    }

                    let byAge = SystemAlbumFactory.byAgeMonth(from: items, birthday: profiles.first?.birthday)
                    if !byAge.isEmpty {
                        albumSection(title: "按月龄", albums: byAge)
                    }
                }
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("布布的相册")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            BubuMascotBadge(size: 52, expression: .happy)
            VStack(alignment: .leading, spacing: 4) {
                Text("布布的相册")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("自动整理每一张长大的证据")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            Spacer()
        }
        .padding()
        .background(BubuTheme.Color.card.opacity(0.7), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuGlassSurface(cornerRadius: BubuTheme.Radius.card, tint: theme)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            BubuMascotBadge(size: 84, expression: .surprised)
            Text("还没有照片\n回首页点「记录此刻」拍下第一张吧")
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func featuredRow(_ albums: [SystemAlbum]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(albums) { album in
                    NavigationLink {
                        AlbumDetailView(title: album.title, items: album.items)
                    } label: {
                        featuredCard(album)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func featuredCard(_ album: SystemAlbum) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let cover = album.cover {
                    MediaThumbnail(media: cover.media, mediaStore: env.mediaStore,
                                   cornerRadius: 18, size: .card)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(theme.opacity(0.10))
                        .overlay {
                            Image(systemName: album.icon)
                                .font(.system(size: 30))
                                .foregroundStyle(theme)
                        }
                }
            }
            .frame(width: 150, height: 150)
            .clipped()

            HStack(spacing: 5) {
                Image(systemName: album.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme)
                Text(album.title)
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer()
                Text("\(album.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .frame(width: 150)
        }
    }

    private func albumSection(title: String, albums: [SystemAlbum]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
                ForEach(albums) { album in
                    NavigationLink {
                        AlbumDetailView(title: album.title, items: album.items)
                    } label: {
                        gridCard(album)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func gridCard(_ album: SystemAlbum) -> some View {
        HStack(spacing: 10) {
            Group {
                if let cover = album.cover {
                    MediaThumbnail(media: cover.media, mediaStore: env.mediaStore,
                                   cornerRadius: 12, size: .grid)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.opacity(0.10))
                }
            }
            .frame(width: 52, height: 52)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(album.title)
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineLimit(1)
                Text(album.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(BubuTheme.Color.card.opacity(0.68), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuGlassSurface(cornerRadius: BubuTheme.Radius.card, tint: theme, interactive: true)
    }
}
