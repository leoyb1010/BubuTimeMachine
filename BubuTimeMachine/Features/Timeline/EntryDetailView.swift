import SwiftUI
import SwiftData

// MARK: - 记录详情
/// 媒体 + 父母视角 + （预留）第一人称 + 家人合奏。
struct EntryDetailView: View {
    @Bindable var entry: Entry
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                mediaSection
                metaSection
                if let note = entry.note, !note.isEmpty {
                    parentVoiceSection(note)
                }
                firstPersonPlaceholder
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle(entry.happenedAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var mediaSection: some View {
        if !entry.media.isEmpty {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(entry.media) { media in
                    MediaThumbnail(media: media, mediaStore: env.mediaStore,
                                   cornerRadius: BubuTheme.Radius.card)
                        .aspectRatio(1, contentMode: .fill)
                }
            }
        }
    }

    private var metaSection: some View {
        HStack(spacing: 16) {
            Label(entry.authorRole, systemImage: "person.fill")
            if let place = entry.locationName {
                Label(place, systemImage: "mappin.and.ellipse")
            }
            Label(entry.happenedAt.formatted(date: .omitted, time: .shortened),
                  systemImage: "clock")
        }
        .font(BubuTheme.Font.caption)
        .foregroundStyle(BubuTheme.Color.secondaryText)
    }

    private func parentVoiceSection(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("此刻的记录")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text(note)
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.warmBrown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var firstPersonPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("布布第一人称日记", systemImage: "sparkles")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.primary)
            Text(entry.firstPersonNote ?? "等连上家里的服务器，AI 会把这一刻改写成布布自己的话。")
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(BubuTheme.Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }
}
