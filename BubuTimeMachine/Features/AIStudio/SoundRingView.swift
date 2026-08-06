import SwiftUI
import SwiftData
import UIKit

// MARK: - 声音年轮
/// 服务端只负责把已同步的真实原声编排成 3—8 分钟音频章；
/// 家庭先看来源清单再确认渲染，成片与每一段都能回到原始记录。
struct SoundRingView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \VoiceMemo.recordedAt, order: .reverse) private var memos: [VoiceMemo]
    // 不再全量 @Query Entry：本页只按 sourceId 找零星几条，
    // 全量拉会把整库 faulting 的成本塞进这个纯展示页。改按需单条查。
    @Environment(\.modelContext) private var context

    private let previewMode: Bool
    @State private var ring: SoundRing?
    @State private var history: [SoundRing] = []
    @State private var isLoading: Bool
    @State private var operation: Operation?
    @State private var errorMessage: String?
    @State private var operationError: String?
    @State private var isOfflineCache = false
    @State private var showRenderConfirmation = false
    @State private var showArchiveConfirmation = false
    @State private var pendingRemovalSourceId: String?
    @State private var showAdvancedSettings = false
    @State private var jumpEntry: Entry?
    @State private var sourceDetail: WeeklyReportSource?
    @State private var shareItem: SoundShareItem?
    @State private var audioURL: URL?
    @State private var player = AudioPlayer()
    @State private var mutationTask: Task<Void, Never>?
    @State private var downloadTask: Task<Void, Never>?
    @State private var pollTask: Task<Void, Never>?
    @State private var mutationToken: UUID?
    @State private var downloadToken: UUID?
    @State private var reloadNonce = 0

    private enum Operation {
        case drafting
        case editingDraft
        case rendering
        case downloading
        case archiving
    }

    private var theme: Color { env.theme.theme.primary }

    init(previewRing: SoundRing? = nil) {
        previewMode = previewRing != nil
        _ring = State(initialValue: previewRing)
        _isLoading = State(initialValue: previewRing == nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                content
            }
            .padding()
            .bubuContentColumn()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("声音年轮")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $jumpEntry) { EntryDetailView(entry: $0) }
        .sheet(item: $sourceDetail) { source in sourceSheet(source) }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
        .sheet(isPresented: $showAdvancedSettings) {
            NavigationStack {
                AdvancedSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showAdvancedSettings = false }
                        }
                    }
            }
        }
        .alert("开始制作声音年轮？", isPresented: $showRenderConfirmation) {
            Button("开始制作") { render() }
            Button("再听听原声", role: .cancel) {}
        } message: {
            Text("只会读取上面列出的原声并生成一份派生音频，不会修改、删除或覆盖任何原记录。")
        }
        .alert("收进档案？", isPresented: $showArchiveConfirmation) {
            Button("收进档案") { archive() }
            Button("再看看", role: .cancel) {}
        } message: {
            Text("只会把这份音频章标为已归档，原声、照片和文字都保持不变。")
        }
        .confirmationDialog(
            "从本次清单移除这段？",
            isPresented: Binding(
                get: { pendingRemovalSourceId != nil },
                set: { if !$0 { pendingRemovalSourceId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("只从本次清单移除", role: .destructive) {
                guard let sourceId = pendingRemovalSourceId else { return }
                pendingRemovalSourceId = nil
                removeClip(sourceId)
            }
            Button("保留", role: .cancel) { pendingRemovalSourceId = nil }
        } message: {
            Text("原声记录不会删除，只影响这一次声音年轮清单。")
        }
        .alert("操作没有完成", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("知道了") { operationError = nil }
        } message: {
            Text(operationError ?? "请稍后再试。")
        }
        .task(id: "\(env.aiServiceRevision)-\(reloadNonce)") {
            await load(expectedRevision: env.aiServiceRevision)
        }
        .onDisappear {
            mutationTask?.cancel()
            downloadTask?.cancel()
            pollTask?.cancel()
            player.stop()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            BubuMascotBadge(size: 62, expression: .music)
            VStack(alignment: .leading, spacing: 5) {
                Text("听得见时间长大")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("原声是主角，中性旁白只报年龄；不克隆声音，也不用想象补齐。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(theme.opacity(0.08), in: RoundedRectangle(
            cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    @ViewBuilder
    private var content: some View {
        if !previewMode && !env.config.isAIConfigured {
            stateCard(icon: "house.and.flag.fill", title: "先连接家里的 AI 服务",
                      message: "声音只在家里的 mini 上编排，受保护原声不会交给第三方语音平台。",
                      actionTitle: "打开高级设置") { showAdvancedSettings = true }
        } else if isLoading {
            loadingState
        } else if let ring {
            ringContent(ring)
        } else if let errorMessage {
            stateCard(icon: "exclamationmark.triangle.fill", title: "这次没有整理好",
                      message: errorMessage, actionTitle: "再试一次") {
                reloadNonce += 1
            }
        } else {
            stateCard(icon: "waveform.badge.plus", title: "还没有声音年轮",
                      message: "先把至少约 3 分钟布布原声或家人留言同步好。我不会用静音或 AI 旁白把时长凑满。",
                      actionTitle: "整理一圈声音") { createDraft() }
        }
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(BubuTheme.Color.softFill).frame(height: 22)
            RoundedRectangle(cornerRadius: 10).fill(BubuTheme.Color.softFill).frame(height: 96)
            RoundedRectangle(cornerRadius: 10).fill(BubuTheme.Color.softFill).frame(height: 96)
        }
        .redacted(reason: .placeholder)
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(
            cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .accessibilityLabel("正在读取声音年轮")
    }

    @ViewBuilder
    private func ringContent(_ ring: SoundRing) -> some View {
        if isOfflineCache {
            Label("当前显示已下载的离线作品；联网后会自动读取最新状态。", systemImage: "arrow.down.circle.fill")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(BubuTheme.Color.softFill, in: RoundedRectangle(
                    cornerRadius: BubuTheme.Radius.small, style: .continuous))
        }
        statusHeader(ring)

        if ring.status == "ready" || ring.status == "archived" {
            playerCard(ring)
        } else if ring.status == "rendering" {
            renderingCard
        } else if ring.status == "failed" {
            stateCard(icon: "arrow.clockwise.circle.fill", title: "制作停在半路",
                      message: ring.error.isEmpty ? "原声没有丢，可以从同一份清单继续制作。" : ring.error,
                      actionTitle: "继续制作") { render() }
            secondaryButton(title: "重新整理素材", icon: "waveform.badge.plus") {
                createDraft()
            }
        }

        timeline(ring)
        actionArea(ring)
    }

    private func statusHeader(_ ring: SoundRing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ring.title)
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("\(ring.summary) · \(statusText(ring.status))")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            Spacer()
            if history.count > 1 {
                Menu {
                    ForEach(history) { item in
                        Button {
                            select(item)
                        } label: {
                            Text("\(item.summary) · \(statusText(item.status))")
                        }
                    }
                } label: {
                    Label("往期", systemImage: "clock.arrow.circlepath")
                        .font(BubuTheme.Font.scaled(12, weight: .semibold))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .frame(minHeight: 44)
                }
                .accessibilityHint("选择以前的声音年轮")
                .disabled(operation != nil)
            }
        }
        .padding(.horizontal, 4)
    }

    private func playerCard(_ ring: SoundRing) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    playOrDownload(ring)
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(BubuTheme.Font.scaled(46, weight: .semibold))
                        .foregroundStyle(BubuTheme.Color.deepRose)
                }
                .buttonStyle(.plain)
                .disabled(previewMode || operation == .downloading)
                .accessibilityLabel(player.isPlaying ? "暂停声音年轮" : "播放声音年轮")

                VStack(alignment: .leading, spacing: 7) {
                    Text(operation == .downloading ? "正在取回家庭音频…" : "完整音频章")
                        .font(BubuTheme.Font.body.weight(.semibold))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Slider(
                        value: Binding(get: { player.progress }, set: { player.seek(to: $0) }),
                        in: 0...1
                    )
                    .tint(BubuTheme.Color.deepRose)
                    .disabled(audioURL == nil)
                    .accessibilityLabel("声音年轮播放进度")
                    .accessibilityValue("\(durationText(player.progress * max(player.duration, ring.renderedDurationSeconds)))，共 \(durationText(max(player.duration, ring.renderedDurationSeconds)))")
                    HStack {
                        Text(durationText(player.progress * max(player.duration, ring.renderedDurationSeconds)))
                        Spacer()
                        Text("成片 \(durationText(ring.renderedDurationSeconds > 0 ? ring.renderedDurationSeconds : ring.originalDurationSeconds))")
                    }
                    .font(BubuTheme.Font.scaled(12, weight: .medium, design: .monospaced))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            Text("每个时间点都保留真实来源；点下面任意一段，可以直接听原声或回看当天照片。")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(
            cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var renderingCard: some View {
        HStack(spacing: 14) {
            ProgressView().tint(theme)
            VStack(alignment: .leading, spacing: 4) {
                Text("正在把原声轻轻接起来")
                    .font(BubuTheme.Font.body.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("离开页面也不会重复提交；回来会从服务端状态继续。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(theme.opacity(0.08), in: RoundedRectangle(
            cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .accessibilityLabel("声音年轮正在制作")
    }

    private func timeline(_ ring: SoundRing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("这圈时间里的原声", systemImage: "waveform.path")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            ForEach(ring.clips) { clip in
                clipCard(clip, ring: ring)
            }
        }
    }

    private func clipCard(_ clip: SoundRingClip, ring: SoundRing) -> some View {
        let voiceSource = ring.sourceRefs.first { $0.sourceId == clip.sourceId }
        let photoSource = ring.sourceRefs.first { $0.sourceId == clip.photoSourceId }
        let memo = localMemo(clip)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(clip.ageYears) 岁")
                    .font(BubuTheme.Font.scaled(20, weight: .bold))
                        .foregroundStyle(BubuTheme.Color.deepRose)
                Text(clip.kind == "childVoice" ? "布布的声音" : "家人对她说")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer()
                Text(durationText(clip.durationSeconds))
                    .font(BubuTheme.Font.scaled(11, weight: .medium, design: .monospaced))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            if let date = Self.date(from: clip.recordedAt) {
                Text(BubuDateFormat.yearMonthDay(date))
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            if !clip.transcript.isEmpty {
                Text("“\(clip.transcript)”")
                    .font(BubuTheme.Font.body)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let fileName = memo?.localFileName {
                VoicePlayerBubble(fileName: fileName,
                                  duration: memo?.durationSeconds ?? clip.durationSeconds,
                                  waveform: [], mediaStore: env.mediaStore,
                                  tint: BubuTheme.Color.deepRose)
            } else if let url = audioURL, clip.endSeconds > clip.startSeconds {
                Button {
                    player.play(url: url, from: clip.startSeconds)
                } label: {
                    Label("从成片这里开始听", systemImage: "play.fill")
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            FlowLayout(spacing: 8) {
                if let voiceSource {
                    sourceButton(voiceSource, title: "查看原声出处")
                }
                if let photoSource {
                    sourceButton(photoSource, title: "看当天照片")
                }
                if ring.status == "draft" {
                    Button(role: .destructive) {
                        pendingRemovalSourceId = clip.sourceId
                    } label: {
                        Label("移除这段", systemImage: "minus.circle")
                            .font(BubuTheme.Font.scaled(11, weight: .semibold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(operation != nil)
                    .accessibilityHint("只从本次声音年轮清单移除，不会删除原声记录")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(
            cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func sourceButton(_ source: WeeklyReportSource, title: String) -> some View {
        Button { open(source) } label: {
            Label(title, systemImage: source.collection == "entries" ? "photo.fill" : "link")
                .font(BubuTheme.Font.scaled(11, weight: .semibold))
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(theme.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开声音年轮引用的原始记录")
    }

    @ViewBuilder
    private func actionArea(_ ring: SoundRing) -> some View {
        if ring.status == "draft" {
            primaryButton(title: "确认素材并开始制作", icon: "waveform.badge.mic") {
                showRenderConfirmation = true
            }
        } else if ring.status == "ready" {
            primaryButton(title: "收进档案", icon: "archivebox.fill") {
                showArchiveConfirmation = true
            }
            secondaryButton(title: "分享音频章", icon: "square.and.arrow.up") {
                share(ring)
            }
        } else if ring.status == "archived" {
            secondaryButton(title: "分享音频章", icon: "square.and.arrow.up") {
                share(ring)
            }
            secondaryButton(title: "整理新一圈", icon: "waveform.badge.plus") {
                createDraft()
            }
        }
    }

    private func primaryButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if operation != nil { ProgressView().tint(BubuTheme.Color.background) }
                Label(title, systemImage: icon)
            }
            .font(BubuTheme.Font.body.weight(.bold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
        .foregroundStyle(BubuTheme.Color.background)
        .background(BubuTheme.Color.warmBrown, in: RoundedRectangle(
            cornerRadius: BubuTheme.Radius.button, style: .continuous))
        .disabled(operation != nil)
    }

    private func secondaryButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(BubuTheme.Font.body.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
        }
        .buttonStyle(.plain)
        .foregroundStyle(BubuTheme.Color.warmBrown)
        .background(theme.opacity(0.10), in: RoundedRectangle(
            cornerRadius: BubuTheme.Radius.button, style: .continuous))
        .disabled(operation != nil || previewMode)
    }

    private func stateCard(
        icon: String, title: String, message: String,
        actionTitle: String? = nil, action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(BubuTheme.Font.scaled(24, weight: .semibold))
                .foregroundStyle(theme)
            Text(title).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            Text(message).font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText).lineSpacing(4)
            if let actionTitle, let action {
                primaryButton(title: operation == .drafting ? "正在整理原声" : actionTitle,
                              icon: "waveform") { action() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(
            cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func open(_ source: WeeklyReportSource) {
        if source.collection == "entries",
           let id = UUID(uuidString: source.localId),
           let entry = fetchEntry(id) {
            jumpEntry = entry
        } else {
            sourceDetail = source
        }
    }

    private func sourceSheet(_ source: WeeklyReportSource) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label(source.title, systemImage: source.collection == "voicememos" ? "waveform" : "photo")
                        .font(BubuTheme.Font.headline)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    if let date = Self.date(from: source.happenedAt) {
                        Text(BubuDateFormat.yearMonthDay(date))
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    Text(source.excerpt.isEmpty ? "原记录没有补充文字。" : source.excerpt)
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .lineSpacing(5)
                    if source.collection == "voicememos",
                       let id = UUID(uuidString: source.localId),
                       let memo = memos.first(where: { $0.id == id }),
                       let fileName = memo.localFileName {
                        VoicePlayerBubble(fileName: fileName,
                                          duration: memo.durationSeconds ?? 0,
                                          waveform: [], mediaStore: env.mediaStore, tint: theme)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(BubuTheme.Color.background.ignoresSafeArea())
            .navigationTitle("原声出处")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { sourceDetail = nil }
                }
            }
        }
    }

    private func load(expectedRevision: Int) async {
        guard !previewMode else { return }
        mutationTask?.cancel()
        downloadTask?.cancel()
        pollTask?.cancel()
        player.stop()
        audioURL = nil
        guard env.config.isAIConfigured else {
            isLoading = false
            ring = nil
            return
        }
        isLoading = true
        errorMessage = nil
        isOfflineCache = false
        let service = env.aiService
        do {
            let fetched = try await service.latestSoundRing()
            guard !Task.isCancelled, env.aiServiceRevision == expectedRevision else { return }
            setCurrentRing(fetched)
            isLoading = false
            var fetchedHistory = (try? await service.soundRingHistory()) ?? []
            guard !Task.isCancelled, env.aiServiceRevision == expectedRevision else { return }
            if let newest = fetchedHistory.first {
                setCurrentRing(newest)
            } else if let fetched {
                fetchedHistory = [fetched]
            }
            history = fetchedHistory
            Self.persistHistoryCache(fetchedHistory)
            if let current = ring {
                if current.status == "rendering" { startPolling(current.id) }
                if current.hasAudio {
                    startDownload(for: current, intent: .cache)
                }
            }
        } catch {
            guard !Self.isCancellation(error), !Task.isCancelled,
                  env.aiServiceRevision == expectedRevision else { return }
            errorMessage = "家里的声音服务暂时没有回应。原声和已有记录都不会受影响。"
            let cached = Self.cachedHistory()
            if let first = cached.first {
                history = cached
                setCurrentRing(first)
                isOfflineCache = true
                errorMessage = nil
            } else {
                setCurrentRing(nil)
            }
        }
        guard !Task.isCancelled, env.aiServiceRevision == expectedRevision else { return }
        isLoading = false
    }

    private func createDraft() {
        guard operation == nil else { return }
        operation = .drafting
        errorMessage = nil
        let service = env.aiService
        let revision = env.aiServiceRevision
        let token = UUID()
        mutationTask?.cancel()
        mutationToken = token
        mutationTask = Task { @MainActor in
            defer {
                if mutationToken == token {
                    operation = nil
                    mutationTask = nil
                    mutationToken = nil
                }
            }
            do {
                let value = try await service.createSoundRingDraft()
                guard !Task.isCancelled, env.aiServiceRevision == revision else { return }
                if let current = ring,
                   current.id == value.id,
                   current.status == "ready" || current.status == "archived" {
                    operationError = "还没有新的原声可整理；已有作品和原记录都保持不变。"
                    return
                }
                setCurrentRing(value)
                upsertHistory(value)
                BubuHaptics.success()
                UIAccessibility.post(notification: .announcement, argument: "声音素材已经整理好，请确认")
            } catch {
                guard !Self.isCancellation(error), !Task.isCancelled,
                      env.aiServiceRevision == revision else { return }
                errorMessage = Self.readable(error)
                UIAccessibility.post(notification: .announcement, argument: "声音素材暂时没有整理好")
            }
        }
    }

    private func render() {
        guard let id = ring?.id, operation == nil else { return }
        operation = .rendering
        let service = env.aiService
        let revision = env.aiServiceRevision
        let token = UUID()
        mutationTask?.cancel()
        mutationToken = token
        mutationTask = Task { @MainActor in
            defer {
                if mutationToken == token {
                    operation = nil
                    mutationTask = nil
                    mutationToken = nil
                }
            }
            do {
                let value = try await service.renderSoundRing(id: id)
                guard !Task.isCancelled, env.aiServiceRevision == revision else { return }
                setCurrentRing(value)
                upsertHistory(value)
                startPolling(value.id)
                UIAccessibility.post(notification: .announcement, argument: "声音年轮开始制作")
            } catch {
                guard !Self.isCancellation(error), !Task.isCancelled,
                      env.aiServiceRevision == revision else { return }
                operationError = Self.readable(error)
            }
        }
    }

    private func removeClip(_ sourceId: String) {
        guard let id = ring?.id, ring?.status == "draft", operation == nil else { return }
        operation = .editingDraft
        let service = env.aiService
        let revision = env.aiServiceRevision
        let token = UUID()
        mutationTask?.cancel()
        mutationToken = token
        mutationTask = Task { @MainActor in
            defer {
                if mutationToken == token {
                    operation = nil
                    mutationTask = nil
                    mutationToken = nil
                }
            }
            do {
                let value = try await service.removeSoundRingClip(
                    id: id, sourceId: sourceId
                )
                guard !Task.isCancelled, env.aiServiceRevision == revision else { return }
                setCurrentRing(value)
                upsertHistory(value)
                BubuHaptics.tapLight()
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "这段已从本次清单移除，原声记录仍然保留"
                )
            } catch {
                guard !Self.isCancellation(error), !Task.isCancelled,
                      env.aiServiceRevision == revision else { return }
                operationError = Self.readable(error)
            }
        }
    }

    private func startPolling(_ id: String) {
        guard !previewMode else { return }
        pollTask?.cancel()
        let service = env.aiService
        let revision = env.aiServiceRevision
        pollTask = Task { @MainActor in
            var failures = 0
            for _ in 0..<300 {
                do {
                    try await Task.sleep(for: .seconds(2))
                    let value = try await service.soundRingStatus(id: id)
                    guard !Task.isCancelled, env.aiServiceRevision == revision else { return }
                    guard ring?.id == id else { return }
                    setCurrentRing(value)
                    upsertHistory(value)
                    failures = 0
                    if value.status == "ready" || value.status == "archived" {
                        guard !Task.isCancelled, env.aiServiceRevision == revision,
                              ringIdentity(ring) == ringIdentity(value) else { return }
                        startDownload(for: value, intent: .cache)
                        BubuHaptics.success()
                        UIAccessibility.post(notification: .announcement, argument: "声音年轮制作完成")
                        return
                    }
                    if value.status == "failed" { return }
                } catch {
                    guard !Self.isCancellation(error), !Task.isCancelled else { return }
                    failures += 1
                    if failures >= 3 {
                        operationError = "网络暂时不稳。制作仍在家里的服务器继续，稍后回来会接着读取。"
                        return
                    }
                }
            }
        }
    }

    private func archive() {
        guard let id = ring?.id, operation == nil else { return }
        operation = .archiving
        let service = env.aiService
        let revision = env.aiServiceRevision
        let token = UUID()
        mutationTask?.cancel()
        mutationToken = token
        mutationTask = Task { @MainActor in
            defer {
                if mutationToken == token {
                    operation = nil
                    mutationTask = nil
                    mutationToken = nil
                }
            }
            do {
                let value = try await service.archiveSoundRing(id: id)
                guard !Task.isCancelled, env.aiServiceRevision == revision else { return }
                setCurrentRing(value)
                upsertHistory(value)
                BubuHaptics.success()
                UIAccessibility.post(notification: .announcement, argument: "声音年轮已收进档案")
            } catch {
                guard !Self.isCancellation(error), !Task.isCancelled,
                      env.aiServiceRevision == revision else { return }
                operationError = "暂时没能收进档案。音频仍然安全，稍后再试即可。"
            }
        }
    }

    private func playOrDownload(_ ring: SoundRing) {
        if let audioURL {
            player.toggle(url: audioURL)
            return
        }
        guard !previewMode, operation == nil else { return }
        startDownload(for: ring, intent: .play)
    }

    private func share(_ ring: SoundRing) {
        if let audioURL {
            shareItem = SoundShareItem(url: audioURL)
            return
        }
        guard !previewMode, operation == nil else { return }
        startDownload(for: ring, intent: .share)
    }

    private enum DownloadIntent { case cache, play, share }

    private func startDownload(for requested: SoundRing, intent: DownloadIntent) {
        let service = env.aiService
        let revision = env.aiServiceRevision
        let token = UUID()
        cancelDownload(resetOperation: true)
        downloadToken = token
        operation = .downloading
        downloadTask = Task { @MainActor in
            defer {
                if downloadToken == token {
                    operation = nil
                    downloadTask = nil
                    downloadToken = nil
                }
            }
            let url = await prepareAudio(requested, service: service, revision: revision)
            guard !Task.isCancelled, downloadToken == token,
                  env.aiServiceRevision == revision,
                  ringIdentity(ring) == ringIdentity(requested) else { return }
            if let url {
                switch intent {
                case .cache: break
                case .play: player.play(url: url)
                case .share: shareItem = SoundShareItem(url: url)
                }
            }
        }
    }

    private func prepareAudio(
        _ requested: SoundRing, service: any AIService, revision: Int
    ) async -> URL? {
        guard requested.hasAudio, !previewMode,
              env.aiServiceRevision == revision,
              ringIdentity(ring) == ringIdentity(requested) else { return nil }
        if let existing = Self.existingAudio(for: requested) {
            audioURL = existing
            return existing
        }
        do {
            let temporary = try await service.downloadSoundRing(id: requested.id)
            guard !Task.isCancelled, env.aiServiceRevision == revision,
                  ringIdentity(ring) == ringIdentity(requested) else {
                try? FileManager.default.removeItem(at: temporary)
                return nil
            }
            let persisted = try Self.persistAudio(temporary, ring: requested)
            guard !Task.isCancelled, env.aiServiceRevision == revision,
                  ringIdentity(ring) == ringIdentity(requested) else { return nil }
            audioURL = persisted
            return persisted
        } catch {
            guard !Self.isCancellation(error), !Task.isCancelled,
                  env.aiServiceRevision == revision,
                  ringIdentity(ring) == ringIdentity(requested) else { return nil }
            operationError = "音频暂时没能取回。服务端作品仍在，稍后再试即可。"
            return nil
        }
    }

    private func select(_ item: SoundRing) {
        pollTask?.cancel()
        downloadTask?.cancel()
        setCurrentRing(item)
        if item.status == "rendering" { startPolling(item.id) }
        if item.hasAudio && audioURL == nil {
            startDownload(for: item, intent: .cache)
        }
    }

    private func localMemo(_ clip: SoundRingClip) -> VoiceMemo? {
        guard let source = ring?.sourceRefs.first(where: { $0.sourceId == clip.sourceId }),
              let id = UUID(uuidString: source.localId) else { return nil }
        return memos.first { $0.id == id }
    }

    private func upsertHistory(_ item: SoundRing) {
        history.removeAll { $0.id == item.id }
        history.insert(item, at: 0)
        Self.persistHistoryCache(Array(history.prefix(6)))
    }

    private func setCurrentRing(_ item: SoundRing?) {
        if ringIdentity(ring) != ringIdentity(item) {
            cancelDownload(resetOperation: true)
            player.stop()
            audioURL = item.flatMap { Self.existingAudio(for: $0) }
        }
        ring = item
    }

    /// 下载任务和 UI 锁必须作为一个状态一起取消；否则切换往期时旧 token 的 defer
    /// 不再拥有清理权，页面会永久停在 `.downloading`。
    private func cancelDownload(resetOperation: Bool) {
        downloadTask?.cancel()
        downloadTask = nil
        downloadToken = nil
        if resetOperation, operation == .downloading {
            operation = nil
        }
    }

    private func ringIdentity(_ item: SoundRing?) -> String {
        guard let item else { return "" }
        return "\(item.id):\(item.contentHash)"
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "draft": return "等待确认"
        case "rendering": return "正在制作"
        case "ready": return "可以播放"
        case "archived": return "已收进档案"
        case "failed": return "可以重试"
        default: return "处理中"
        }
    }

    private func durationText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func date(from text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private static func readable(_ error: Error) -> String {
        let text = String(describing: error)
        if text.contains("重新整理") || text.contains("发生了变化") || text.contains("已不可用") {
            return "有一段原声在确认后发生了变化。原记录仍然安全，请点“重新整理素材”生成新清单。"
        }
        if text.contains("3 分钟") || text.contains("原声") {
            return "目前可用原声还不够约 3 分钟。可以继续录几段，素材足够后再来整理；我不会用旁白或静音凑数。"
        }
        return "家里的声音服务暂时没有回应。已有原声不会受影响。"
    }

    private static func existingAudio(for ring: SoundRing) -> URL? {
        let url = audioURL(for: ring)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func persistAudio(_ temporary: URL, ring: SoundRing) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let destination = audioURL(for: ring)
        let staged = audioDirectory.appendingPathComponent(".\(UUID().uuidString).m4a")
        try fm.moveItem(at: temporary, to: staged)
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: destination)
        }
        pruneAudioCache(keeping: destination)
        return destination
    }

    private static func audioURL(for ring: SoundRing) -> URL {
        let safeHash = ring.contentHash.filter { $0.isLetter || $0.isNumber }
        return audioDirectory.appendingPathComponent(
            "bubu_sound_ring_\(ring.id)_\(safeHash).m4a"
        )
    }

    /// 成片是可从家庭服务器重建的派生缓存，不和原声共目录；手机只留最近 6 份。
    private static func pruneAudioCache(keeping current: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let candidates = files.filter {
            $0.lastPathComponent.hasPrefix("bubu_sound_ring_") && $0.pathExtension == "m4a"
        }.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        for url in candidates.dropFirst(6) where url != current {
            try? fm.removeItem(at: url)
        }
    }

    private static func persistHistoryCache(_ items: [SoundRing]) {
        guard !items.isEmpty, let data = try? JSONEncoder().encode(Array(items.prefix(6))) else { return }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
            try data.write(to: historyCacheURL, options: .atomic)
        } catch {
            // 派生缓存写入失败不影响事实记录与在线使用。
        }
    }

    private static func cachedHistory() -> [SoundRing] {
        guard let data = try? Data(contentsOf: historyCacheURL),
              let values = try? JSONDecoder().decode([SoundRing].self, from: data) else { return [] }
        return values.filter { existingAudio(for: $0) != nil }
    }

    private static var historyCacheURL: URL {
        audioDirectory.appendingPathComponent("sound-rings.json")
    }

    private static var audioDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DerivedAudio", isDirectory: true)
    }
    /// 按 id 单条取 Entry（fetchLimit 1），替代全量 @Query。
    private func fetchEntry(_ id: UUID) -> Entry? {
        var d = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

}

private struct SoundShareItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

#if DEBUG
extension SoundRing {
    static func visualSample(status: String) -> SoundRing {
        let base = visualSample
        return SoundRing(
            id: base.id, artifactKey: base.artifactKey, status: status,
            title: base.title, summary: base.summary, generatedAt: base.generatedAt,
            modelVersion: base.modelVersion,
            originalDurationSeconds: base.originalDurationSeconds,
            renderedDurationSeconds: status == "draft" ? 0 : base.renderedDurationSeconds,
            attempts: status == "failed" ? 2 : base.attempts,
            error: status == "failed" ? "上次制作中断，原声仍然安全。" : "",
            narrator: base.narrator, voiceCloning: base.voiceCloning,
            hasAudio: status == "ready" || status == "archived",
            clips: base.clips, sourceRefs: base.sourceRefs,
            contentHash: "\(base.contentHash)-\(status)"
        )
    }

    static let visualSample: SoundRing = {
        let voice0 = "voicememos:8791FB2B-7EA9-43A5-A347-B837FC2BCB4F"
        let voice1 = "voicememos:9791FB2B-7EA9-43A5-A347-B837FC2BCB5F"
        let voice2 = "voicememos:A791FB2B-7EA9-43A5-A347-B837FC2BCB6F"
        let photo = "entries:4F95B83D-40BC-4DA6-9DAB-4C84FC5CF22A"
        return SoundRing(
            id: "soundvisualsample", artifactKey: "sound_ring:sample:visual",
            status: "ready", title: "布布的声音年轮 · 0—2岁",
            summary: "3 段真实原声 · 3分32秒",
            generatedAt: "2026-08-06T08:00:00Z", modelVersion: "visual-sample",
            originalDurationSeconds: 212, renderedDurationSeconds: 226,
            attempts: 1, error: "", narrator: "Apple 系统中性旁白",
            voiceCloning: false, hasAudio: true,
            clips: [
                .init(sourceId: voice0, photoSourceId: photo, ageYears: 0, kind: "childVoice",
                      title: "布布的声音", recordedAt: "2024-11-16T08:00:00Z",
                      transcript: "嗯呀……妈妈。", durationSeconds: 68,
                      startSeconds: 4, endSeconds: 72),
                .init(sourceId: voice1, photoSourceId: "", ageYears: 1, kind: "childVoice",
                      title: "布布的声音", recordedAt: "2025-09-03T08:00:00Z",
                      transcript: "小鸟回家啦。", durationSeconds: 71,
                      startSeconds: 76, endSeconds: 147),
                .init(sourceId: voice2, photoSourceId: "", ageYears: 2, kind: "familyVoice",
                      title: "家人对她说", recordedAt: "2026-07-31T08:00:00Z",
                      transcript: "愿你一直保留今天这样认真看世界的眼睛。", durationSeconds: 73,
                      startSeconds: 151, endSeconds: 224),
            ],
            sourceRefs: [
                .init(sourceId: voice0, collection: "voicememos", recordId: "voice0",
                      localId: "8791FB2B-7EA9-43A5-A347-B837FC2BCB4F",
                      happenedAt: "2024-11-16T08:00:00Z", title: "布布的声音",
                      excerpt: "嗯呀……妈妈。", kind: "voice"),
                .init(sourceId: voice1, collection: "voicememos", recordId: "voice1",
                      localId: "9791FB2B-7EA9-43A5-A347-B837FC2BCB5F",
                      happenedAt: "2025-09-03T08:00:00Z", title: "布布的声音",
                      excerpt: "小鸟回家啦。", kind: "voice"),
                .init(sourceId: voice2, collection: "voicememos", recordId: "voice2",
                      localId: "A791FB2B-7EA9-43A5-A347-B837FC2BCB6F",
                      happenedAt: "2026-07-31T08:00:00Z", title: "家人对她说",
                      excerpt: "愿你一直保留今天这样认真看世界的眼睛。", kind: "voice"),
                .init(sourceId: photo, collection: "entries", recordId: "entry0",
                      localId: "4F95B83D-40BC-4DA6-9DAB-4C84FC5CF22A",
                      happenedAt: "2024-11-16T08:00:00Z", title: "那天的照片",
                      excerpt: "窗边的一小段下午。", kind: "photo_moment"),
            ],
            contentHash: "soundvisualsamplehash")
    }()
}
#endif
