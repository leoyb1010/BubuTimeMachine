import SwiftUI
import SwiftData
import PhotosUI
import Observation
import AVFoundation

// MARK: - 记录此刻 业务模型
/// @Observable + @MainActor。把选中的媒体落本地并自动分析：
/// 写入 SwiftData（Entry + Media，syncState=.local）→ 存沙盒 → 缩略图 → 端侧分析。
/// 端侧分析（EXIF/地理/Vision）自动回填发生时间、地点、标签，零后端、隐私至上。
@Observable
@MainActor
final class CaptureModel {
    var showQuickCapture = false
    var pickedItems: [PhotosPickerItem] = []
    var cameraPhotos: [SelectedCameraPhoto] = []
    var cameraVideos: [SelectedCameraVideo] = []
    var selectedPreviews: [SelectedMediaPreview] = []
    var isLoadingPreviews = false
    var isSaving = false
    var saveError: String?
    /// 部分媒体导入失败：面板已关（记录已存），提示上移到首页层展示，避免随面板一起消失。
    var partialSaveWarning: String?
    var lastSavedSummary: String?
    var note: String = ""
    var mood: Mood?
    var includeLocation = false
    var currentLocation: CapturedLocation?
    var locationError: String?
    var savedFlash = false

    /// 录好的语音（待随本次记录一起保存）。
    var pendingVoice: (fileName: String, duration: Double, waveform: [Float])?

    /// 分析进度提示文案（"正在看看这张照片…"）。
    var analyzingHint: String?
    /// 本次分析聚合出的标签，用于保存后给用户看见"机器看懂了什么"。
    var detectedTags: [String] = []
    var detectedLocation: String?

    /// 最近一次保存的 Entry id 与其标签（供首页做"第一次"识别）。
    var lastSavedEntryID: UUID?

    private let mediaStore: MediaStore
    private let analyzer: PhotoAnalyzer
    /// 署名身份。可变：切换家庭成员后由视图层刷新，避免新记录署到旧身份头上。
    var role: FamilyRole

    /// 预览加载单飞任务：新选择会取消旧任务，防止两个任务交错后网格与底层数组错位。
    private var previewTask: Task<Void, Never>?

    init(mediaStore: MediaStore, analyzer: PhotoAnalyzer, role: FamilyRole) {
        self.mediaStore = mediaStore
        self.analyzer = analyzer
        self.role = role
    }

    /// 丢弃未保存的待存语音：删掉已 importFile 落盘的 m4a，再清引用，避免孤儿文件。
    /// 仅用于「用户主动丢弃」或「开新记录前清残留」；保存成功后语音已归属 entry，
    /// 走 pendingVoice = nil 而非此方法，切勿误删。
    func discardPendingVoice() {
        if let v = pendingVoice {
            mediaStore.deleteMedia(named: v.fileName)
        }
        pendingVoice = nil
    }

    func startQuickCapture(prefillNote: String = "") {
        note = prefillNote
        mood = nil
        includeLocation = false
        currentLocation = nil
        locationError = nil
        pickedItems = []
        cameraPhotos = []
        cameraVideos = []
        selectedPreviews = []
        discardPendingVoice()
        detectedTags = []
        detectedLocation = nil
        analyzingHint = nil
        saveError = nil
        lastSavedSummary = nil
        showQuickCapture = true
    }

    /// 是否有可保存内容（媒体 / 文字 / 语音 任一即可）。
    var canSave: Bool {
        !pickedItems.isEmpty || !cameraPhotos.isEmpty || !cameraVideos.isEmpty || !trimmedNote.isEmpty || pendingVoice != nil
    }

