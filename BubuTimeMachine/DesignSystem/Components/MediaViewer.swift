import SwiftUI
import AVKit

// MARK: - 媒体相册查看器
struct MediaGalleryViewer: View {
    let mediaItems: [Media]
    let initialMediaID: UUID
    let mediaStore: MediaStore
    var onDismiss: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var selectedID: UUID

    init(mediaItems: [Media], initialMediaID: UUID, mediaStore: MediaStore, onDismiss: @escaping () -> Void) {
        self.mediaItems = mediaItems
        self.initialMediaID = initialMediaID
        self.mediaStore = mediaStore
        self.onDismiss = onDismiss
        _selectedID = State(initialValue: initialMediaID)
    }

    private var selectedIndex: Int {
        mediaItems.firstIndex(where: { $0.id == selectedID }) ?? 0
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if mediaItems.isEmpty {
                ContentUnavailableView("没有可查看的媒体", systemImage: "photo")
                    .foregroundStyle(.white)
            } else {
                // 用 UIKit UIPageViewController 翻页（系统相册同款）：翻页对齐由系统保证，
                // 彻底避免 SwiftUI TabView(.page) 套可缩放 UIScrollView 时「滑一半卡住」的老问题。
                PhotoPager(mediaItems: mediaItems, mediaStore: mediaStore,
                           selectedID: $selectedID, env: env)
                    .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .accessibilityLabel("关闭")
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Spacer()

                if mediaItems.count > 1 {
                    Text("\(selectedIndex + 1) / \(mediaItems.count) · 左右滑动")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.42), in: Capsule())
                        .padding(.bottom, 18)
                }
            }
            .overlay(alignment: .bottom) {
                if mediaItems.count == 1 {
                    Text("双击或捏合可放大")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.86))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.36), in: Capsule())
                        .padding(.bottom, 18)
                }
            }
        }
    }
}

// MARK: - UIKit 翻页容器（替代 SwiftUI TabView.page，翻页对齐可靠）
private final class MediaHostingController: UIHostingController<AnyView> {
    let mediaID: UUID
    init(mediaID: UUID, rootView: AnyView) {
        self.mediaID = mediaID
        super.init(rootView: rootView)
        view.backgroundColor = .clear
    }
    @MainActor required dynamic init?(coder aDecoder: NSCoder) { fatalError("init(coder:) unavailable") }
}

private struct PhotoPager: UIViewControllerRepresentable {
    let mediaItems: [Media]
    let mediaStore: MediaStore
    @Binding var selectedID: UUID
    let env: AppEnvironment

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pager = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 20]     // 页间留白，相邻图片不会露边
        )
        pager.dataSource = context.coordinator
        pager.delegate = context.coordinator
        pager.view.backgroundColor = .clear
        let start = mediaItems.firstIndex { $0.id == selectedID } ?? 0
        if !mediaItems.isEmpty {
            pager.setViewControllers([context.coordinator.controller(for: start)],
                                     direction: .forward, animated: false)
        }
        return pager
    }

    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        // 仅当外部改了 selectedID（与当前显示页不一致）才跳页；用户滑动引起的变更不会触发跳转。
        guard let current = pager.viewControllers?.first as? MediaHostingController,
              current.mediaID != selectedID,
              let target = mediaItems.firstIndex(where: { $0.id == selectedID }),
              let currentIdx = mediaItems.firstIndex(where: { $0.id == current.mediaID }) else { return }
        pager.setViewControllers([context.coordinator.controller(for: target)],
                                 direction: target > currentIdx ? .forward : .reverse, animated: true)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PhotoPager
        private var cache: [UUID: MediaHostingController] = [:]

        init(_ parent: PhotoPager) { self.parent = parent }

        func controller(for index: Int) -> MediaHostingController {
            let media = parent.mediaItems[index]
            if let cached = cache[media.id] { return cached }
            let root = AnyView(
                MediaPageView(media: media, mediaStore: parent.mediaStore)
                    .environment(parent.env)
            )
            let controller = MediaHostingController(mediaID: media.id, rootView: root)
            cache[media.id] = controller
            return controller
        }

        /// 只保留当前页 ±1 的控制器。每页持有一张 2400px 解码位图（15-25MB）+ 视频页的 AVPlayer，
        /// 不驱逐的话连续翻几百张相册内存线性涨到被系统杀。
        func evictFarPages(around id: UUID) {
            guard let center = parent.mediaItems.firstIndex(where: { $0.id == id }) else { return }
            let keep = Set((max(0, center - 1)...min(parent.mediaItems.count - 1, center + 1))
                .map { parent.mediaItems[$0].id })
            cache = cache.filter { keep.contains($0.key) }
        }

        private func index(of controller: UIViewController) -> Int? {
            guard let media = controller as? MediaHostingController else { return nil }
            return parent.mediaItems.firstIndex { $0.id == media.mediaID }
        }

        func pageViewController(_ pvc: UIPageViewController,
                                viewControllerBefore controller: UIViewController) -> UIViewController? {
            guard let i = index(of: controller), i > 0 else { return nil }
            return self.controller(for: i - 1)
        }

        func pageViewController(_ pvc: UIPageViewController,
                                viewControllerAfter controller: UIViewController) -> UIViewController? {
            guard let i = index(of: controller), i < parent.mediaItems.count - 1 else { return nil }
            return self.controller(for: i + 1)
        }

        func pageViewController(_ pvc: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            guard completed, let current = pvc.viewControllers?.first as? MediaHostingController else { return }
            parent.selectedID = current.mediaID
            evictFarPages(around: current.mediaID)
        }
    }
}

private struct MediaPageView: View {
    let media: Media
    let mediaStore: MediaStore

