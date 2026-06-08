import SwiftUI

// MARK: - Ken Burns 成长电影播放器
/// 把真实照片串成会动的幻灯片：模板片头 + 缓慢缩放 + 字幕 + 可关闭/重播。
struct GrowthMoviePlayer: View {
    let draft: MovieDraft
    let mediaStore: MediaStore
    var tint: Color = BubuTheme.Color.primary
    var onClose: () -> Void

    @State private var index = 0
    @State private var zoomIn = true
    @State private var isPlaying = true
    @State private var progress: Double = 0
    @State private var showIntro = true
    @State private var timer: Timer?

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

            if isFinished { finishOverlay }
        }
        .contentShape(Rectangle())
        .onAppear { startTimer() }
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
        if draft.mediaFiles.indices.contains(index),
           let data = mediaStore.data(forMedia: draft.mediaFiles[index]),
           let ui = UIImage(data: data) {
            ZStack {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 30)
                    .brightness(-0.30)
                    .ignoresSafeArea()
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoomIn ? 1.035 : 1.0)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 86)
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
                .lineLimit(3)
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
        .padding(.top, 8)
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
