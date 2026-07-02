import SwiftUI
import SwiftData
import PhotosUI

// MARK: - 记录详情（可编辑、可补充、家人合奏）
/// 已上传内容不再"只读"：可改文字/心情/时间、追加照片、追加语音、家人多视角补充。
struct EntryDetailView: View {
    @Bindable var entry: Entry
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [ChildProfile]

    @State private var editing = false
    @State private var appendPick: [PhotosPickerItem] = []
    @State private var showCommentSheet = false
    @State private var viewingMediaID: UUID?
    @State private var showDeleteConfirm = false
    @State private var appendMediaStatus: String?
    @State private var showReactionPicker = false
    @State private var storybookToast: String?

    private var profile: ChildProfile? { profiles.first }
    private var sortedMedia: [Media] {
        entry.media.sorted { $0.createdAt < $1.createdAt }
    }
    private var theme: Color { env.theme.theme.primary }
    private var timePerspectivePrefix: String {
        let months = Calendar.current.dateComponents([.month], from: entry.happenedAt, to: .now).month ?? 0
        return months <= 2 ? "此时" : "那时"
    }
    private var locationBinding: Binding<Bool> {
        Binding(
            get: { entry.locationName != nil || entry.latitude != nil || entry.longitude != nil },
            set: { keep in
                if !keep {
                    entry.locationName = nil
                    entry.latitude = nil
                    entry.longitude = nil
                    markEntryDirty()
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ageBadge
                if let appendMediaStatus { mediaStatusRow(appendMediaStatus) }
                mediaSection
                reactionSection
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
        .navigationTitle(BubuDateFormat.shortDate(entry.happenedAt))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing ? "完成" : "编辑") {
                    if editing {
                        markEntryDirty()
                        try? context.save()
                        refreshWidgets()
                        env.syncEngine.syncNow()
                    }
                    withAnimation(.smooth) { editing.toggle() }
                }
                .fontWeight(.semibold)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleStorybook()
                } label: {
                    Image(systemName: entry.inStorybook ? "book.fill" : "book")
                        .foregroundStyle(entry.inStorybook ? BubuTheme.Color.deepRose : BubuTheme.Color.warmBrown)
                }
                .accessibilityLabel(entry.inStorybook ? "移出绘本" : "收进绘本")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("删除记录")
            }
        }
        .overlay(alignment: .top) {
            if let storybookToast {
                Text(storybookToast)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(BubuTheme.Color.deepRose, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: appendPick) { _, items in Task { await appendMedia(items) } }
        .sheet(isPresented: $showCommentSheet) {
            CommentComposeSheet(entry: entry)
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewingMediaID != nil },
            set: { if !$0 { viewingMediaID = nil } }
        )) {
            if let id = viewingMediaID {
                MediaGalleryViewer(mediaItems: sortedMedia,
                                   initialMediaID: id,
                                   mediaStore: env.mediaStore) {
                    viewingMediaID = nil
                }
            }
        }
        .alert("删除这条记录？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) { deleteEntry() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后会从时光轴隐藏，本地记录会标记为待同步删除。")
        }
    }

    // MARK: 年龄角标

    @ViewBuilder
    private var ageBadge: some View {
        if let profile {
            HStack(spacing: 8) {
                Text("🎂")
                Text("\(timePerspectivePrefix)的布布 · \(AgeCalculator.ageDescription(birthday: profile.birthday, at: entry.happenedAt))")
                    .font(BubuTheme.Font.caption.weight(.semibold))
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
            let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(sortedMedia) { media in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            if !editing { viewingMediaID = media.id }
                        } label: {
                            MediaThumbnail(media: media, mediaStore: env.mediaStore,
                                           cornerRadius: BubuTheme.Radius.card)
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .clipped()
                        }
                        .buttonStyle(.plain)
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

    private func mediaStatusRow(_ text: String) -> some View {
        Label(text, systemImage: "arrow.triangle.2.circlepath")
            .font(BubuTheme.Font.caption)
            .foregroundStyle(theme)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(theme.opacity(0.08), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
    }

    // MARK: 亲一下（反应）

    private var reactionSummary: ReactionSummary {
        ReactionSummary.from(entry.comments, myRole: env.config.currentRole.rawValue)
    }

    private var reactionSection: some View {
        let summary = reactionSummary
        return HStack(spacing: 12) {
            Button {
                withAnimation(BubuMotion.quick) { showReactionPicker.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: summary.mine == nil ? "heart" : "heart.fill")
                        .foregroundStyle(summary.mine == nil ? BubuTheme.Color.secondaryText : theme)
                    Text(summary.mine?.label ?? "亲一下")
                        .font(BubuTheme.Font.caption.weight(.medium))
                        .foregroundStyle(summary.mine == nil ? BubuTheme.Color.secondaryText : theme)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(theme.opacity(summary.mine == nil ? 0.06 : 0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showReactionPicker, attachmentAnchor: .point(.top),
                     arrowEdge: .bottom) {
                ReactionPicker(current: summary.mine) { r in
                    toggleReaction(r)
                    showReactionPicker = false
                }
                .presentationCompactAdaptation(.popover)
                .padding(8)
            }
            ReactionRow(summary: summary)
            Spacer()
        }
    }

    /// 切换反应：同一人只保留一条；点已选的反应=取消。
    private func toggleReaction(_ r: Reaction) {
        let myRole = env.config.currentRole.rawValue
        let existing = entry.comments.filter { $0.authorRole == myRole && Reaction.isReaction($0) }
        let already = ReactionSummary.from(entry.comments, myRole: myRole).mine == r
        for c in existing {
            PendingDeletion.enqueue(collection: "comments", remoteId: c.remoteId, in: context)
            context.delete(c)
        }
        if !already {
            let comment = Comment(authorRole: myRole, text: r.encodedText)
            comment.entry = entry
            context.insert(comment)
            context.insert(FeedEvent(kind: .commentAdded, actorRole: myRole,
                                     summary: "\(myRole) \(r.label)了这一刻 \(r.rawValue)",
                                     targetLocalId: entry.id.uuidString))
            BubuHaptics.selection()
        }
        try? context.save()
        refreshWidgets()
        env.syncEngine.syncNow()
    }



    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editing {
                DatePicker("发生时间", selection: $entry.happenedAt, displayedComponents: [.date, .hourAndMinute])
                    .font(BubuTheme.Font.body)
                MoodPicker(selection: $entry.mood, tint: theme)
                Toggle(isOn: locationBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("保存地点")
                            .font(BubuTheme.Font.caption.weight(.semibold))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text(entry.locationName ?? "关闭后会移除这条记录里的地点信息")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                }
                .tint(theme)
                .padding(12)
                .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
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
                    .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
            } else if let note = entry.note {
                Text(note)
                    .font(BubuTheme.Font.body)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .fixedSize(horizontal: false, vertical: true)
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
                        markEntryDirty()
                        context.insert(voice)
                        context.insert(FeedEvent(kind: .voiceAdded, actorRole: env.config.currentRole.rawValue,
                                                 summary: "补充了一段语音记录",
                                                 targetLocalId: entry.id.uuidString))
                        try? context.save()
                        refreshWidgets()
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
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme)
                .frame(width: 34, height: 34)
                .background(theme.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("布布第一人称日记")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(entry.firstPersonNote ?? "去 AI 工坊，把这一刻变成布布自己的话")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .padding(12)
        .background(theme.opacity(0.07), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
    }

    // MARK: 家人合奏

    private var familyEnsembleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("家人合奏", systemImage: "person.3.fill")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer()
                Button {
                    showCommentSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(theme)
                }
                .buttonStyle(.plain)
            }
            if entry.comments.filter({ !Reaction.isReaction($0) }).isEmpty {
                Text("还没有人补充。点 + 号，说说你的视角。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            } else {
                ForEach(entry.comments.filter { !Reaction.isReaction($0) }.sorted { $0.createdAt < $1.createdAt }) { comment in
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

    private func appendMedia(_ items: [PhotosPickerItem]) async {
        appendMediaStatus = items.isEmpty ? nil : "正在整理新照片/视频…"
        defer { appendMediaStatus = nil }
        for item in items {
            if let movie = try? await item.loadTransferable(type: MovieTransfer.self),
               let imported = try? await env.mediaStore.importVideoForSync(from: movie.url) {
                let fileName = imported.fileName
                let media = Media(type: .video, localFileName: fileName)
                if imported.wasCompressed {
                    media.aiTags = ["已压缩", "视频"]
                }
                media.thumbnailFileName = await env.mediaStore.makeVideoThumbnail(fromVideo: fileName)
                media.entry = entry
                context.insert(media)
                continue
            }
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
        markEntryDirty()
        try? context.save()
        refreshWidgets()
        env.syncEngine.syncNow()
    }

    private func deleteMedia(_ media: Media) {
        PendingDeletion.enqueue(collection: "media", remoteId: media.remoteId, in: context)
        env.mediaStore.deleteLocalFiles(media: media.localFileName, thumbnail: media.thumbnailFileName)
        context.delete(media)
        markEntryDirty()
        try? context.save()
        refreshWidgets()
        env.syncEngine.syncNow()
    }

    private func deleteVoice(_ voice: VoiceNote) {
        PendingDeletion.enqueue(collection: "voicenotes", remoteId: voice.remoteId, in: context)
        env.mediaStore.deleteLocalFiles(media: voice.localFileName)
        context.delete(voice)
        markEntryDirty()
        try? context.save()
        refreshWidgets()
        env.syncEngine.syncNow()
    }

    private func markEntryDirty() {
        entry.editedAt = .now
        entry.syncState = .local
    }

    /// 收进 / 移出成长绘本：切换标记、落库并同步，弹一条轻提示。
    private func toggleStorybook() {
        entry.inStorybook.toggle()
        markEntryDirty()
        try? context.save()
        env.syncEngine.syncNow()
        BubuHaptics.tapLight()
        withAnimation(.smooth) {
            storybookToast = entry.inStorybook ? "已收进绘本 📖" : "已移出绘本"
        }
        let shown = storybookToast
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.smooth) {
                if storybookToast == shown { storybookToast = nil }
            }
        }
    }

    private func refreshWidgets() {
        env.refreshWidgetSnapshot(context: context)
        WidgetRefresher.reload()
    }

    private func deleteEntry() {
        entry.isArchived = true
        markEntryDirty()
        context.insert(FeedEvent(kind: .entryArchived,
                                 actorRole: env.config.currentRole.rawValue,
                                 summary: "删除了一条时光轴记录",
                                 targetLocalId: entry.id.uuidString))
        try? context.save()
        refreshWidgets()
        env.syncEngine.syncNow()
        dismiss()
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
