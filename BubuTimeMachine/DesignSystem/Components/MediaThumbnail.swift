import SwiftUI

// MARK: - 媒体缩略图
/// 从沙盒加载缩略图（优先）或原图，异步解码，失败时显示占位。
struct MediaThumbnail: View {
    let media: Media
    let mediaStore: MediaStore
    var cornerRadius: CGFloat = BubuTheme.Radius.small

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let remote = media.remoteURL, let url = URL(string: remote), media.type == .photo {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: placeholder
                    }
                }
            } else {
                placeholder
            }

            // 视频/音频角标
            if media.type != .photo {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: media.type == .video ? "play.circle.fill" : "waveform")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                        Spacer()
                    }
                }
                .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipped()
        .task(id: media.id) { await load() }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(BubuTheme.Color.cream)
            .overlay {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 28))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
    }

    private var placeholderSymbol: String {
        switch media.type {
        case .photo: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        }
    }

    private func load() async {
        let store = mediaStore
        let thumbName = media.thumbnailFileName
        let mediaName = media.localFileName
        let loaded: UIImage? = await Task.detached(priority: .userInitiated) {
            if let thumbName,
               let data = try? Data(contentsOf: store.thumbnailURL(for: thumbName)),
               let img = UIImage(data: data) {
                return img
            }
            if let mediaName,
               let data = store.data(forMedia: mediaName),
               let img = UIImage(data: data) {
                return img
            }
            return nil
        }.value
        await MainActor.run { self.image = loaded }
    }
}
