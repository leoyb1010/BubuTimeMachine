import SwiftUI

// MARK: - Ken Burns 成长电影播放器
/// 把某一岁的真实照片串成会动的幻灯片：缓慢缩放平移 + 交叉淡入 + 旁白字幕。
/// 端侧零依赖即可"放电影"；正式部署时可替换为服务端 ffmpeg 成片。
struct GrowthMoviePlayer: View {
    let mediaFiles: [String]            // 沙盒图片文件名，按时间排序
    let captions: [String]             // 每张配的旁白（可少于图片数）
    let title: String
    let mediaStore: MediaStore
    var tint: Color = BubuTheme.Color.primary
    var onClose: () -> Void

    @State private var index = 0
    @State private var zoomIn = true
    @State private var isPlaying = true
    @State private var progress: Double = 0
    @State private var timer: Timer?

    private let perSlide: Double = 3.2

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 当前帧
            if mediaFiles.indices.contains(index),
               let data = mediaStore.data(forMedia: mediaFiles[index]),
               let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(zoomIn ? 1.18 : 1.0)
                    .animation(.easeInOut(duration: perSlide), value: zoomIn)
                    .animation(.easeInOut(duration: perSlide), value: index)
                    .id(index)
                    .transition(.opacity)
                    .ignoresSafeArea()
            } else {
                // 没有照片时的优雅降级
                LinearGradient(colors: [tint, tint.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .overlay { Text("🎬").font(.system(size: 80)) }
            }

            // 暗角 + 字幕
            VStack {
                topBar
                Spacer()
                caption
                progressBar
            }
            .padding()
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
        .onTapGesture { togglePlay() }
    }

    private var topBar: some View {
        HStack {
            Text(title)
                .font(BubuTheme.Font.headline)
                .foregroundStyle(.white)
                .shadow(radius: 4)
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            }
        }
    }

    @ViewBuilder
    private var caption: some View {
        if captions.indices.contains(index), !captions[index].isEmpty {
            Text(captions[index])
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.6), radius: 6)
                .padding(.horizontal, 20)
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
        .padding(.top, 8)
    }

    private var overallProgress: Double {
        guard !mediaFiles.isEmpty else { return 0 }
        return (Double(index) + progress) / Double(mediaFiles.count)
    }

    private func startTimer() {
        zoomIn = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
    }

    private func tick() {
        guard isPlaying else { return }
        progress += 0.05 / perSlide
        if progress >= 1 {
            advance()
        }
    }

    private func advance() {
        progress = 0
        if index < mediaFiles.count - 1 {
            withAnimation { index += 1 }
            zoomIn.toggle()    // 交替缩放方向，更有运动感
        } else {
            isPlaying = false
            timer?.invalidate()
        }
    }

    private func togglePlay() {
        isPlaying.toggle()
        if isPlaying && index >= mediaFiles.count - 1 && progress >= 1 {
            // 已播完 → 从头再放
            index = 0; progress = 0; isPlaying = true
        }
    }
}
