import SwiftUI

// MARK: - 媒体缩略图
/// 经 `ThumbnailProvider` 统一加载：内存缓存命中即返回、原图按显示档位降采样、缺缩略图后台落盘补齐。
/// 远端媒体由 SyncEngine 落地后走同一本地管线；未落地时显示呼吸占位。
struct MediaThumbnail: View {
    let media: Media
    let mediaStore: MediaStore
    var cornerRadius: CGFloat = BubuTheme.Radius.small
    var size: ThumbnailProvider.SizeClass = .card

    @Environment(AppEnvironment.self) private var env
    @State private var image: UIImage?
    @State private var pulse = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
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
        // remoteURL 在视图出现后才同步到位时也要启动呼吸动画（onAppear 只跑一次）
        .onChange(of: isAwaitingRemote) { _, awaiting in
            if awaiting { pulse = true }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(BubuTheme.Color.cream)
            .overlay {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 28))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            // 远端尚未落地：呼吸闪烁提示「正在取」。
            .opacity(isAwaitingRemote ? (pulse ? 0.55 : 1.0) : 1.0)
            .animation(isAwaitingRemote ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                       value: pulse)
            .onAppear { if isAwaitingRemote { pulse = true } }
    }

    /// 本地无文件但有远端 URL：等 SyncEngine 下载落地。
    private var isAwaitingRemote: Bool {
        media.localFileName == nil && media.remoteURL != nil
    }

    private var placeholderSymbol: String {
        switch media.type {
        case .photo: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        }
    }

    private func load() async {
        image = await env.thumbnails.image(
            mediaId: media.id,
            thumbnailFileName: media.thumbnailFileName,
            localFileName: media.localFileName,
            isPhoto: media.type == .photo,
            size: size
        )
    }
}
