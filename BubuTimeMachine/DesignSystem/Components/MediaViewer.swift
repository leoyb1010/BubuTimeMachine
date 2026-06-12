import SwiftUI
import AVKit

// MARK: - 媒体相册查看器
struct MediaGalleryViewer: View {
    let mediaItems: [Media]
    let initialMediaID: UUID
    let mediaStore: MediaStore
    var onDismiss: () -> Void

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
                TabView(selection: $selectedID) {
                    ForEach(mediaItems) { media in
                        MediaPageView(media: media, mediaStore: mediaStore)
                            .tag(media.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
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
                    Text("\(selectedIndex + 1) / \(mediaItems.count)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.42), in: Capsule())
                        .padding(.bottom, 18)
                }
            }
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
        if let name = media.localFileName,
           let data = mediaStore.data(forMedia: name),
           let image = UIImage(data: data) {
            ZoomableImageView(image: image)
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
        if let name = media.localFileName {
            let localURL = mediaStore.mediaURL(for: name)
            if FileManager.default.fileExists(atPath: localURL.path) {
                VideoPlayer(player: AVPlayer(url: localURL))
                    .ignoresSafeArea(edges: .bottom)
            } else if let remote = media.remoteURL,
                      let remoteURL = URL(string: remote) {
                VideoPlayer(player: AVPlayer(url: remoteURL))
                    .ignoresSafeArea(edges: .bottom)
            } else {
                missing("本地视频文件找不到了")
            }
        } else if let remote = media.remoteURL,
                  let remoteURL = URL(string: remote) {
            VideoPlayer(player: AVPlayer(url: remoteURL))
                .ignoresSafeArea(edges: .bottom)
        } else {
            missing("本地视频文件找不到了")
        }
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
            let data = try await env.apiClient.downloadFile(from: remoteURL)
            guard let decoded = UIImage(data: data) else {
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

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
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
