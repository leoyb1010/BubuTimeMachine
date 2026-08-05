import SwiftUI
import SwiftData
import Photos
import UIKit

struct PhotoImportOutcome {
    let accepted: [PHAsset]
    let ignored: [PHAsset]
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

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            groupHeader(group)
                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(assets(in: group), id: \.localIdentifier) { asset in
                                    cell(asset)
                                }
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
        HStack(spacing: 10) {
            Text("📸").font(BubuTheme.Font.scaled(30))
            Text("已经按时间和地点整理成 \(groups.count) 段。选好一段，一次收进时光轴。")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            Spacer(minLength: 0)
        }
    }

    private func assets(in group: PhotoEventGroup) -> [PHAsset] {
        let wanted = Set(group.assetIdentifiers)
        return assets.filter { wanted.contains($0.localIdentifier) }
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
                } else {
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
            if isOn { selected.remove(asset.localIdentifier) } else { selected.insert(asset.localIdentifier) }
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
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(timestamp) \(kind)")
        .accessibilityValue(isOn ? "已选择" : "未选择")
        .accessibilityHint("双击切换选择")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .task {
            if thumbs[asset.localIdentifier] == nil {
                thumbs[asset.localIdentifier] = await PhotoLibraryScanner.loadImage(asset, targetPixel: 200)
            }
        }
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 库里是否已有同内容照片（contentHash 命中即重复；老数据 hash 为 nil 不参与判定）。
    private static func hashExists(_ hash: String, context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<Media>(predicate: #Predicate { $0.contentHash == hash })
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
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
            if asset.mediaType == .video {
                // 视频：导出原文件 → 压缩沙盒导入 + 视频缩略图（R4 E-6）
                guard let tmpURL = await PhotoLibraryScanner.loadVideoFile(asset) else { continue }
                // 无论后续导入成功与否都清理 PhotoKit 导出的临时原片，避免失败重试累积孤儿文件。
                let importedResult = try? await env.mediaStore.importVideoForSync(from: tmpURL)
                try? FileManager.default.removeItem(at: tmpURL)
                guard let imported = importedResult else { continue }
                media = Media(type: .video, localFileName: imported.fileName)
                media.durationSeconds = asset.duration
                media.thumbnailFileName = await env.mediaStore.makeVideoThumbnail(fromVideo: imported.fileName)
            } else {
                // 原始字节：失败（iCloud 没下载 + 无网等）计入失败，不静默
                guard let data = await PhotoLibraryScanner.loadOriginalData(asset) else { continue }
                // 重复收录拦截（V2 contentHash）：同一张照片之前已收过就跳过，
                // 但仍标记已处理（skippedDuplicates 也进 markHandled），避免明天再被提示。
                let hash = MediaStore.sha256Hex(data)
                if Self.hashExists(hash, context: context) {
                    duplicateAssets.append(asset)
                    continue
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
            }
            media.width = asset.pixelWidth
            media.height = asset.pixelHeight
            media.entry = entry
            context.insert(media)
            createdMedia.append(media)
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
}
