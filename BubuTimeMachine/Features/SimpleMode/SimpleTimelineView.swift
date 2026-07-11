import SwiftUI
import SwiftData

// MARK: - 简单模式 · 看布布
/// 给长辈看的极简时光轴：一条记录一张大图，大字日期，点一下全屏看。只读，不做编辑/删除，避免误操作。
struct SimpleTimelineView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Entry> { !$0.isArchived },
           sort: \Entry.happenedAt, order: .reverse)
    private var entries: [Entry]
    @Query private var profiles: [ChildProfile]

    @State private var viewer: ViewerTarget?

    private var childName: String { profiles.first?.name ?? env.config.childName }

    var body: some View {
        ZStack(alignment: .top) {
            BubuTheme.Color.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 18) {
                    Color.clear.frame(height: 68)   // 顶栏占位
                    if entries.isEmpty {
                        emptyState
                    } else {
                        ForEach(entries) { entry in
                            entryCard(entry)
                        }
                    }
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
            }

            topBar
        }
        .fullScreenCover(item: $viewer) { target in
            MediaGalleryViewer(mediaItems: target.media,
                               initialMediaID: target.initialID,
                               mediaStore: env.mediaStore) { viewer = nil }
        }
    }

    private var topBar: some View {
        HStack {
            Text("\(childName)的时光")
                .font(BubuTheme.Font.scaled(24, weight: .black))
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Spacer()
            Button {
                BubuHaptics.tapLight()
                dismiss()
            } label: {
                Text("关闭")
                    .font(BubuTheme.Font.scaled(18, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(BubuTheme.Color.primary, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(BubuTheme.Color.background.opacity(0.96))
    }

    @ViewBuilder
    private func entryCard(_ entry: Entry) -> some View {
        let photos = entry.media.filter { $0.type == .photo || $0.type == .video }
        let voice = entry.voiceNotes.first { $0.localFileName != nil }
        // 有照片/视频 → 整卡可点看大图；纯语音/纯文字 → 不可点（用语音气泡自己的播放按钮）。
        if let first = photos.first {
            Button {
                viewer = ViewerTarget(media: photos, initialID: first.id)
            } label: { cardBody(entry, cover: first, voice: voice) }
            .buttonStyle(.plain)
        } else {
            cardBody(entry, cover: nil, voice: voice)
        }
    }

    private func cardBody(_ entry: Entry, cover: Media?, voice: VoiceNote?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cover {
                MediaThumbnail(media: cover, mediaStore: env.mediaStore,
                               cornerRadius: 22, size: .card)
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
            Text(BubuDateFormat.longDate(entry.happenedAt))
                .font(BubuTheme.Font.scaled(16, weight: .bold))
                .foregroundStyle(BubuTheme.Color.deepRose)
            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(BubuTheme.Font.scaled(20, weight: .semibold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
            }
            // 语音条目：给出可播放气泡（否则「说一段」录的话在这里既看不到也听不到）。
            if let voice, let fileName = voice.localFileName {
                VoicePlayerBubble(fileName: fileName, duration: voice.durationSeconds,
                                  waveform: voice.waveformSamples, mediaStore: env.mediaStore)
            }
            // 纯语音且无文字时给一句说明，避免只剩一行日期。
            if cover == nil, (entry.note?.isEmpty ?? true), voice != nil {
                Text("一段说给\(childName)的话")
                    .font(BubuTheme.Font.scaled(17, weight: .semibold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🍼").font(.system(size: 60))
            Text("还没有记录")
                .font(BubuTheme.Font.scaled(22, weight: .black))
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text("回去点「拍一张」，\n给\(childName)留下第一张照片吧")
                .font(BubuTheme.Font.scaled(17, weight: .bold))
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 80)
    }
}

private struct ViewerTarget: Identifiable {
    let id = UUID()
    let media: [Media]
    let initialID: UUID
}
