import SwiftUI
import SwiftData
import Photos
import UIKit

// MARK: - 今天拍的照片 · 一键收进时光机
/// 首页卡片点进来：网格展示今天新增的照片，多选后一键收录成时光轴记录（可加一句话）。
struct TodayPhotosSheet: View {
    let assets: [PHAsset]
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let onDone: ([PHAsset]) -> Void   // 处理过的资产（收录或全部忽略）回传给首页标记

    @State private var selected: Set<String> = []
    @State private var thumbs: [String: UIImage] = [:]
    @State private var note = ""
    @State private var saving = false
    @State private var importError: String?

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            cell(asset)
                        }
                    }
                    if !selected.isEmpty {
                        TextField("给这些照片配一句话（可选）", text: $note, axis: .vertical)
                            .font(BubuTheme.Font.body)
                            .padding(12)
                            .background(BubuTheme.Color.softFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding()
            }
            .background(BubuTheme.Color.background.ignoresSafeArea())
            .navigationTitle("今天拍的")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("全部忽略") { onDone(assets); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "收好" : "收好 \(selected.count) 张") {
                        Task { await importSelected() }
                    }
                    .fontWeight(.bold)
                    .disabled(selected.isEmpty || saving)
                }
            }
            .overlay { if saving { savingOverlay } }
            .alert("有照片没能收录", isPresented: Binding(
                get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("📸").font(.system(size: 30))
            Text("挑出布布的照片，点「收好」就进时光轴啦")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            Spacer(minLength: 0)
        }
    }

    private func cell(_ asset: PHAsset) -> some View {
        let isOn = selected.contains(asset.localIdentifier)
        return ZStack(alignment: .topTrailing) {
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
                .font(.system(size: 20))
                .foregroundStyle(isOn ? BubuTheme.Color.primary : .white.opacity(0.9))
                .shadow(radius: 2)
                .padding(4)

            if asset.mediaType == .video {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "video.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                        Spacer()
                        Text(Self.durationText(asset.duration))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                    .padding(6)
                }
            }
        }
        .onTapGesture {
            if isOn { selected.remove(asset.localIdentifier) } else { selected.insert(asset.localIdentifier) }
            BubuHaptics.selection()
        }
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
        var earliestCapture: Date?
        var aggregatedTags: [String] = []

        for asset in chosen {
            let media: Media
            if asset.mediaType == .video {
                // 视频：导出原文件 → 压缩沙盒导入 + 视频缩略图（R4 E-6）
                guard let tmpURL = await PhotoLibraryScanner.loadVideoFile(asset),
                      let imported = try? await env.mediaStore.importVideoForSync(from: tmpURL) else { continue }
                try? FileManager.default.removeItem(at: tmpURL)
                media = Media(type: .video, localFileName: imported.fileName)
                media.durationSeconds = asset.duration
                media.thumbnailFileName = await env.mediaStore.makeVideoThumbnail(fromVideo: imported.fileName)
            } else {
                // 原始字节：失败（iCloud 没下载 + 无网等）计入失败，不静默
                guard let data = await PhotoLibraryScanner.loadOriginalData(asset),
                      let fileName = try? env.mediaStore.savePhoto(data) else { continue }
                media = Media(type: .photo, localFileName: fileName)
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
            okAssets.append(asset)
            if let taken = asset.creationDate {
                earliestCapture = min(earliestCapture ?? taken, taken)
            }
        }

        let failedCount = chosen.count - okAssets.count

        guard !okAssets.isEmpty || !noteText.isEmpty else {
            // 一张都没成：不落 Entry、不标记、不关面板
            context.delete(entry)
            importError = "选中的 \(chosen.count) 张都没能读取（照片可能还在 iCloud 上没下载，连上网络后再试）。"
            return
        }

        if let capture = earliestCapture { entry.happenedAt = capture }   // 记"拍摄那一刻"
        do { try context.save() } catch {
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

        // 只标记：成功收录的 + 用户看过但没选的；失败的留着下次再提示
        let failedIDs = Set(chosen.map(\.localIdentifier)).subtracting(okAssets.map(\.localIdentifier))
        let toMark = assets.filter { !failedIDs.contains($0.localIdentifier) }

        if failedCount > 0 {
            importError = "收好了 \(okAssets.count) 张，另外 \(failedCount) 张没能读取（可能还在 iCloud 上），之后会再提醒你。"
            BubuHaptics.warning()
            onDone(toMark)
            // 不立即 dismiss：让用户看到提示，点"知道了"后自己关
            return
        }
        BubuHaptics.success()
        onDone(toMark)
        dismiss()
    }
}
