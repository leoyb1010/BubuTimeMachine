import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct MemoryJournalComposer: View {
    let kind: MemoryJournalKind
    var initialDate: Date?
    var onSaved: ((Date) -> Void)?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var id = UUID()
    @State private var date = Date.now
    @State private var words = ""
    @State private var scene = ""
    @State private var meal = ""
    @State private var sleep = ""
    @State private var source = ""
    @State private var schoolReport: SchoolDailyReport?
    @State private var files: [JournalMediaFile] = []
    @State private var selected: [PhotosPickerItem] = []
    @State private var reportItems: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var importingReportFile = false
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
    @State private var draftLease: JournalDraftLease?
    private var ownsDraft: Bool { draftLease != nil }
    @State private var transcription: Task<Void, Never>?
    @State private var importing: Task<Void, Never>?

    private var draft: MemoryJournalDraft {
        .init(id: id, kind: kind, date: date, words: words, context: scene,
              meal: meal, sleep: sleep, source: source, schoolReport: schoolReport)
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
                    if kind == .saying { (dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout(spacing: 14))) {
                        BubuMascotBadge(size: 64, expression: kind == .school ? .playing : .music)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(kind == .school ? "把今天装进小书包" : "这句话，想听很多年")
                                .font(BubuTheme.Font.title)
                            Text(kind == .school ? "老师发来的日常，一起收进时光" : "原声留下，文字可以慢慢补")
                                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                    } }
                    DatePicker("发生在", selection: $date, in: ...Date.now,
                               displayedComponents: kind == .school ? [.date] : [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    if busy { HStack { ProgressView(); Text(progress) }.font(BubuTheme.Font.caption) }
                    if let message { Text(message).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText) }
                    if kind == .school { importControls }
                    else { recordingControls }
                    if schoolReport != nil {
                        SchoolReportEditor(report: Binding(get: { schoolReport ?? SchoolDailyReport() }, set: { schoolReport = $0 }),
                            sourceFile: files.first { $0.hash == schoolReport?.sourceHash })
                    }
                    field(kind == .school ? "今天的小故事" : "她说了什么", text: $words,
                          prompt: kind == .school ? "今天和小伙伴一起……" : "原话是什么？也可以先只存声音")
                    if kind == .school {
                        if schoolReport == nil {
                            field("吃饭怎么样", text: $meal, prompt: "没提到就留空，不猜测食量")
                            field("午睡怎么样", text: $sleep, prompt: "如 12:10–13:30，或老师的原话")
                        }
                        DisclosureGroup("老师消息与识别原文") {
                            field("老师原文", text: $source, prompt: "粘贴老师的消息，或查看截图识别候选")
                            if schoolReport == nil {
                                Button("从原文整理餐睡草稿") { suggestFields() }
                                    .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
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
                    Text("收好后会出现在时光里。开启家庭同步时，原声和素材会继续上传。")
                        .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .disabled(!ownsDraft || busy)
                .padding().bubuContentColumn(700)
            }
            .background(BubuTheme.Color.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(kind == .school ? "记幼儿园的一天" : "留住一句童言")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if schoolReport != nil {
                    Toggle("已对照原表核对，未确认项留空", isOn: Binding(
                        get: { schoolReport?.confirmed == true }, set: { schoolReport?.confirmed = $0 }))
                        .font(BubuTheme.Font.caption).tint(env.theme.theme.actionFill)
                        .foregroundStyle(BubuTheme.Color.warmBrown).frame(minHeight: 44)
                        .accessibilityIdentifier("school.confirmed")
                        .disabled(!ownsDraft || busy).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(BubuTheme.Color.card)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(importing != nil ? "停止导入" : (transcription == nil ? "以后再说" : "停止识别")) {
                        if let importing {
                            importing.cancel()
                            self.importing = nil
                            busy = false
                            reportItems = []; selected = []
                            message = "已停止等待，已导入的素材和填写内容保留，可以继续填写或收好。"
                        } else if let transcription {
                            transcription.cancel()
                            self.transcription = nil
                            busy = false
                            message = "已停止等待识别，原声保留，可以直接收好。"
                        } else if dirty { discard = true } else { closeComposer() }
                    }.disabled(busy && transcription == nil && importing == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("收好") { save() }.fontWeight(.bold)
                        .disabled(!ownsDraft || !dirty || busy || unimportedVoice != nil || recorder.state == .recording)
                        .disabled(schoolReport?.confirmed == false)
                        .accessibilityIdentifier("journal.save")
                }
            }
            .tint(accent)
            .interactiveDismissDisabled(dirty || busy)
            .confirmationDialog("这一笔还没收好", isPresented: $discard, titleVisibility: .visible) {
                if unimportedVoice == nil && !draftRecoveryFailed {
                    Button("留在草稿，下次继续") {
                        if let result = recorder.stop() { keepRecording(result) }
                        if unimportedVoice == nil && persistDraft() { closeComposer() }
                    }
                }
                Button("丢弃草稿", role: .destructive) { discarded = true; closeComposer() }
                Button("继续记录", role: .cancel) {}
            }
            .onAppear { restoreDraft() }
            .task { await importLocalReportProbeIfRequested() }
            .onChange(of: date) { _, _ in schoolReport?.confirmed = false }
            .task(id: snapshot) {
                do { try await Task.sleep(for: .milliseconds(350)) }
                catch { return }
                persistDraft()
            }
            .onChange(of: selected) { _, items in
                guard !items.isEmpty, importing == nil else { return }
                importing = Task { await importPhotos(items, report: false) }
            }
            .onChange(of: reportItems) { _, items in
                guard !items.isEmpty, importing == nil else { return }
                importing = Task { await importPhotos(items, report: true) }
            }
            .onChange(of: recorder.state) { _, state in
                if state == .finished, let result = recorder.consumeInterruptedResult() { keepRecording(result) }
            }
            .fileImporter(isPresented: $showFiles,
                          allowedContentTypes: importingReportFile ? [.image] : [.image, .movie, .plainText],
                          allowsMultipleSelection: !importingReportFile) { result in
                if case .success(let urls) = result, importing == nil {
                    let report = importingReportFile
                    importing = Task { await importFiles(urls, report: report) }
                }
                else if case .failure(let error) = result { message = error.localizedDescription }
            }
            .onDisappear {
                if !isPresented { finishEditing() }
                else if !saved && !discarded { persistDraft() }
            }
        }
    }

    private var importControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if schoolReport?.sourceHash != nil {
                Label("亲子桥原表已加入", systemImage: "checkmark.circle.fill")
                    .font(BubuTheme.Font.body.weight(.semibold)).foregroundStyle(accent)
            } else {
            HStack(spacing: 8) {
            PhotosPicker(selection: $reportItems, maxSelectionCount: 1, matching: .images, preferredItemEncoding: .current) {
                Label("读一张亲子桥", systemImage: "doc.text.viewfinder")
                    .frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(.white)
            }.buttonStyle(.borderedProminent).tint(env.theme.theme.actionFill)
            Button { importingReportFile = true; showFiles = true } label: {
                Image(systemName: "folder").frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.bordered).accessibilityLabel("从文件读取亲子桥")
            }
            }
            HStack(alignment: .top) {
            PhotosPicker(selection: $selected, maxSelectionCount: 50, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) {
                Label("老师照片 / 视频", systemImage: "photo.stack")
            }
                Spacer()
                Button { importingReportFile = false; showFiles = true } label: { Label("素材文件", systemImage: "folder") }
            }.font(BubuTheme.Font.body)
            if schoolReport == nil {
                Button("没有图片，直接填亲子桥") { schoolReport = SchoolDailyReport() }
                    .font(BubuTheme.Font.caption).accessibilityIdentifier("school.manual-report")
            }
            Text("亲子桥一张记一天，照片视频每批最多 50 个。识别仅在本机，确认后再保存。")
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
        message = nil
        defer {
            if !Task.isCancelled {
                busy = false; importing = nil
                if report { reportItems = [] } else { selected = [] }
            }
        }
        var failures: [String] = []
        var warnings: [String] = []
        for (index, item) in items.enumerated() {
            guard !Task.isCancelled else { return }
            progress = "读取相册原件 \(index + 1) / \(items.count) · iCloud 素材需先下载"
            do {
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("-uitest-in-memory"),
                   ProcessInfo.processInfo.arguments.contains("-uitest-journal-slow-import") {
                    try await Task.sleep(for: .seconds(20))
                }
                #endif
                guard files.count < 50 else { failures.append("第\(index + 1)项：本条记录已达50个素材上限"); continue }
                let transfer = try await JournalPickedFile.load(item)
                defer { try? FileManager.default.removeItem(at: transfer.url) }
                try Task.checkCancellation()
                progress = report ? "已取得原图，正在识别亲子桥…" : "保存素材 \(index + 1) / \(items.count)…"
                let result = try await JournalImport.prepare(url: transfer.url, report: report, store: env.mediaStore)
                guard !Task.isCancelled else {
                    env.mediaStore.deleteLocalFiles(media: result.file.fileName, thumbnail: result.file.thumbnail)
                    return
                }
                if let warning = result.warning { warnings.append(warning) }
                accept(result)
            } catch {
                guard !Task.isCancelled else { return }
                failures.append("第\(index + 1)项：\(error.localizedDescription)")
            }
        }
        let success = report ? "原图已加入，识别出 \(schoolReport?.candidates.count ?? 0) 项候选。点候选采用，或对照原图直接填写；核对后收好。" : "已导入，点右上角「收好」保存。重复素材已跳过。"
        message = ([failures.isEmpty ? success : "\(failures.count) 个素材未导入，原片未改动。"] + warnings + failures.prefix(3)).joined(separator: "\n")
    }
    private func importFiles(_ urls: [URL], report: Bool) async {
        guard !busy else { return }
        busy = true
        message = nil
        progress = report ? "正在读取亲子桥文件…" : "正在读取素材文件…"
        defer { if !Task.isCancelled { busy = false; importing = nil } }
        var failed = max(0, urls.count - 50)
        var failureDetails: [String] = []
        for url in urls.prefix(50) {
            guard !Task.isCancelled else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                if UTType(filenameExtension: url.pathExtension)?.conforms(to: .plainText) == true {
                    let text = try await Task.detached(priority: .utility) {
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 100_000 else { throw CocoaError(.fileReadTooLarge) }
                        return try String(contentsOf: url, encoding: .utf8)
                    }.value
                    try Task.checkCancellation()
                    source += (source.isEmpty ? "" : "\n") + text
                } else if files.count < 50 {
                    let result = try await JournalImport.prepare(url: url, report: report, store: env.mediaStore)
                    guard !Task.isCancelled else {
                        env.mediaStore.deleteLocalFiles(media: result.file.fileName, thumbnail: result.file.thumbnail)
                        return
                    }
                    accept(result)
                    if let warning = result.warning { message = warning }
                } else { failed += 1 }
            } catch {
                if Task.isCancelled { return }
                failed += 1
                if failureDetails.count < 3 { failureDetails.append(error.localizedDescription) }
            }
        }
        if !report { suggestFields() }
        else if message == nil { message = "原图已加入，请对照核对后收好。" }
        if failed > 0 { message = "\(failed) 个文件未导入，原文件未改动。\n" + failureDetails.joined(separator: "\n") }
    }
    private func accept(_ result: JournalImport.Result) {
        if let incoming = result.schoolReport {
            if var existing = schoolReport {
                existing.candidates = incoming.candidates
                existing.dateEvidence = incoming.dateEvidence
                existing.sourceHash = incoming.sourceHash
                existing.confirmed = false
                schoolReport = existing
            } else { schoolReport = incoming }
        }
        if files.contains(where: { $0.hash == result.file.hash }) {
            if result.file.isSchoolReport == true, let index = files.firstIndex(where: { $0.hash == result.file.hash }) {
                files[index].isSchoolReport = true
            }
            env.mediaStore.deleteLocalFiles(media: result.file.fileName, thumbnail: result.file.thumbnail)
            return
        }
        files.append(result.file)
        if !result.recognizedText.isEmpty { source += (source.isEmpty ? "" : "\n") + result.recognizedText }
    }
    private func remove(_ file: JournalMediaFile) {
        if file.hash == schoolReport?.sourceHash {
            schoolReport?.sourceHash = nil
            schoolReport?.candidates = [:]
            schoolReport?.dateEvidence = ""
            schoolReport?.confirmed = false
        }
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
            onSaved?(date)
            env.syncEngine.syncNow()
            env.refreshWidgetSnapshot(context: context)
            BubuHaptics.success()
            closeComposer()
        } catch { message = "没有保存成功，草稿和录音还在，请重试：\(error.localizedDescription)" }
    }
    private func restoreDraft() {
        guard !ownsDraft else { return }
        guard let lease = JournalDraftLease.acquire(kind) else {
            message = "另一窗口正在编辑这一份草稿，请先在那里收好或退出。"
            return
        }
        draftLease = lease
        guard !loaded else { return }
        if let initialDate { date = initialDate }
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
            schoolReport = value.draft.schoolReport
            files = value.files
            voice = value.voice.map { ($0.fileName, $0.duration, $0.waveform) }
            message = "上次没收好的草稿还在，接着记吧。"
        } catch {
            draftRecoveryFailed = true
            message = "旧草稿暂时打不开，原文件已保留。本次新记录可以收好，但暂不覆盖旧草稿。"
        }
    }
    private func closeComposer() {
        finishEditing()
        dismiss()
    }
    private func finishEditing() {
        guard ownsDraft else { return }
        importing?.cancel(); importing = nil
        if !discarded, !saved, let result = recorder.stop() { keepRecording(result) }
        if !saved && !discarded { persistDraft() }
        // Failed recording imports keep their source until an explicit discard.
        if unimportedVoice == nil || discarded { recorder.cancel() }
        if discarded {
            for file in files { env.mediaStore.deleteLocalFiles(media: file.fileName, thumbnail: file.thumbnail) }
            if let voice { env.mediaStore.deleteMedia(named: voice.fileName) }
        }
        if (saved || discarded) && !draftRecoveryFailed {
            try? JournalDraftStore.remove(at: JournalDraftStore.file(for: kind))
        }
        draftLease = nil
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

    private func importLocalReportProbeIfRequested() async {
        #if DEBUG && targetEnvironment(simulator)
        guard kind == .school, schoolReport == nil,
              ProcessInfo.processInfo.arguments.contains("-uitest-in-memory"),
              ProcessInfo.processInfo.arguments.contains("-uitest-school-import") else { return }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documents.appendingPathComponent("school-fixture.jpg")
        if !FileManager.default.fileExists(atPath: url.path) {
            // Reproducible UI fixture on fresh CI simulators; a supplied local sample takes priority.
            let sample = UIGraphicsImageRenderer(size: CGSize(width: 700, height: 900)).image { canvas in
                UIColor.white.setFill(); canvas.fill(CGRect(x: 0, y: 0, width: 700, height: 900))
                ("亲子桥\n仅模拟测试样本\n上午点心 90%\n午睡时间请对照原图" as NSString).draw(
                    in: CGRect(x: 40, y: 60, width: 620, height: 700),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 32), .foregroundColor: UIColor.black])
            }
            try? sample.jpegData(compressionQuality: 0.95)?.write(to: url, options: .atomic)
        }
        busy = true; progress = "整理亲子桥…"
        defer { busy = false }
        do {
            let result = try await JournalImport.prepare(url: url, report: true, store: env.mediaStore)
            accept(result)
            if let report = result.schoolReport {
                try JSONEncoder().encode(report).write(to: documents.appendingPathComponent("school-probe.json"), options: .atomic)
            }
        } catch { message = "实样验证失败：\(error.localizedDescription)" }
        #endif
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
