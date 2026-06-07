import SwiftUI
import SwiftData
import PhotosUI

// MARK: - 记录详情（可编辑、可补充、家人合奏）
/// 已上传内容不再"只读"：可改文字/心情/时间、追加照片、追加语音、家人多视角补充。
struct EntryDetailView: View {
    @Bindable var entry: Entry
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query private var profiles: [ChildProfile]

    @State private var editing = false
    @State private var appendPick: [PhotosPickerItem] = []
    @State private var showCommentSheet = false

    private var profile: ChildProfile? { profiles.first }
    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                ageBadge
                mediaSection
                appendPhotoButton
                metaSection
                if entry.note != nil || editing { noteSection }
                voiceNotesSection
                tagsSection
                firstPersonPlaceholder
                familyEnsembleSection
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle(entry.happenedAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing ? "完成" : "编辑") {
                    if editing { entry.editedAt = .now; try? context.save() }
                    withAnimation(.smooth) { editing.toggle() }
                }
                .fontWeight(.semibold)
            }
        }
        .onChange(of: appendPick) { _, items in Task { await appendPhotos(items) } }
        .sheet(isPresented: $showCommentSheet) {
            CommentComposeSheet(entry: entry)
        }
    }

    // MARK: 年龄角标

    @ViewBuilder
    private var ageBadge: some View {
        if let profile {
            HStack(spacing: 8) {
                Text("🎂")
                Text("那时的布布 · \(AgeCalculator.ageDescription(birthday: profile.birthday, at: entry.happenedAt))")
                    .font(BubuTheme.Font.body.weight(.semibold))
                    .foregroundStyle(theme)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(theme.opacity(0.1), in: Capsule())
        }
    }

    // MARK: 媒体

    @ViewBuilder
    private var mediaSection: some View {
        if !entry.media.isEmpty {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(entry.media) { media in
                    ZStack(alignment: .topTrailing) {
                        MediaThumbnail(media: media, mediaStore: env.mediaStore,
                                       cornerRadius: BubuTheme.Radius.card)
                            .aspectRatio(1, contentMode: .fill)
                        if editing {
                            Button {
                                deleteMedia(media)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white, .red)
                                    .padding(6)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var appendPhotoButton: some View {
        if editing {
            let tint = theme
            PhotosPicker(selection: $appendPick, maxSelectionCount: 9,
                         matching: .any(of: [.images, .videos])) {
                Label("再添加照片/视频", systemImage: "plus.rectangle.on.rectangle")
                    .font(BubuTheme.Font.body)
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
            }
        }
    }

    // MARK: 元信息（时间/地点/心情/作者）

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editing {
                DatePicker("发生时间", selection: $entry.happenedAt, displayedComponents: [.date, .hourAndMinute])
                    .font(BubuTheme.Font.body)
                MoodPicker(selection: $entry.mood, tint: theme)
            } else {
                HStack(spacing: 16) {
                    Label(entry.authorRole, systemImage: "person.fill")
                    if let mood = entry.mood {
                        Text("\(mood.emoji) \(mood.rawValue)")
                    }
                    if let place = entry.locationName {
                        Label(place, systemImage: "mappin.and.ellipse")
                    }
                }
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("此刻的记录")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            if editing {
                TextField("此刻的布布……", text: Binding(
                    get: { entry.note ?? "" },
                    set: { entry.note = $0.isEmpty ? nil : $0 }), axis: .vertical)
                    .font(BubuTheme.Font.body)
                    .lineLimit(3...8)
                    .padding()
                    .background(.white, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
            } else if let note = entry.note {
                Text(note).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    // MARK: 语音记录

    @ViewBuilder
    private var voiceNotesSection: some View {
        if !entry.voiceNotes.isEmpty || editing {
            VStack(alignment: .leading, spacing: 10) {
                Label("语音记录", systemImage: "waveform")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                ForEach(entry.voiceNotes) { voice in
                    if let fileName = voice.localFileName {
                        HStack {
                            VoicePlayerBubble(fileName: fileName, duration: voice.durationSeconds,
                                              waveform: voice.waveformSamples, mediaStore: env.mediaStore, tint: theme)
                            Spacer()
                            Text(voice.authorRole).font(BubuTheme.Font.caption)
                                .foregroundStyle(BubuTheme.Color.secondaryText)
                            if editing {
                                Button { deleteVoice(voice) } label: {
                                    Image(systemName: "trash.circle.fill").font(.system(size: 22))
                                        .foregroundStyle(BubuTheme.Color.secondaryText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if editing {
                    VoiceRecorderBar(mediaStore: env.mediaStore) { fileName, duration, waveform in
                        let voice = VoiceNote(localFileName: fileName, durationSeconds: duration,
                                              authorRole: env.config.currentRole.rawValue, waveformSamples: waveform)
                        voice.entry = entry
                        context.insert(voice)
                        try? context.save()
                    }
                }
            }
        }
    }

    // MARK: AI 标签

    @ViewBuilder
    private var tagsSection: some View {
        let tags = Array(Set(entry.media.flatMap { $0.aiTags }))
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("自动识别", systemImage: "tag")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                FlowTags(tags: tags, tint: theme)
            }
        }
    }

    private var firstPersonPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("布布第一人称日记", systemImage: "sparkles")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(theme)
            Text(entry.firstPersonNote ?? "去「AI 工坊」，把这一刻改写成布布自己的话。")
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(theme.opacity(0.07), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    // MARK: 家人合奏

    private var familyEnsembleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("家人合奏", systemImage: "person.3.fill")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer()
                Button {
                    showCommentSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(theme)
                }
                .buttonStyle(.plain)
            }
            if entry.comments.isEmpty {
                Text("还没有人补充。点 + 号，从你的视角说说这一刻。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            } else {
                ForEach(entry.comments.sorted { $0.createdAt < $1.createdAt }) { comment in
                    commentRow(comment)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func commentRow(_ comment: Comment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(comment.authorRole)
                .font(BubuTheme.Font.caption.weight(.bold))
                .foregroundStyle(theme)
            if let text = comment.text, !text.isEmpty {
                Text(text).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
            }
            if let voiceFile = comment.voiceFileName {
                VoicePlayerBubble(fileName: voiceFile, duration: comment.voiceDuration,
                                  waveform: comment.voiceWaveform, mediaStore: env.mediaStore, tint: theme)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    // MARK: 操作

    private func appendPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let fileName = try? env.mediaStore.savePhoto(data) {
                let media = Media(type: .photo, localFileName: fileName)
                media.thumbnailFileName = env.mediaStore.makePhotoThumbnail(fromImage: image)
                media.entry = entry
                context.insert(media)
            }
        }
        appendPick = []
        entry.editedAt = .now
        try? context.save()
    }

    private func deleteMedia(_ media: Media) {
        context.delete(media)
        try? context.save()
    }

    private func deleteVoice(_ voice: VoiceNote) {
        context.delete(voice)
        try? context.save()
    }
}

// MARK: - 流式标签
struct FlowTags: View {
    let tags: [String]
    var tint: Color = BubuTheme.Color.primary

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text("# \(tag)")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(tint.opacity(0.1), in: Capsule())
            }
        }
    }
}
