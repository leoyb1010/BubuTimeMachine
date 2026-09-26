import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct MemoryJournalComposer: View {
    private static var activeDrafts: Set<MemoryJournalKind> = []
    let kind: MemoryJournalKind
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var id = UUID()
    @State private var date = Date.now
    @State private var words = ""
    @State private var scene = ""
    @State private var meal = ""
    @State private var sleep = ""
    @State private var source = ""
    @State private var files: [JournalMediaFile] = []
    @State private var selected: [PhotosPickerItem] = []
    @State private var reportItems: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var busy = false
    @State private var progress = ""
    @State private var message: String?
    @State private var discard = false
    @State private var saved = false
    @State private var discarded = false
    @State private var loaded = false
    @State private var unimportedVoice: (url: URL, duration: TimeInterval, waveform: [Float])?
    @State private var recorder = AudioRecorder()
    @State private var voice: (fileName: String, duration: Double, waveform: [Float])?
    @State private var draftRecoveryFailed = false
    @State private var ownsDraft = false
    @State private var transcription: Task<Void, Never>?

    private var draft: MemoryJournalDraft {
        .init(id: id, kind: kind, date: date, words: words, context: scene,
              meal: meal, sleep: sleep, source: source)
    }
    private var dirty: Bool { draft.hasText || !files.isEmpty || voice != nil || unimportedVoice != nil || recorder.state == .recording }
    private var accent: Color { env.theme.theme.textAccent }
    private var snapshot: JournalDraftSnapshot {
        .init(draft: draft, files: files, voice: voice.map { .init(fileName: $0.fileName, duration: $0.duration, waveform: $0.waveform) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    (dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout(spacing: 14))) {
                        BubuMascotBadge(size: 64, expression: kind == .school ? .playing : .music)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(kind == .school ? "把今天装进小书包" : "这句话，想听很多年")
                                .font(BubuTheme.Font.title)
                            Text(kind == .school ? "老师发来的日常，一起收进时光" : "原声留下，文字可以慢慢补")
                                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                    }
                    DatePicker("发生在", selection: $date, in: ...Date.now,
                               displayedComponents: kind == .school ? [.date] : [.date, .hourAndMinute])
                    if kind == .school { importControls }
                    else { recordingControls }
                    field(kind == .school ? "今天的小故事" : "她说了什么", text: $words,
                          prompt: kind == .school ? "今天和小伙伴一起……" : "原话是什么？也可以先只存声音")
                    if kind == .school {
                        field("吃饭怎么样", text: $meal, prompt: "没提到就留空，不猜测食量")
                        field("午睡怎么样", text: $sleep, prompt: "如 12:10–13:30，或老师的原话")
                        field("老师原文", text: $source, prompt: "粘贴老师的消息，或导入日报截图")
                        Button("从原文整理餐睡草稿") { suggestFields() }
                            .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("识别可能有误，请核对日期、人物和餐睡内容。群发的班级信息不等于她的个人记录。")
                            .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    } else {
                        field("当时在做什么", text: $scene, prompt: "睡前聊天、放学路上、第一次讲故事……")
                    }
                    if !files.isEmpty {
                        Text("已选 \(files.count) 个素材").font(BubuTheme.Font.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))]) {
                            ForEach(files) { file in
                                VStack(spacing: 6) {
                                    JournalDraftThumbnail(file: file).frame(height: 88)
                                    Text(file.isVideo ? "视频" : "照片").font(.caption)
                                    Button("移除", role: .destructive) { remove(file) }.font(.caption)
                                }
                                .frame(maxWidth: .infinity).padding(10)
                                .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm))
                            }
                        }
                    }
                    if busy { HStack { ProgressView(); Text(progress) }.font(BubuTheme.Font.caption) }
                    if let message { Text(message).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText) }
                    Text("收好后会出现在时光里。开启家庭同步时，原声和素材会继续上传。")
                        .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .disabled(!ownsDraft || busy)
                .padding().bubuContentColumn(700)
            }
            .background(BubuTheme.Color.background.ignoresSafeArea())
            .navigationTitle(kind == .school ? "记幼儿园的一天" : "留住一句童言")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(transcription == nil ? "以后再说" : "停止识别") {
                        if let transcription {
                            transcription.cancel()
                            self.transcription = nil
                            busy = false
                            message = "已停止等待识别，原声保留，可以直接收好。"
                        } else if dirty { discard = true } else { dismiss() }
                    }.disabled(busy && transcription == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("收好") { save() }.fontWeight(.bold)
                        .disabled(!ownsDraft || !dirty || busy || unimportedVoice != nil || recorder.state == .recording)
                        .accessibilityIdentifier("journal.save")
                }
            }
            .tint(accent)
            .interactiveDismissDisabled(dirty || busy)
            .confirmationDialog("这一笔还没收好", isPresented: $discard, titleVisibility: .visible) {
                if unimportedVoice == nil && !draftRecoveryFailed {
                    Button("留在草稿，下次继续") {
                        if let result = recorder.stop() { keepRecording(result) }
                        if unimportedVoice == nil && persistDraft() { dismiss() }
                    }
                }
                Button("丢弃草稿", role: .destructive) { discarded = true; dismiss() }
                Button("继续记录", role: .cancel) {}
            }
            .onAppear { restoreDraft() }
            .task(id: snapshot) {
                do { try await Task.sleep(for: .milliseconds(350)) }
                catch { return }
                persistDraft()
            }
            .onChange(of: selected) { _, items in Task { await importPhotos(items, report: false) } }
            .onChange(of: reportItems) { _, items in Task { await importPhotos(items, report: true) } }
            .onChange(of: recorder.state) { _, state in
                if state == .finished, let result = recorder.consumeInterruptedResult() { keepRecording(result) }
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image, .movie, .plainText], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { Task { await importFiles(urls) } }
                else if case .failure(let error) = result { message = error.localizedDescription }
            }
            .onDisappear {
                guard ownsDraft else { return }
                if !discarded, !saved, let result = recorder.stop() { keepRecording(result) }
                if !saved && !discarded { persistDraft() }
                // A failed import still owns the recorder's source. Never delete it implicitly.
                if unimportedVoice == nil || discarded { recorder.cancel() }
                if discarded {
                    for file in files { env.mediaStore.deleteLocalFiles(media: file.fileName, thumbnail: file.thumbnail) }
                    if let voice { env.mediaStore.deleteMedia(named: voice.fileName) }
                }
                if (saved || discarded) && !draftRecoveryFailed {
                    try? JournalDraftStore.remove(at: JournalDraftStore.file(for: kind))
                }
                Self.activeDrafts.remove(kind)
                ownsDraft = false
            }
        }
    }

    private var importControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(selection: $selected, maxSelectionCount: 50, matching: .any(of: [.images, .videos])) {
                Label("批量选老师的照片 / 视频", systemImage: "photo.stack.fill")
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
            }.buttonStyle(.borderedProminent).tint(env.theme.theme.actionFill)
            HStack {
                PhotosPicker(selection: $reportItems, maxSelectionCount: 5, matching: .images) {
                    Label("读日报截图", systemImage: "text.viewfinder")
                }
                Spacer()
                Button { showFiles = true } label: { Label("从文件导入", systemImage: "folder") }
            }.font(BubuTheme.Font.body)
            Text("截图在本机识别，先整理成草稿。每批最多 50 个素材；大视频请保持 App 在前台直到收好。")
                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
        }
    }

    private var recordingControls: some View {
        VStack(spacing: 12) {
            if let voice {
                VoicePlayerBubble(fileName: voice.fileName, duration: voice.duration,
                                  waveform: voice.waveform, mediaStore: env.mediaStore, tint: accent)
                Button("识别成文字草稿") {
                    transcription = Task { await transcribe(voice.fileName) }
                }
                Text("童音可能识别不准，原声始终保留。已有文字不会被自动覆盖。")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            } else if let result = unimportedVoice {
                Button("重试保存已录声音") { keepRecording(result) }
            } else {
                Button { Task { await toggleRecording() } } label: {
                    Label(recorder.state == .recording ? "停止 · \(AudioRecorder.timeText(recorder.elapsed))" : "录下她的声音",
                          systemImage: recorder.state == .recording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(BubuTheme.Font.headline).frame(maxWidth: .infinity, minHeight: 64)
                        .foregroundStyle(.white)
                }.buttonStyle(.borderedProminent).tint(env.theme.theme.actionFill)
                if recorder.state == .recording {
                    WaveformView(samples: Array(recorder.levels.suffix(30)), color: accent).frame(height: 34)
                    Text("正在录音，锁屏或来电会保留已录部分").font(BubuTheme.Font.caption)
                }
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(BubuTheme.Font.headline)
            TextField(prompt, text: text, axis: .vertical).lineLimit(2...8)
                .font(BubuTheme.Font.body).padding(12)
                .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm))
                .accessibilityIdentifier(title == "她说了什么" || title == "今天的小故事" ? "journal.words" : title)
        }
    }
    private func suggestFields() {
        let suggestion = SchoolReportSuggestion.parse(source)
        if meal.isEmpty { meal = suggestion.meal }
        if sleep.isEmpty { sleep = suggestion.sleep }
        message = "已整理出餐睡草稿，请核对；没找到的信息保持空白。"
    }
    private func importPhotos(_ items: [PhotosPickerItem], report: Bool) async {
        guard !items.isEmpty, !busy else { return }
        busy = true
        defer { busy = false; if report { reportItems = [] } else { selected = [] } }
        var failed = 0
        for (index, item) in items.enumerated() {
            progress = "整理 \(index + 1) / \(items.count)"
            do {
                guard files.count < 50 else { failed += 1; continue }
                guard let transfer = try await item.loadTransferable(type: JournalPickedFile.self) else { failed += 1; continue }
                defer { try? FileManager.default.removeItem(at: transfer.url) }
                let result = try await JournalImport.prepare(url: transfer.url, report: report, store: env.mediaStore)
                accept(result)
            } catch { failed += 1 }
        }
        if report { suggestFields() }
        message = failed > 0 ? "\(failed) 个素材未导入。原片仍在原处；请重新选择失败的素材。" : "已整理，请核对后收好。重复素材已跳过。"
    }
    private func importFiles(_ urls: [URL]) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        var failed = max(0, urls.count - 50)
        for url in urls.prefix(50) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                if UTType(filenameExtension: url.pathExtension)?.conforms(to: .plainText) == true {
                    let text = try await Task.detached(priority: .utility) {
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 100_000 else { throw CocoaError(.fileReadTooLarge) }
                        return try String(contentsOf: url, encoding: .utf8)
                    }.value
                    source += (source.isEmpty ? "" : "\n") + text
                } else if files.count < 50 {
                    accept(try await JournalImport.prepare(url: url, report: false, store: env.mediaStore))
                } else { failed += 1 }
            } catch { failed += 1 }
        }
        suggestFields()
        if failed > 0 { message = "\(failed) 个文件未导入，请检查格式或从相册重新选择。" }
    }
    private func accept(_ result: JournalImport.Result) {
        if files.contains(where: { $0.hash == result.file.hash }) {
            env.mediaStore.deleteLocalFiles(media: result.file.fileName, thumbnail: result.file.thumbnail)
            return
        }
        files.append(result.file)
        if !result.recognizedText.isEmpty { source += (source.isEmpty ? "" : "\n") + result.recognizedText }
    }
    private func remove(_ file: JournalMediaFile) {
        files.removeAll { $0.id == file.id }
        env.mediaStore.deleteLocalFiles(media: file.fileName, thumbnail: file.thumbnail)
    }
    private func toggleRecording() async {
        if recorder.state == .recording {
            if let result = recorder.stop() { keepRecording(result) }
        } else if await recorder.requestPermission() {
            if !recorder.start() { message = "录音没有启动，请重试。" }
        } else { message = "请在系统设置允许麦克风权限，也可以先用文字记下来。" }
    }
    private func keepRecording(_ result: (url: URL, duration: TimeInterval, waveform: [Float])) {
        unimportedVoice = result
        do {
            let fileName = try env.mediaStore.importAudio(from: result.url)
            voice = (fileName, result.duration, result.waveform)
            unimportedVoice = nil
            try? FileManager.default.removeItem(at: result.url)
        } catch { message = "录音暂未保存，请保持页面并检查储存空间。" }
    }
    private func transcribe(_ fileName: String) async {
        guard !busy else { return }
        busy = true; progress = "正在听这句话…"
        defer { if !Task.isCancelled { busy = false; transcription = nil } }
        let text = await VoiceTranscriber.transcribe(url: env.mediaStore.mediaURL(for: fileName),
            aiService: env.aiService, aiConfigured: env.config.isAIConfigured)
        guard !Task.isCancelled else { return }
        if let text, !text.isEmpty {
            if words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { words = text }
            else { message = "识别结果：\(text)\n已保留你填写的原话。" }
        } else { message = "暂时没听清，原声已保留，可以直接收好或手动补文字。" }
    }
    private func save() {
        guard ownsDraft, !busy, unimportedVoice == nil, recorder.state != .recording else { return }
        do {
            guard files.allSatisfy({ env.mediaStore.fileExists(forMedia: $0.fileName) }),
                  voice.map({ env.mediaStore.fileExists(forMedia: $0.fileName) }) ?? true else {
                message = "有素材暂时找不到，请重新选择后再收好；不会保存缺失的原声或照片。"
                return
            }
            _ = try MemoryJournalWriter.save(draft, files: files, voice: voice, role: env.config.currentRole,
                                              container: context.container)
            saved = true
            env.syncEngine.syncNow()
            env.refreshWidgetSnapshot(context: context)
            BubuHaptics.success()
            dismiss()
        } catch { message = "没有保存成功，草稿和录音还在，请重试：\(error.localizedDescription)" }
    }
    private func restoreDraft() {
        guard !loaded else { return }
        guard Self.activeDrafts.insert(kind).inserted else {
            message = "另一窗口正在编辑这一份草稿，请先在那里收好或退出。"
            return
        }
        ownsDraft = true
        defer { loaded = true }
        do {
            guard let value = try JournalDraftStore.load(from: JournalDraftStore.file(for: kind)), value.draft.kind == kind else { return }
            // A crash after the database commit must not offer the same saved draft again.
            let draftID = value.draft.id
            if try context.fetchCount(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == draftID })) > 0 {
                try JournalDraftStore.remove(at: JournalDraftStore.file(for: kind))
                return
            }
            id = value.draft.id; date = value.draft.date; words = value.draft.words
            scene = value.draft.context; meal = value.draft.meal; sleep = value.draft.sleep; source = value.draft.source
            files = value.files
            voice = value.voice.map { ($0.fileName, $0.duration, $0.waveform) }
            message = "上次没收好的草稿还在，接着记吧。"
        } catch {
            draftRecoveryFailed = true
            message = "旧草稿暂时打不开，原文件已保留。本次新记录可以收好，但暂不覆盖旧草稿。"
        }
    }
    @discardableResult
    private func persistDraft() -> Bool {
        guard ownsDraft, loaded, !saved, !discarded, !draftRecoveryFailed else { return false }
        do {
            if dirty { try JournalDraftStore.save(snapshot, to: JournalDraftStore.file(for: kind)) }
            else { try JournalDraftStore.remove(at: JournalDraftStore.file(for: kind)) }
            return true
        }
        catch let error as JournalDraftError { message = error.localizedDescription }
        catch { message = "草稿尚未写入磁盘，请保持页面并检查储存空间。" }
        return false
    }
}

/// Drafts use the same bounded thumbnail cache as the timeline, without constructing
/// temporary SwiftData models or decoding original teacher videos on the main thread.
private struct JournalDraftThumbnail: View {
    let file: JournalMediaFile
    @Environment(AppEnvironment.self) private var env
    @State private var image: UIImage?

    var body: some View {
        Color.clear.overlay {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: file.isVideo ? "video.fill" : "photo.fill") }
        }
        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.sm))
        .accessibilityLabel(file.isVideo ? "已选视频" : "已选照片")
        .task(id: file.id) {
            image = await env.thumbnails.image(mediaId: file.id, thumbnailFileName: file.thumbnail,
                localFileName: file.fileName, isPhoto: !file.isVideo, size: .grid)
        }
    }
}
