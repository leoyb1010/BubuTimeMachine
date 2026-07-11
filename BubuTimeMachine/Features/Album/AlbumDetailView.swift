import SwiftUI

// MARK: - 相册详情
/// 三列网格，点图直接全屏查看器（与照片墙一致，不绕记录详情）。
struct AlbumDetailView: View {
    let title: String
    let items: [AlbumMediaItem]

    @Environment(AppEnvironment.self) private var env
    @State private var viewerRoute: MediaViewerRoute?
    /// 分批渲染：大相册（上千张）首屏只挂 90 个缩略图，滚到底自动追加。
    @State private var visibleCount = 90

    private var galleryMedia: [Media] { items.map(\.media) }

    var body: some View {
        ScrollView {
            if items.isEmpty {
                VStack(spacing: 14) {
                    BubuEmptyIllustration(assetName: "BubuEmptyAlbum", fallbackExpression: .surprised)
                    Text("这个相册还是空的")
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .padding(.top, 80)
            } else {
                let visible = Array(items.prefix(visibleCount))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                        Button {
                            viewerRoute = MediaViewerRoute(initialMediaID: item.media.id)
                        } label: {
                            MediaThumbnail(media: item.media, mediaStore: env.mediaStore,
                                           cornerRadius: 8, size: .grid)
                                .aspectRatio(1, contentMode: .fit)
                                .clipped()
                        }
                        .buttonStyle(.plain)
                        // 哨兵挂在【倒数第 12 个真实 cell】上：LazyVGrid 只在 cell 真正滚到
                        // 视口附近才触发 onAppear——之前独立 ProgressView 随 ScrollView 立即
                        // 渲染只加一次，大相册永远卡在 180 张（R4 P2-21）
                        .onAppear {
                            if index >= visible.count - 12, visibleCount < items.count {
                                visibleCount += 90
                            }
                        }
                    }
                }
                .padding(8)

                if visibleCount < items.count {
                    ProgressView().padding(.vertical, 16)
                }
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
