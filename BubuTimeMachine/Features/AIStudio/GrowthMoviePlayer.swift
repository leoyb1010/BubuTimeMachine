import SwiftUI
import ImageIO

// MARK: - Ken Burns 成长电影播放器
/// 把真实照片串成会动的幻灯片：模板片头 + 缓慢缩放平移 + 字幕 + 可关闭/重播。
/// 性能：原图经 ImageIO 降采样后展示（不在主线程解码全尺寸原图），并预载下一张。
struct GrowthMoviePlayer: View {
    let draft: MovieDraft
    let mediaStore: MediaStore
    var tint: Color = BubuTheme.Color.primary
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var zoomIn = true
    @State private var isPlaying = true
    @State private var progress: Double = 0
    @State private var showIntro = true
    @State private var timer: Timer?
    @State private var slideImages: [Int: UIImage] = [:]

    private var perSlide: Double { draft.template == .daily ? 2.3 : 3.2 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            currentSlide

            if showIntro { introOverlay }

            VStack {
                topBar
                Spacer()
                if !showIntro { caption }
                progressBar
            }
            .padding()
            .zIndex(3)

            if isFinished { finishOverlay }
        }
        .contentShape(Rectangle())
        .onAppear {
            startTimer()
            Task { await loadImages(around: 0) }
        }
        .onChange(of: index) { _, newIndex in
            Task { await loadImages(around: newIndex) }
        }
        .onDisappear { timer?.invalidate() }
        .onTapGesture { if !isFinished { togglePlay() } }
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                if abs(value.translation.height) > 90 || abs(value.translation.width) > 120 { onClose() }
            }
        )
    }

    @ViewBuilder
    private var currentSlide: some View {
        if let ui = slideImages[index] {
            ZStack {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .brightness(-0.42)
                    .saturation(0.85)
                    .ignoresSafeArea()
                    .overlay(.black.opacity(0.18))
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(reduceMotion ? 1.0 : (zoomIn ? 1.045 : 1.0))
                    .offset(x: reduceMotion ? 0 : panOffset)
                    .padding(.horizontal, 18)
                    .padding(.top, 104)
                    .padding(.bottom, 150)
                    .animation(.easeInOut(duration: perSlide), value: zoomIn)
                    .animation(.easeInOut(duration: perSlide), value: index)
                    .id(index)
                    .transition(.opacity)
                    .shadow(color: .black.opacity(0.42), radius: 22, y: 8)
            }
        } else {
            LinearGradient(colors: [tint, tint.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .overlay { Text("🎬").font(.system(size: 80)) }
        }
    }

    /// Ken Burns 平移：逐张交替左右缓移，配合缩放更像「镜头在动」。
    private var panOffset: CGFloat {
        let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
        return (zoomIn ? 9 : -9) * direction
    }

    /// 当前张 + 前后邻张降采样预载；远处的释放，控住内存峰值。
    private func loadImages(around center: Int) async {
        for i in [center, center + 1, center - 1] where draft.mediaFiles.indices.contains(i) {
            guard slideImages[i] == nil else { continue }
            let url = mediaStore.mediaURL(for: draft.mediaFiles[i])
            let image = await Task.detached(priority: .userInitiated) {
                Self.downsampledImage(url: url, maxPixel: 1600)
            }.value
            if let image { slideImages[i] = image }
        }
        slideImages = slideImages.filter { abs($0.key - center) <= 1 }
    }

    nonisolated private static func downsampledImage(url: URL, maxPixel: CGFloat) -> UIImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOpts) else { return nil }
        let thumbOpts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts) else { return nil }
        return UIImage(cgImage: cg)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(radius: 4)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.title)
                    .font(BubuTheme.Font.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(draft.template.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
            }
            Spacer()
        }
    }

    private var introOverlay: some View {
        VStack(spacing: 14) {
            Text(draft.template.emoji).font(.system(size: 68))
            Text(draft.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(draft.template.title)
                .font(BubuTheme.Font.headline)
                .foregroundStyle(.white.opacity(0.86))
        }
        .padding(28)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding()
        .transition(.opacity)
        .zIndex(2)
    }

    @ViewBuilder
    private var caption: some View {
        if draft.captions.indices.contains(index), !draft.captions[index].isEmpty {
            Text(draft.captions[index])
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.55), radius: 4)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
                .transition(.opacity)
                .id("cap\(index)")
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white)
                    .frame(width: geo.size.width * overallProgress)
            }
        }
        .frame(height: 4)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var finishOverlay: some View {
        VStack(spacing: 14) {
            Text("放完啦")
                .font(BubuTheme.Font.title)
                .foregroundStyle(.white)
            HStack(spacing: 12) {
                Button { replay() } label: {
                    Label("重播", systemImage: "gobackward")
                        .font(BubuTheme.Font.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(tint, in: Capsule())
                }
                Button { onClose() } label: {
                    Text("关闭")
                        .font(BubuTheme.Font.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(.white.opacity(0.18), in: Capsule())
                }
            }
        }
        .padding(28)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var overallProgress: Double {
        guard !draft.mediaFiles.isEmpty else { return 0 }
        return (Double(index) + progress) / Double(draft.mediaFiles.count)
    }

    private var isFinished: Bool {
        !isPlaying && index >= draft.mediaFiles.count - 1 && progress >= 1
    }

    private func startTimer() {
        zoomIn = true
        showIntro = true
        timer?.invalidate()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(.easeOut(duration: 0.25)) { showIntro = false }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
    }

    private func tick() {
        guard isPlaying, !showIntro else { return }
        progress += 0.05 / perSlide
        if progress >= 1 { advance() }
    }

    private func advance() {
        if index < draft.mediaFiles.count - 1 {
            progress = 0
            withAnimation { index += 1 }
            zoomIn.toggle()
        } else {
            progress = 1
            isPlaying = false
            timer?.invalidate()
        }
    }

    private func togglePlay() { isPlaying.toggle() }

    private func replay() {
        index = 0
        progress = 0
        isPlaying = true
        startTimer()
    }
}
