import SwiftUI
import AVKit

// MARK: - 媒体查看器
struct MediaViewer: View {
    let media: Media
    let mediaStore: MediaStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch media.type {
        case .photo:
            if let name = media.localFileName,
               let data = mediaStore.data(forMedia: name),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else if let remote = media.remoteURL, let url = URL(string: remote) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit().padding()
                    default: ProgressView().tint(.white)
                    }
                }
            } else {
                missing("本地照片文件找不到了")
            }
        case .video:
            if let name = media.localFileName {
                let url = mediaStore.mediaURL(for: name)
                if FileManager.default.fileExists(atPath: url.path) {
                    VideoPlayer(player: AVPlayer(url: url))
                        .ignoresSafeArea(edges: .bottom)
                } else if let remote = media.remoteURL, let remoteURL = URL(string: remote) {
                    VideoPlayer(player: AVPlayer(url: remoteURL))
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    missing("本地视频文件找不到了")
                }
            } else {
                missing("本地视频文件找不到了")
            }
        case .audio:
            if let name = media.localFileName {
                VoicePlayerBubble(fileName: name, duration: media.durationSeconds ?? 0,
                                  waveform: [], mediaStore: mediaStore, tint: BubuTheme.Color.primary)
                    .padding()
                    .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                    .padding()
            } else {
                missing("本地音频文件找不到了")
            }
        }
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