    private var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 保存为一个 Entry。返回是否成功。
    @discardableResult
    func savePickedItems(into context: ModelContext) async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }

        let noteText = trimmedNote
        let entry = Entry(happenedAt: .now, authorRole: role.rawValue,
                          note: noteText.isEmpty ? nil : noteText)
        entry.mood = mood
        context.insert(entry)

        // 媒体 + 分析聚合
        var earliestCapture: Date?
        var aggregatedTags: [String] = []
        var locationName: String?
        var coordinate: (Double, Double)?

        var savedCount = 0
        for photo in cameraPhotos {
            guard let (media, analysis) = await persist(cameraPhoto: photo) else { continue }
            media.entry = entry
            context.insert(media)
            savedCount += 1

            if let a = analysis {
                aggregatedTags.append(contentsOf: a.tags)
                media.aiTags = a.tags
                if locationName == nil { locationName = a.locationName }
                if coordinate == nil, let lat = a.latitude, let lon = a.longitude {
                    coordinate = (lat, lon)
                }
            }
        }
        for item in pickedItems {
            guard let (media, analysis) = await persist(item: item) else { continue }
            media.entry = entry
            context.insert(media)
            savedCount += 1

            if let a = analysis {
                if let d = a.captureDate {
                    earliestCapture = min(earliestCapture ?? d, d)
                }
                aggregatedTags.append(contentsOf: a.tags)
                media.aiTags = a.tags
                if locationName == nil { locationName = a.locationName }
                if coordinate == nil, let lat = a.latitude, let lon = a.longitude {
                    coordinate = (lat, lon)
                }
            }
        }
        for video in cameraVideos {
            guard let media = await persist(cameraVideo: video) else { continue }
            media.entry = entry
            context.insert(media)
            savedCount += 1
        }

        // 语音
        if let v = pendingVoice {
            let voice = VoiceNote(localFileName: v.fileName, durationSeconds: v.duration,
                                  authorRole: role.rawValue, waveformSamples: v.waveform)
            voice.entry = entry
            context.insert(voice)
            // 端侧自动转写（尽力而为）：成功后这段话就能被搜索/问答找到（R4 E-1）
            let url = mediaStore.mediaURL(for: v.fileName)
            Task { @MainActor in
                if let text = await VoiceTranscriber.transcribe(url: url) {
                    voice.transcript = text
                    try? context.save()
                }
            }
        }

        let expectedMedia = cameraPhotos.count + cameraVideos.count + pickedItems.count
        let failedMedia = expectedMedia - savedCount

        guard savedCount > 0 || !noteText.isEmpty || pendingVoice != nil else {
            context.delete(entry)
            saveError = expectedMedia > 0
                ? "选中的 \(expectedMedia) 个媒体都没能导入（照片可能还在 iCloud 上没下载，连上网络后再试）。"
                : "没有成功导入媒体或文字，请重新选择。"
            return false
        }

        // 应用分析结果
        if let capture = earliestCapture { entry.happenedAt = capture }
        // 反向地理编码只对首张有 GPS 的照片做一次（各张分析时已跳过，这里统一补一次），
        // 避免多选照片时每张各发一次反向地理编码。
        if includeLocation, locationName == nil, let (lat, lon) = coordinate {
            locationName = await analyzer.locationName(latitude: lat, longitude: lon)
        }
        if includeLocation,
           locationName == nil,
           coordinate == nil,
           let currentLocation {
            locationName = currentLocation.name
            coordinate = (currentLocation.latitude, currentLocation.longitude)
        }
        if includeLocation, let loc = locationName { entry.locationName = loc }
        if includeLocation, let (lat, lon) = coordinate { entry.latitude = lat; entry.longitude = lon }

        let uniqueTags = Array(Set(aggregatedTags)).prefix(6)
        detectedTags = Array(uniqueTags)
        detectedLocation = includeLocation ? locationName : nil

        do { try context.save() } catch {
            // 保存失败：回滚本次插入的 entry/media/voice，避免脏对象留在 context，
            // 否则用户重试会再插一条新 entry → 重复记录。
            context.rollback()
            saveError = "保存失败：\(error.localizedDescription)"
            return false
        }
        let event = FeedEvent(kind: .entryCreated, actorRole: role.rawValue,
                              summary: noteText.isEmpty ? "记录了布布的一个新瞬间" : "记录了：\(noteText)",
                              targetLocalId: entry.id.uuidString, happenedAt: entry.happenedAt)
        context.insert(event)
        try? context.save()
        refreshWidgetSnapshot(context: context)

        lastSavedEntryID = entry.id
        let mediaText = savedCount > 0 ? " · \(savedCount) 个媒体" : ""
        let voiceText = pendingVoice == nil ? "" : " · 1 段语音"
        lastSavedSummary = "已保存到手机\(mediaText)\(voiceText)"
        // 部分媒体失败：诚实告知，不再"静默丢照片装成功"。
        // 面板随即关闭（记录已存），提示走 partialSaveWarning 在首页层弹出，否则 alert 随面板一起消失、用户看不到。
        if failedMedia > 0 {
            partialSaveWarning = "有 \(failedMedia) 个媒体没能导入（可能还在 iCloud 上没下载）。文字已保存，照片请稍后重新选择补上。"
        }
        pickedItems = []
        cameraPhotos = []
        cameraVideos = []
        selectedPreviews = []
        note = ""
        mood = nil
        pendingVoice = nil
        showQuickCapture = false
        flashSaved()
        return true
    }

    /// 重建预览网格。单飞：再次调用会取消上一次，收尾前检查取消位，
    /// 保证 selectedPreviews 永远对应【最新】的选择状态（否则加载间隙点 X 会删错媒体）。
    func updatePreviews() {
        previewTask?.cancel()
        previewTask = Task { await rebuildPreviews() }
    }

    private func rebuildPreviews() async {
        let items = pickedItems
        isLoadingPreviews = !items.isEmpty
        defer { if !Task.isCancelled { isLoadingPreviews = false } }

        var previews: [SelectedMediaPreview] = cameraPhotos.enumerated().map { index, photo in
            SelectedMediaPreview(index: index, image: photo.image, isVideo: false, label: "拍照")
        }
        previews += cameraVideos.enumerated().map { offset, video in
            SelectedMediaPreview(index: cameraPhotos.count + offset, image: video.thumbnail, isVideo: true, label: "录像")
        }
        let baseCount = cameraPhotos.count + cameraVideos.count
        for (offset, item) in items.enumerated() {
            if Task.isCancelled { return }
            let index = baseCount + offset
            if let movie = try? await item.loadTransferable(type: MovieTransfer.self) {
                let image = await Self.videoPreviewImage(url: movie.url)
                // MovieTransfer 每次都把视频拷一份到 tmp，用完即删，避免 .mov 孤儿堆积。
                try? FileManager.default.removeItem(at: movie.url)
                previews.append(SelectedMediaPreview(index: index, image: image, isVideo: true, label: "视频"))
                continue
            }
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                // 预览只留 ~600px 小图：全尺寸位图多选时会 OOM；保存时会重新取原始数据
                let thumb = await image.byPreparingThumbnail(ofSize: Self.previewSize(for: image.size)) ?? image
                previews.append(SelectedMediaPreview(index: index, image: thumb, isVideo: false, label: "照片"))
            } else {
                previews.append(SelectedMediaPreview(index: index, image: nil, isVideo: false, label: "媒体"))
            }
        }
        guard !Task.isCancelled else { return }
        selectedPreviews = previews
    }

    private static func previewSize(for size: CGSize) -> CGSize {
        let maxSide = max(size.width, size.height)
        guard maxSide > 600, maxSide > 0 else { return size }
        let scale = 600 / maxSide
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func removePickedItem(at index: Int) {
        if cameraPhotos.indices.contains(index) {
            cameraPhotos.remove(at: index)
        } else if index - cameraPhotos.count >= 0 && index - cameraPhotos.count < cameraVideos.count {
            cameraVideos.remove(at: index - cameraPhotos.count)
        } else {
            let pickedIndex = index - cameraPhotos.count - cameraVideos.count
            guard pickedItems.indices.contains(pickedIndex) else { return }
            pickedItems.remove(at: pickedIndex)
        }
        selectedPreviews.removeAll { $0.index == index }
        selectedPreviews = selectedPreviews.enumerated().map { offset, preview in
            SelectedMediaPreview(index: offset, image: preview.image, isVideo: preview.isVideo, label: preview.label)
        }
    }

    func addCameraPhoto(_ image: UIImage) {
        cameraPhotos.append(SelectedCameraPhoto(image: image))
        updatePreviews()
    }

    /// 直接录像：拷入沙盒临时位置，生成缩略图，加入待保存列表。
    func addCameraVideo(url: URL) {
        Task {
            let thumb = await Self.videoPreviewImage(url: url)
            cameraVideos.append(SelectedCameraVideo(url: url, thumbnail: thumb))
            updatePreviews()
        }
    }

    private func persist(cameraVideo: SelectedCameraVideo) async -> Media? {
        analyzingHint = "正在整理这段录像，太大时会先压缩…"
        defer { analyzingHint = nil }
        guard let imported = try? await mediaStore.importVideoForSync(from: cameraVideo.url) else { return nil }
        let fileName = imported.fileName
        let media = Media(type: .video, localFileName: fileName)
        if imported.wasCompressed { media.aiTags = ["已压缩", "视频"] }
        media.thumbnailFileName = await mediaStore.makeVideoThumbnail(fromVideo: fileName)
        return media
    }

    private func persist(cameraPhoto: SelectedCameraPhoto) async -> (Media, PhotoAnalysis?)? {
        guard let data = cameraPhoto.image.jpegData(compressionQuality: 0.92),
              let fileName = try? mediaStore.savePhoto(data) else { return nil }
        let media = Media(type: .photo, localFileName: fileName)
        media.width = Int(cameraPhoto.image.size.width)
        media.height = Int(cameraPhoto.image.size.height)
        media.thumbnailFileName = mediaStore.makePhotoThumbnail(fromImage: cameraPhoto.image)
        analyzingHint = "正在看看这张照片里有什么…"
        let analysis = await analyzer.analyze(imageData: data, includeLocation: includeLocation, resolveLocationName: false)
        analyzingHint = nil
        return (media, analysis)
    }

    private static func videoPreviewImage(url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let cg = try? await generator.image(at: .zero).image {
            return UIImage(cgImage: cg)
        }
        return nil
    }

    /// 单个 PhotosPickerItem → 落沙盒 + 缩略图 + 端侧分析。
    private func persist(item: PhotosPickerItem) async -> (Media, PhotoAnalysis?)? {
        // 视频（暂不分析，仅缩略图）
        if let movie = try? await item.loadTransferable(type: MovieTransfer.self) {
            analyzingHint = "正在整理这段视频，太大时会先压缩…"
            // importVideoForSync 已把视频拷进媒体目录，MovieTransfer 的 tmp 拷贝用完即删，避免 .mov 孤儿。
            defer { try? FileManager.default.removeItem(at: movie.url) }
            guard let imported = try? await mediaStore.importVideoForSync(from: movie.url) else {
                analyzingHint = nil
                return nil
            }
            analyzingHint = nil
            let fileName = imported.fileName
            let media = Media(type: .video, localFileName: fileName)
            if imported.wasCompressed {
                media.aiTags = ["已压缩", "视频"]
            }
            media.thumbnailFileName = await mediaStore.makeVideoThumbnail(fromVideo: fileName)
            return (media, nil)
        }
        // 图片
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            guard let fileName = try? mediaStore.savePhoto(data) else { return nil }
            let media = Media(type: .photo, localFileName: fileName)
            media.width = Int(image.size.width)
            media.height = Int(image.size.height)
            media.thumbnailFileName = mediaStore.makePhotoThumbnail(fromImage: image)

            analyzingHint = "正在看看这张照片里有什么…"
            let analysis = await analyzer.analyze(imageData: data, includeLocation: includeLocation, resolveLocationName: false)
            analyzingHint = nil
            return (media, analysis)
        }
        return nil
    }

    private func flashSaved() {
        BubuHaptics.success()
        BubuSound.play(.save)
        withAnimation(BubuMotion.gentle) { savedFlash = true }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(BubuMotion.gentle) { savedFlash = false }
        }
    }

    private func refreshWidgetSnapshot(context: ModelContext) {
        guard let snapshot = SharedWidgetSnapshot.make(context: context) else { return }
        SharedDefaults.saveWidgetSnapshot(snapshot)
        WidgetRefresher.reload()
    }
}

// MARK: - 相机照片
struct SelectedCameraPhoto: Identifiable, Sendable {
    let id = UUID()
    let image: UIImage
}

// MARK: - 相机录像
struct SelectedCameraVideo: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let thumbnail: UIImage?
}

// MARK: - 选择媒体预览
struct SelectedMediaPreview: Identifiable, Sendable {
    let id = UUID()
    let index: Int
    let image: UIImage?
    let isVideo: Bool
    let label: String
}

// MARK: - 视频可传输类型
struct MovieTransfer: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: temp)
            try FileManager.default.copyItem(at: received.file, to: temp)
            return MovieTransfer(url: temp)
        }
    }
}
