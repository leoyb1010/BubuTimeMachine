import SwiftUI
import SwiftData
import Photos
import UIKit

struct PhotoImportOutcome {
    let accepted: [PHAsset]
    let ignored: [PHAsset]
    let queued: [PHAsset]

    init(accepted: [PHAsset], ignored: [PHAsset], queued: [PHAsset] = []) {
        self.accepted = accepted
        self.ignored = ignored
        self.queued = queued
    }
}

// MARK: - 智能照片收件箱 · 一组收进时光机
/// 自动按事件分段展示最近新增素材；用户一次确认一组，未选择的素材继续保留待处理。
struct TodayPhotosSheet: View {
    let assets: [PHAsset]
    let groups: [PhotoEventGroup]
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onDone: (PhotoImportOutcome) -> Void

    @State private var selected: Set<String> = []
    @State private var thumbs: [String: UIImage] = [:]
    @State private var note = ""
    @State private var saving = false
    @State private var importError: String?
    @State private var groupToIgnore: PhotoEventGroup?
    @State private var selectionSignals: [String: PhotoSelectionSignals] = [:]
    @State private var identityMatches: [String: ChildIdentityMatch] = [:]
    @State private var hiddenSimilarIDs: Set<String> = []
    @State private var expandedGroupIDs: Set<String> = []
    @State private var analyzingSuggestions = false
    @State private var suggestionMessage: String?