    var body: some View {
        switch media.type {
        case .photo:
            photoPage
        case .video:
            videoPage
        case .audio:
            audioPage
        }
    }

    @ViewBuilder
    private var photoPage: some View {
        if let name = media.localFileName {
            LocalZoomableImage(url: mediaStore.mediaURL(for: name))
                .ignoresSafeArea()
        } else if let remote = media.remoteURL {
            RemoteZoomableImage(remoteURL: remote)
                .ignoresSafeArea()
        } else {
            missing("本地照片文件找不到了")
        }
    }

    @ViewBuilder
    private var videoPage: some View {
        if let url = videoURL {
            StableVideoPlayer(url: url)
                .ignoresSafeArea(edges: .bottom)
        } else {
            missing("本地视频文件找不到了")
        }
    }

    private var videoURL: URL? {
        if let name = media.localFileName {
            let localURL = mediaStore.mediaURL(for: name)
            if FileManager.default.fileExists(atPath: localURL.path) {
                return localURL
            }
        }
        guard let remote = media.remoteURL else { return nil }
        return URL(string: remote)
    }

    private var audioPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 62))
                .foregroundStyle(.white.opacity(0.9))

            if let name = media.localFileName {
                VoicePlayerBubble(fileName: name,
                                  duration: media.durationSeconds ?? 0,
                                  waveform: [],
                                  mediaStore: mediaStore,
                                  tint: BubuTheme.Color.primary)
                    .padding()
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                Text("本地音频文件找不到了")
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding()
    }

    private func missing(_ text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 42))
            Text(text)
                .font(BubuTheme.Font.body)
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}

private struct LocalZoomableImage: View {
    let url: URL

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                ZoomableImageView(image: image)
            } else if didFail {
                ContentUnavailableView("照片文件无法解码", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: url) {
            didFail = false
            image = await Task.detached(priority: .userInitiated) {
                ThumbnailProvider.downsample(url: url, maxPixel: 2400)
            }.value
            didFail = image == nil
        }
    }
}

private struct StableVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: url) {
            player?.pause()
            player = AVPlayer(url: url)
        }
        .onDisappear {
            player?.pause()
        }
    }
}

/// 远端图片：必须走 APIClient.downloadFile（带 PocketBase 鉴权 + 401 重登重试），
/// 文件 collection 配了 viewRule 时裸 URLSession 会 403。失败态提供重试。
private struct RemoteZoomableImage: View {
    @Environment(AppEnvironment.self) private var env

    let remoteURL: String
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if let image {
                ZoomableImageView(image: image)
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 42))
                    Text(errorText ?? "照片还没下载好")
                        .font(BubuTheme.Font.body)
                    Button("重试") {
                        Task { await load() }
                    }
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.16), in: Capsule())
                }
                .foregroundStyle(.white.opacity(0.9))
            }
        }
        .task(id: remoteURL) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard !remoteURL.isEmpty, image == nil, !isLoading else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let tempURL = try await env.apiClient.downloadFileToTemporaryURL(from: remoteURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            guard let decoded = await Task.detached(priority: .userInitiated, operation: {
                ThumbnailProvider.downsample(url: tempURL, maxPixel: 2400)
            }).value else {
                errorText = "照片文件无法解码"
                return
            }
            image = decoded
        } catch {
            errorText = "照片下载失败，请稍后重试"
            #if DEBUG
            print("[MediaViewer] remote image failed:", remoteURL, error)
            #endif
        }
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomingImageScrollView {
        let view = ZoomingImageScrollView()
        view.setImage(image)
        return view
    }

    func updateUIView(_ uiView: ZoomingImageScrollView, context: Context) {
        uiView.setImage(image)
    }
}

/// 布局收敛到 layoutSubviews：首帧 bounds 为 0、旋转、分屏都会自动重排，黑屏根因消除。
final class ZoomingImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var lastImage: UIImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .clear
        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)

        // 未放大时禁用内层滚动，把横滑让给外层 TabView 翻页（否则内层平移手势与翻页抢滑，
        // 造成「一次滑半张、停在中间」）。放大后再启用以支持平移。缩放/双击手势不受影响。
        isScrollEnabled = false

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    /// 只有放大后才允许内层滚动（平移），原始大小时交给 TabView 翻页。
    private func updateScrollEnabled() {
        isScrollEnabled = zoomScale > minimumZoomScale + 0.01
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage) {
        guard lastImage !== image else {
            setNeedsLayout()
            return
        }
        lastImage = image
        imageView.image = image
        zoomScale = 1
        updateScrollEnabled()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutImageIfNeeded()
    }

    private func layoutImageIfNeeded() {
        guard let image = imageView.image,
              bounds.width > 0, bounds.height > 0,
              image.size.width > 0, image.size.height > 0 else { return }

        let fitScale = min(bounds.width / image.size.width,
                           bounds.height / image.size.height)
        let fittedSize = CGSize(width: image.size.width * fitScale,
                                height: image.size.height * fitScale)

        if zoomScale <= minimumZoomScale + 0.001 {
            imageView.frame = CGRect(origin: .zero, size: fittedSize)
            contentSize = fittedSize
        }
        centerImage()
    }

    private func centerImage() {
        let horizontal = max((bounds.width - contentSize.width) / 2, 0)
        let vertical = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal,
                                    bottom: vertical, right: horizontal)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        updateScrollEnabled()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.01 {
            setZoomScale(1, animated: true)
            return
        }
        let point = gesture.location(in: imageView)
        let targetScale = min(2.8, maximumZoomScale)
        let rect = CGRect(x: point.x - bounds.width / targetScale / 2,
                          y: point.y - bounds.height / targetScale / 2,
                          width: bounds.width / targetScale,
                          height: bounds.height / targetScale)
        zoom(to: rect, animated: true)
    }
}
