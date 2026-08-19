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
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var galleryMedia: [Media] { items.map(\.media) }

    /// 每批追加数量：宽屏列数多、一屏装得下更多，步长同步放大。
    private var pageStep: Int { BubuAdaptive.value(sizeClass, compact: 90, regular: 180) }

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
                // 自适应列数：固定 3 列在 iPad 上每张缩略图会涨到 336pt 见方（照片墙变"三张巨图"）。
                // 用 adaptive 让 iPhone 保持 3 列、iPad 自然排到 6-8 列。
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 4)], spacing: 4) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                        Button {
                            viewerRoute = MediaViewerRoute(initialMediaID: item.media.id)
                        } label: {
                            MediaThumbnail(media: item.media, mediaStore: env.mediaStore,
                                           cornerRadius: BubuTheme.Radius.xs, size: .grid)
                                .aspectRatio(1, contentMode: .fit)
                                .clipped()
                        }
                        .buttonStyle(.plain)
                        // 哨兵挂在【倒数第 12 个真实 cell】上：LazyVGrid 只在 cell 真正滚到
                        // 视口附近才触发 onAppear——之前独立 ProgressView 随 ScrollView 立即
                        // 渲染只加一次，大相册永远卡在 180 张（R4 P2-21）
                        // 分页步长随列数放大：宽屏一屏容量翻倍，仍按 90 追加会频繁触发、滚动发涩
                        .onAppear {
                            if index >= visible.count - pageStep / 6, visibleCount < items.count {
                                visibleCount += pageStep
                            }
                        }
                    }
                }
                .padding(8)

                if visibleCount < items.count {
                    // 再加载一屏时用骨架占位而不是转圈：格子形状是已知的，
                    // 骨架能让网格保持连续、不在滚动中忽然塌一块。
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 4)], spacing: 4) {
                        ForEach(0..<6, id: \.self) { _ in
                            BubuSkeletonBlock(cornerRadius: BubuTheme.Radius.xs)
                                .aspectRatio(1, contentMode: .fill)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, BubuTheme.Spacing.m)
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