    private let identityRecognizer = ChildIdentityRecognizer()

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                // 【卡死修复】必须 LazyVStack：普通 VStack 会在 sheet 打开瞬间把
                // 全部组×全部格子同步实例化——积压几百张候选时点一下就是数秒冻结。
                LazyVStack(spacing: 14) {
                    header
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            groupHeader(group)
                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(visibleAssets(in: group), id: \.localIdentifier) { asset in
                                    cell(asset)
                                }
                            }
                            if hiddenSimilarCount(in: group) > 0 {
                                Button(expandedGroupIDs.contains(group.id)
                                       ? "收起相似照片"
                                       : "展开另外 \(hiddenSimilarCount(in: group)) 张相似照片") {
                                    if expandedGroupIDs.contains(group.id) {
                                        expandedGroupIDs.remove(group.id)
                                    } else {
                                        expandedGroupIDs.insert(group.id)
                                    }
                                }
                                .font(BubuTheme.Font.scaled(12.5, weight: .bold))
                                .foregroundStyle(BubuTheme.Color.primary)
                            }
                        }
                    }
                    if !selected.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("这一段发生了什么？（可选）")
                                .font(BubuTheme.Font.scaled(13, weight: .bold))
                                .foregroundStyle(BubuTheme.Color.secondaryText)
                            TextField("写一句话", text: $note, axis: .vertical)
                                .font(BubuTheme.Font.body)
                                .padding(12)
                                .background(BubuTheme.Color.softFill,
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .padding()
            }
            .background(BubuTheme.Color.background.ignoresSafeArea())
            .navigationTitle("待收进时光")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("稍后") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selected.isEmpty {
                    Button {
                        Task { await importSelected() }
                    } label: {
                        Label("收好 \(selected.count) 个", systemImage: "tray.and.arrow.down.fill")
                            .font(BubuTheme.Font.scaled(16, weight: .heavy, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BubuTheme.Color.primary)
                    .disabled(saving)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(BubuTheme.Color.background.opacity(0.96))
                    .accessibilityLabel("收好 \(selected.count) 个照片和视频")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: selected.isEmpty)
            .overlay { if saving { savingOverlay } }
            .alert("有照片没能收录", isPresented: Binding(
                get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .confirmationDialog("不再提示这段时光？", isPresented: Binding(
                get: { groupToIgnore != nil },
                set: { if !$0 { groupToIgnore = nil } }
            ), titleVisibility: .visible) {
                Button("忽略这组", role: .destructive) {
                    guard let group = groupToIgnore else { return }
                    onDone(PhotoImportOutcome(accepted: [], ignored: assets(in: group)))
                    groupToIgnore = nil
                    dismiss()
                }
                Button("取消", role: .cancel) { groupToIgnore = nil }
            } message: {
                Text("只会从待整理列表隐藏，不会删除系统相册里的原片。")
            }
        }
        // 照片网格是高密度选择器；无障碍超大字号继续由 VoiceOver 完整读出，
        // 视觉字号夹到 xxLarge，避免导航按钮、缩略图和主要操作彼此挤出屏幕。
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("📸").font(BubuTheme.Font.scaled(30))
                Text("已经按时间和地点整理成 \(groups.count) 段。选好一段，一次收进时光轴。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                Spacer(minLength: 0)
            }
            Button {
                Task { await analyzeAndSelectSuggestions() }
            } label: {
                HStack {
                    Label(analyzingSuggestions ? "正在端侧精选…" : "帮我精选",
                          systemImage: "wand.and.stars")
                    Spacer()
                    if analyzingSuggestions { ProgressView() }
                }
            }
            .buttonStyle(.bordered)
            .tint(BubuTheme.Color.primary)
            .disabled(analyzingSuggestions)
            if let suggestionMessage {
                Text(suggestionMessage)
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func assets(in group: PhotoEventGroup) -> [PHAsset] {
        let wanted = Set(group.assetIdentifiers)
        return assets.filter { wanted.contains($0.localIdentifier) }
    }

    private func visibleAssets(in group: PhotoEventGroup) -> [PHAsset] {
        let groupAssets = assets(in: group)
        guard !expandedGroupIDs.contains(group.id) else { return groupAssets }
        return groupAssets.filter { !hiddenSimilarIDs.contains($0.localIdentifier) }
    }

    private func hiddenSimilarCount(in group: PhotoEventGroup) -> Int {
        assets(in: group).count { hiddenSimilarIDs.contains($0.localIdentifier) }
    }

    private func groupHeader(_ group: PhotoEventGroup) -> some View {
        let groupAssets = assets(in: group)
        let allSelected = groupAssets.allSatisfy { selected.contains($0.localIdentifier) }
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.groupTimeText(group))
                    .font(BubuTheme.Font.scaled(15, weight: .heavy, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(Self.groupCountText(group))
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            Spacer()
            Menu {
                Button("不再提示这组", role: .destructive) { groupToIgnore = group }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(BubuTheme.Font.scaled(16, weight: .bold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .accessibilityLabel("这组的更多操作")
            Button(allSelected ? "取消" : "全选") {
                if allSelected {
                    groupAssets.forEach { selected.remove($0.localIdentifier) }
                    if selected.isEmpty { note = "" }
                } else {
                    // 一次只确认一个真实事件，避免两段活动被错误合成一个 Entry。
                    clearNoteIfSwitching(to: group)
                    selected.removeAll()
                    groupAssets.forEach { selected.insert($0.localIdentifier) }
                }
                BubuHaptics.selection()
            }
            .font(BubuTheme.Font.scaled(13, weight: .bold))
            .buttonStyle(.borderless)
        }
        .padding(.top, 6)
    }

    private static func groupTimeText(_ group: PhotoEventGroup) -> String {
        let locale = Locale(identifier: "zh_CN")
        let day = group.startedAt.formatted(.dateTime.month().day().locale(locale))
        let start = group.startedAt.formatted(.dateTime.hour().minute().locale(locale))
        let end = group.endedAt.formatted(.dateTime.hour().minute().locale(locale))
        return start == end ? "\(day) \(start)" : "\(day) \(start)-\(end)"
    }

    private static func groupCountText(_ group: PhotoEventGroup) -> String {
        var parts: [String] = []
        if group.photoCount > 0 { parts.append("\(group.photoCount) 张照片") }
        if group.videoCount > 0 { parts.append("\(group.videoCount) 段视频") }
        if group.livePhotoCount > 0 { parts.append("\(group.livePhotoCount) 张实况") }
        return parts.joined(separator: "，")
    }

    private func cell(_ asset: PHAsset) -> some View {
        let isOn = selected.contains(asset.localIdentifier)
        let kind = asset.mediaType == .video ? "视频" : "照片"
        let timestamp = asset.creationDate?.formatted(
            .dateTime.month().day().hour().minute().locale(Locale(identifier: "zh_CN"))) ?? ""
        return Button {
            if isOn {
                selected.remove(asset.localIdentifier)
                if selected.isEmpty { note = "" }
            } else {
                // 点进另一段时光时先清掉上一段选择，和“全选”保持同一规则。
                let groupIDs = groups.first(where: { $0.assetIdentifiers.contains(asset.localIdentifier) })?
                    .assetIdentifiers ?? []
                let allowed = Set(groupIDs)
                if !selected.isEmpty && selected.isDisjoint(with: allowed) { note = "" }
                selected = selected.intersection(allowed)
                selected.insert(asset.localIdentifier)
            }
            BubuHaptics.selection()
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let img = thumbs[asset.localIdentifier] {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        BubuTheme.Color.softFill
                    }
                }
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isOn ? BubuTheme.Color.primary : .clear, lineWidth: 3)
                }
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(BubuTheme.Font.scaled(20))
                    .foregroundStyle(isOn ? BubuTheme.Color.primary : .white.opacity(0.9))
                    .shadow(radius: 2)
                    .padding(4)

                if asset.mediaType == .video {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "video.fill")
                                .font(BubuTheme.Font.scaled(12, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                            Spacer()
                            Text(Self.durationText(asset.duration))
                                .font(BubuTheme.Font.scaled(10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                        .padding(6)
                    }
                }

                VStack {
                    Spacer()
                    HStack {
                        if let reason = selectionSignals[asset.localIdentifier]?.suppressionReason {
                            badge(Self.shortSuppressionLabel(reason), icon: "rectangle.on.rectangle.slash")
                        } else if Self.isScreenCapture(asset) {
                            badge("截图", icon: "rectangle.on.rectangle.slash")
                        } else if identityMatches[asset.localIdentifier]?.isLikelyChild == true {
                            badge("可能是布布", icon: "sparkles")
                        }
                        Spacer()
                    }
                    .padding(5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(timestamp) \(kind)")
        .accessibilityValue(isOn ? "已选择" : "未选择")
        .accessibilityHint("双击切换选择")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .contextMenu {
            if asset.mediaType == .image, identityRecognizer.isEnabled {
                Button("这是布布") { Task { await learnIdentity(asset, isChild: true) } }
                Button("不是布布") { Task { await learnIdentity(asset, isChild: false) } }
            }
        }
        .task {
            if thumbs[asset.localIdentifier] == nil {
                // 网格缩略图用本地优先 loader：不等 iCloud 下载、降级图也先显示——
                // 旧的 loadImage 在 iCloud 离线照片上永远等不到高清回调，格子永远灰着。
                thumbs[asset.localIdentifier] = await PhotoLibraryScanner.loadThumb(asset, targetPixel: 200)
            }
        }
    }

    private func clearNoteIfSwitching(to group: PhotoEventGroup) {
        let target = Set(group.assetIdentifiers)
        if !selected.isEmpty && selected.isDisjoint(with: target) {
            note = ""
            suggestionMessage = "已切换到另一段时光，上一段的备注没有带过来。"
        }
    }

    private func badge(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(BubuTheme.Font.scaled(8.5, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(BubuTheme.Color.warmBrown.opacity(0.82), in: Capsule())
    }

    private static func isScreenCapture(_ asset: PHAsset) -> Bool {
        asset.mediaSubtypes.contains(.photoScreenshot)
            || asset.mediaSubtypes.contains(.videoScreenRecording)
    }

    private static func shortSuppressionLabel(_ reason: String) -> String {
        if reason.contains("二维码") { return "二维码" }
        if reason.contains("文档") || reason.contains("票据") { return "文档" }
        return "截图"
    }

    /// 用户主动触发后才运行端侧精选：截图降级、近似照折叠、布布候选加标。
    /// 分析只用 ≤900px 预览，不读取或上传整批原片；视频在本版保留为独立候选。
    private func analyzeAndSelectSuggestions() async {
        analyzingSuggestions = true
        suggestionMessage = nil
        defer { analyzingSuggestions = false }

        let targetGroup = groups.first(where: { group in
            !selected.isDisjoint(with: group.assetIdentifiers)
        }) ?? groups.first
        guard let targetGroup else {
            suggestionMessage = "当前没有可以整理的素材。"
            return
        }
        let targetAssets = assets(in: targetGroup)
        let targetIDs = Set(targetGroup.assetIdentifiers)
        var nextSignals: [String: PhotoSelectionSignals] = selectionSignals.filter {
            !targetIDs.contains($0.key)
        }
        var nextMatches: [String: ChildIdentityMatch] = [:]
        for asset in targetAssets {
            let analysisFrames: [Data]
            if asset.mediaType == .video {
                analysisFrames = await PhotoLibraryScanner.loadVideoKeyframes(asset)
            } else if let image = await analysisImage(for: asset, targetPixel: 900),
                      let data = image.jpegData(compressionQuality: 0.82) {
                analysisFrames = [data]
            } else {
                analysisFrames = []
            }
            // 【卡顿修复】Vision（条码/文字/人脸/特征打印）每帧几十到几百毫秒。
            // 工程默认 MainActor 隔离 + 继承调用方 actor，直接调用会让整组照片的
            // 分析全部串行压在主线程——一组 20 张就是数秒可感冻结。
            // 入参 Data 与识别器都是 Sendable，整块下移 detached；PHAsset 不跨隔离域。
            let isShot = Self.isScreenCapture(asset)
            let recognizer = identityRecognizer
            let recognizerEnabled = recognizer.isEnabled
            let frames = analysisFrames
            let (bestSignals, bestMatch) = await Task.detached(priority: .userInitiated) {
                () -> (PhotoSelectionSignals?, ChildIdentityMatch?) in
                let frameSignals = frames.compactMap {
                    PhotoSelectionAnalyzer.analyze(imageData: $0, isScreenshot: isShot)
                }
                let signals = frameSignals.max(by: { $0.qualityScore < $1.qualityScore })
                var match: ChildIdentityMatch?
                if recognizerEnabled {
                    var matches: [ChildIdentityMatch] = []
                    for frame in frames {
                        matches.append(await recognizer.match(imageData: frame))
                    }
                    match = matches.max(by: { $0.confidence < $1.confidence })
                }
                return (signals, match)
            }.value
            if let bestSignals {
                nextSignals[asset.localIdentifier] = bestSignals
            }
            if let bestMatch {
                nextMatches[asset.localIdentifier] = bestMatch
            }
        }

        var suggestions = Set<String>()
        var hidden = Set<String>()
        let items = targetAssets.compactMap { asset -> PhotoSelectionItem? in
            guard asset.mediaType == .image else { return nil }
            guard let signals = nextSignals[asset.localIdentifier] else { return nil }
            return PhotoSelectionItem(identifier: asset.localIdentifier, signals: signals)
        }
        for similar in PhotoSelectionAnalyzer.groupSimilar(items) {
            suggestions.insert(similar.representativeIdentifier)
            hidden.formUnion(similar.memberIdentifiers.filter {
                $0 != similar.representativeIdentifier
            })
        }
        for video in targetAssets where video.mediaType == .video
            && nextSignals[video.localIdentifier]?.shouldSuppress != true
            && !Self.isScreenCapture(video) {
            suggestions.insert(video.localIdentifier)
        }

        selectionSignals = nextSignals
        identityMatches = nextMatches
        hiddenSimilarIDs = hidden
        expandedGroupIDs = []
        selected = suggestions
        let childCount = nextMatches.values.count { $0.isLikelyChild }
        let suppressedCount = nextSignals.values.count { $0.shouldSuppress }
        suggestionMessage = "只整理当前这一段：精选 \(suggestions.count) 个代表素材，折叠 \(hidden.count) 张近似照"
            + (suppressedCount > 0 ? "，默认跳过 \(suppressedCount) 个截图、录屏、二维码或文档" : "")
            + (childCount > 0 ? "；其中 \(childCount) 张可能是布布" : "")
            + "。原片一张也没有删除。"
        BubuHaptics.success()
    }

    private func learnIdentity(_ asset: PHAsset, isChild: Bool) async {
        guard let image = await analysisImage(for: asset, targetPixel: 1_200),
              let data = image.jpegData(compressionQuality: 0.9) else { return }
        do {
            let learned = try await identityRecognizer.learn(imageData: data, isChild: isChild)
            guard learned > 0 else {
                suggestionMessage = "这张照片没有检测到清楚的人脸，本机模型没有改动。"
                return
            }
            identityMatches[asset.localIdentifier] = await identityRecognizer.match(imageData: data)
            suggestionMessage = isChild
                ? "已在这台 iPhone 上记住“这是布布”。"
                : "已在这台 iPhone 上记住“不是布布”。"
            BubuHaptics.success()
        } catch {
            suggestionMessage = "本机反馈暂时没能保存，照片没有改动。"
        }
    }

    /// `??` 右侧是 autoclosure，不能放 async 调用；先取局部量也避免 Release
    /// whole-module 下捕获 PHAsset 时触发 Swift 6 sending 风险。
    private func analysisImage(for asset: PHAsset, targetPixel: CGFloat) async -> UIImage? {
        let identifier = asset.localIdentifier
        // 本地优先：端侧分析没必要为一张 iCloud 离线照片等网络下载，
        // 本地拿不到就退回网格缩略图，再不行跳过这张。
        let analyzed = await PhotoLibraryScanner.loadThumb(asset, targetPixel: targetPixel)
        if let analyzed { return analyzed }
        return thumbs[identifier]
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 库里是否已有同内容照片（contentHash 命中即重复；老数据 hash 为 nil 不参与判定）。
    private enum HashLookup {
        case missing
        case duplicate
        case unavailable
    }

    private static func lookupHash(_ hash: String, context: ModelContext) -> HashLookup {
        let descriptor = FetchDescriptor<Media>(predicate: #Predicate { $0.contentHash == hash })
        let matches: [Media]
        do { matches = try context.fetch(descriptor) }
        catch { return .unavailable }
        guard !matches.isEmpty else { return .missing }
        // 只要已有任一可见事实就判重；只有全部命中都归档时，才允许新建一条可见 Entry。
        return matches.contains { $0.entry?.isArchived != true } ? .duplicate : .missing
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            ProgressView("正在收好…").tint(.white).foregroundStyle(.white)
                .padding(28).background(BubuTheme.Color.warmBrown.opacity(0.92), in: RoundedRectangle(cornerRadius: 22))
        }
    }

    /// 保真导入：逐张取【原始字节】落盘（EXIF/GPS/HEIC 原样保留，不解码不重编码），
    /// 发生时间回填最早拍摄时间。逐张流式处理不整批驻留内存。
    /// 失败诚实上报：只把成功的照片标记"已处理"，失败的下次还会提示。
    private func importSelected() async {
        saving = true
        defer { saving = false }

        let chosen = assets.filter { selected.contains($0.localIdentifier) }
        let noteText = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let role = env.config.currentRole

        // iOS 26.4+ 把用户已经确认的这一段交给 PhotoKit 系统后台上传：锁屏、切 App、
        // 断网和重启后都由 intake.sqlite + mini staging 收敛。任何准备失败都安全回退
        // 下面原有的本地保真导入，不会丢掉用户这次选择。
        if await enqueueReliableBackgroundImport(
            chosen, note: noteText.isEmpty ? nil : noteText, role: role
        ) {
            BubuHaptics.success()
            onDone(PhotoImportOutcome(accepted: [], ignored: [], queued: chosen))
            dismiss()
            return
        }

        let entry = Entry(happenedAt: .now, authorRole: role.rawValue,
                          note: noteText.isEmpty ? nil : noteText)
        context.insert(entry)

        var okAssets: [PHAsset] = []
        var duplicateAssets: [PHAsset] = []   // 已收录过（contentHash 命中），跳过但标记已处理
        var earliestCapture: Date?
        var aggregatedTags: [String] = []
        var createdMedia: [Media] = []

        for asset in chosen {
            let media: Media
            var pairedLivePhotoMedia: Media?
            if asset.mediaType == .video {
                // 视频：导出原文件 → 压缩沙盒导入 + 视频缩略图（R4 E-6）
                guard let tmpURL = await PhotoLibraryScanner.loadVideoFile(asset) else { continue }
                guard let originalHash = try? MediaStore.sha256Hex(at: tmpURL) else {
                    try? FileManager.default.removeItem(at: tmpURL)
                    continue
                }
                switch Self.lookupHash(originalHash, context: context) {
                case .duplicate:
                    try? FileManager.default.removeItem(at: tmpURL)
                    duplicateAssets.append(asset)
                    continue
                case .unavailable:
                    try? FileManager.default.removeItem(at: tmpURL)
                    continue
                case .missing:
                    break
                }
                // 无论后续导入成功与否都清理 PhotoKit 导出的临时原片，避免失败重试累积孤儿文件。
                let importedResult = try? await env.mediaStore.importVideoForSync(from: tmpURL)
                try? FileManager.default.removeItem(at: tmpURL)
                guard let imported = importedResult else { continue }
                media = Media(type: .video, localFileName: imported.fileName)
                // 即使为公网传输生成了代理，也以 PhotoKit 原资源哈希做跨重试幂等。
                media.contentHash = originalHash
                media.durationSeconds = asset.duration
                media.thumbnailFileName = await env.mediaStore.makeVideoThumbnail(fromVideo: imported.fileName)
            } else {
                // 原始字节：失败（iCloud 没下载 + 无网等）计入失败，不静默
                guard let data = await PhotoLibraryScanner.loadOriginalData(asset) else { continue }
                // 重复收录拦截（V2 contentHash）：同一张照片之前已收过就跳过，
                // 但仍标记已处理（skippedDuplicates 也进 markHandled），避免明天再被提示。
                let hash = MediaStore.sha256Hex(data)
                switch Self.lookupHash(hash, context: context) {
                case .duplicate:
                    duplicateAssets.append(asset)
                    continue
                case .unavailable:
                    continue
                case .missing:
                    break
                }
                guard let fileName = try? env.mediaStore.savePhoto(data) else { continue }
                media = Media(type: .photo, localFileName: fileName)
                media.contentHash = hash
                if let thumbSource = UIImage(data: data) {
                    media.thumbnailFileName = env.mediaStore.makePhotoThumbnail(fromImage: thumbSource)
                }
                let analysis = await env.photoAnalyzer.analyze(imageData: data, includeLocation: false)
                media.aiTags = analysis.tags
                aggregatedTags.append(contentsOf: analysis.tags)

                if asset.mediaSubtypes.contains(.photoLive) {
                    // Live Photo 必须静态原片 + paired video 一起成功；任一失败都回滚静态文件，
                    // 候选保留到下次重试，不把“只有一半”的实况照片标成已收录。
                    guard let temporaryPair = await PhotoLibraryScanner.loadLivePhotoPairedVideo(asset) else {
                        env.mediaStore.deleteLocalFiles(media: media.localFileName,
                                                        thumbnail: media.thumbnailFileName)
                        continue
                    }
                    let importedPair = try? await env.mediaStore.importVideoForSync(from: temporaryPair)
                    try? FileManager.default.removeItem(at: temporaryPair)
                    guard let importedPair else {
                        env.mediaStore.deleteLocalFiles(media: media.localFileName,
                                                        thumbnail: media.thumbnailFileName)
                        continue
                    }
                    let pair = Media(type: .video, localFileName: importedPair.fileName)
                    pair.durationSeconds = asset.duration
                    pair.thumbnailFileName = await env.mediaStore.makeVideoThumbnail(
                        fromVideo: importedPair.fileName)
                    pair.aiTags = ["实况照片动态片段"]
                    pairedLivePhotoMedia = pair
                }
            }
            media.width = asset.pixelWidth
            media.height = asset.pixelHeight
            media.entry = entry
            context.insert(media)
            createdMedia.append(media)
            if let pairedLivePhotoMedia {
                pairedLivePhotoMedia.width = asset.pixelWidth
                pairedLivePhotoMedia.height = asset.pixelHeight
                pairedLivePhotoMedia.entry = entry
                context.insert(pairedLivePhotoMedia)
                createdMedia.append(pairedLivePhotoMedia)
            }
            okAssets.append(asset)
            if let taken = asset.creationDate {
                earliestCapture = min(earliestCapture ?? taken, taken)
            }
        }

        let failedCount = chosen.count - okAssets.count - duplicateAssets.count

        // 全是重复：不落空 Entry，标记已处理后温和告知（不算失败）
        if okAssets.isEmpty, !duplicateAssets.isEmpty, failedCount == 0 {
            context.delete(entry)
            BubuHaptics.tapLight()
            importError = "这 \(duplicateAssets.count) 张之前都收录过啦，没有重复保存。"
            onDone(PhotoImportOutcome(accepted: duplicateAssets, ignored: []))
            return
        }

        guard !okAssets.isEmpty else {
            // 一张都没成：即使填过附言也不落空 Entry；重复项可安全从候选移除，失败项保留重试。
            context.delete(entry)
            if !duplicateAssets.isEmpty {
                onDone(PhotoImportOutcome(accepted: duplicateAssets, ignored: []))
            }
            importError = "选中的素材没有成功读取（照片可能还在 iCloud 上没下载，连上网络后再试）。"
            return
        }

        if let capture = earliestCapture { entry.happenedAt = capture }   // 记"拍摄那一刻"
        do { try context.save() } catch {
            for media in createdMedia {
                env.mediaStore.deleteLocalFiles(media: media.localFileName,
                                                thumbnail: media.thumbnailFileName)
                context.delete(media)
            }
            context.delete(entry)
            importError = "保存失败：\(error.localizedDescription)"
            return
        }
        let summary = noteText.isEmpty ? "收录了今天的 \(okAssets.count) 张照片" : "记录了：\(noteText)"
        let event = FeedEvent(kind: .entryCreated, actorRole: role.rawValue,
                              summary: summary, targetLocalId: entry.id.uuidString,
                              happenedAt: entry.happenedAt)
        context.insert(event)
        try? context.save()

        env.syncEngine.syncNow()
        env.refreshWidgetSnapshot(context: context)

        // 只标记成功与重复；未选择、读取失败的素材继续留在智能收件箱。
        let acceptedAssets = okAssets + duplicateAssets
        let dupNote = duplicateAssets.isEmpty ? "" : "（\(duplicateAssets.count) 张之前收录过，自动跳过）"

        if failedCount > 0 {
            importError = "收好了 \(okAssets.count) 张\(dupNote)，另外 \(failedCount) 张没能读取（可能还在 iCloud 上），之后会再提醒你。"
            BubuHaptics.warning()
            onDone(PhotoImportOutcome(accepted: acceptedAssets, ignored: []))
            // 不立即 dismiss：让用户看到提示，点"知道了"后自己关
            return
        }
        BubuHaptics.success()
        onDone(PhotoImportOutcome(accepted: acceptedAssets, ignored: []))
        dismiss()
    }

    private func enqueueReliableBackgroundImport(
        _ chosen: [PHAsset],
        note: String?,
        role: FamilyRole
    ) async -> Bool {
        guard #available(iOS 26.4, *),
              env.config.isConfigured,
              let baseURL = env.config.aiBaseURL,
              // 公网大文件会受代理限制；视频继续走已有前台保真路径。
              chosen.allSatisfy({
                  $0.mediaType == .image && !$0.mediaSubtypes.contains(.photoLive)
              }) else { return false }
        let service = ReliablePhotoIntakeService(baseURL: baseURL) {
            try await env.apiClient.authenticate(role: "intake").token
        }
        do {
            try await service.enqueue(
                assets: chosen, note: note, authorRole: role.rawValue)
            return true
        } catch {
            // 可靠管线未建立时不把候选标记成功；直接走成熟的前台导入路径。
            return false
        }
    }
}
