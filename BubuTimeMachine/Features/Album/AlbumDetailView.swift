import SwiftUI

// MARK: - 相册详情
/// 三列网格，点图直接全屏查看器（与照片墙一致，不绕记录详情）。
struct AlbumDetailView: View {
    let title: String
    let items: [AlbumMediaItem]

    @Environment(AppEnvironment.self) private var env
    @State private var viewerRoute: MediaViewerRoute?

    private var galleryMedia: [Media] { items.map(\.media) }

    var body: some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView("这个相册还是空的", systemImage: "photo")
                    .padding(.top, 80)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(items) { item in
                        Button {
                            viewerRoute = MediaViewerRoute(initialMediaID: item.media.id)
                        } label: {
                            MediaThumbnail(media: item.media, mediaStore: env.mediaStore,
                                           cornerRadius: 8, size: .grid)
                                .aspectRatio(1, contentMode: .fit)
                                .clipped()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
        .fullScreenCover(item: $viewerRoute) { route in
            MediaGalleryViewer(mediaItems: galleryMedia,
                               initialMediaID: route.initialMediaID,
                               mediaStore: env.mediaStore) {
                viewerRoute = nil
            }
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
