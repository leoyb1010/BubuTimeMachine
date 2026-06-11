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
        } else if let remote = media.remoteURL,
                  let url = URL(string: remote) {
            RemoteZoomableImage(url: url)
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

private struct RemoteZoomableImage: View {
    let url: URL
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                ZoomableImageView(image: image)
            } else if failed {
                VStack(spacing: 12) {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 42))
                    Text("照片还没下载好")
                        .font(BubuTheme.Font.body)
                }
                .foregroundStyle(.white.opacity(0.85))
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: url) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        failed = false
        image = nil
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let decoded = UIImage(data: data) else {
                failed = true
                return
            }
            image = decoded
        } catch {
            failed = true
        }
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.decelerationRate = .fast

        let imageView = context.coordinator.imageView
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        context.coordinator.scrollView = scrollView

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.set(image: image, in: scrollView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        weak var scrollView: UIScrollView?
        private var currentImage: UIImage?

        func set(image: UIImage, in scrollView: UIScrollView) {
            if currentImage !== image {
                currentImage = image
                imageView.image = image
                scrollView.zoomScale = 1
            }
            layoutImage(in: scrollView)
        }

        private func layoutImage(in scrollView: UIScrollView) {
            guard let image = imageView.image,
                  scrollView.bounds.width > 0,
                  scrollView.bounds.height > 0 else { return }

            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }

            let widthScale = scrollView.bounds.width / imageSize.width
            let heightScale = scrollView.bounds.height / imageSize.height
            let fitScale = min(widthScale, heightScale)
            let fittedSize = CGSize(width: imageSize.width * fitScale,
                                    height: imageSize.height * fitScale)

            if scrollView.zoomScale == 1 {
                imageView.frame = CGRect(origin: .zero, size: fittedSize)
                scrollView.contentSize = fittedSize
            }
            centerContent(in: scrollView)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(in: scrollView)
        }

        private func centerContent(in scrollView: UIScrollView) {
            let horizontalInset = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
            let verticalInset = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(top: verticalInset,
                                                   left: horizontalInset,
                                                   bottom: verticalInset,
                                                   right: horizontalInset)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }

            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: true)
                return
            }

            let targetScale = min(2.6, scrollView.maximumZoomScale)
            let point = gesture.location(in: imageView)
            let width = scrollView.bounds.width / targetScale
            let height = scrollView.bounds.height / targetScale
            let rect = CGRect(x: point.x - width / 2,
                              y: point.y - height / 2,
                              width: width,
                              height: height)
            scrollView.zoom(to: rect, animated: true)
        }
    }
}
