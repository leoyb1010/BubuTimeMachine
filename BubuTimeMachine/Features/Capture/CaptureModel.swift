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
    var selectedPreviews: [SelectedMediaPreview] = []
    var isLoadingPreviews = false
    var isSaving = false
    var saveError: String?
    var lastSavedSummary: String?
    var note: String = ""
    var mood: Mood?
    var includeLocation = false
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
    private let role: FamilyRole

    init(mediaStore: MediaStore, analyzer: PhotoAnalyzer, role: FamilyRole) {
        self.mediaStore = mediaStore
        self.analyzer = analyzer
        self.role = role
    }

    func startQuickCapture() {
        note = ""
        mood = nil
        includeLocation = false
        pickedItems = []
        cameraPhotos = []
        selectedPreviews = []
        pendingVoice = nil
        detectedTags = []
        detectedLocation = nil
        analyzingHint = nil
        saveError = nil
        lastSavedSummary = nil
        showQuickCapture = true
    }

    /// 是否有可保存内容（媒体 / 文字 / 语音 任一即可）。
    var canSave: Bool {
        !pickedItems.isEmpty || !cameraPhotos.isEmpty || !note.isEmpty || pendingVoice != nil
    }

    /// 保存为一个 Entry。返回是否成功。
    @discardableResult
    func savePickedItems(into context: ModelContext) async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }

        let entry = Entry(happenedAt: .now, authorRole: role.rawValue,
                          note: note.isEmpty ? nil : note)
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

        // 语音
        if let v = pendingVoice {
            let voice = VoiceNote(localFileName: v.fileName, durationSeconds: v.duration,
                                  authorRole: role.rawValue, waveformSamples: v.waveform)
            voice.entry = entry
            context.insert(voice)
        }

        guard savedCount > 0 || !note.isEmpty || pendingVoice != nil else {
            context.delete(entry)
            saveError = "没有成功导入媒体或文字，请重新选择。"
            return false
        }

        // 应用分析结果
        if let capture = earliestCapture { entry.happenedAt = capture }
        if includeLocation, let loc = locationName { entry.locationName = loc }
        if includeLocation, let (lat, lon) = coordinate { entry.latitude = lat; entry.longitude = lon }

        let uniqueTags = Array(Set(aggregatedTags)).prefix(6)
        detectedTags = Array(uniqueTags)
        detectedLocation = includeLocation ? locationName : nil

        do { try context.save() } catch {
            saveError = "保存失败：\(error.localizedDescription)"
            return false
        }
        let event = FeedEvent(kind: .entryCreated, actorRole: role.rawValue,
                              summary: note.isEmpty ? "记录了布布的一个新瞬间" : "记录了：\(note)",
                              targetLocalId: entry.id.uuidString, happenedAt: entry.happenedAt)
        context.insert(event)
        try? context.save()

        lastSavedEntryID = entry.id
        let mediaText = savedCount > 0 ? " · \(savedCount) 个媒体" : ""
        let voiceText = pendingVoice == nil ? "" : " · 1 段语音"
        lastSavedSummary = "已保存到手机\(mediaText)\(voiceText)"
        pickedItems = []
        cameraPhotos = []
        selectedPreviews = []
        note = ""
        mood = nil
        pendingVoice = nil
        showQuickCapture = false
        flashSaved()
        return true
    }

    func updatePreviews() async {
        let items = pickedItems
        isLoadingPreviews = !items.isEmpty
        defer { isLoadingPreviews = false }

        var previews: [SelectedMediaPreview] = cameraPhotos.enumerated().map { index, photo in
            SelectedMediaPreview(index: index, image: photo.image, isVideo: false, label: "拍照")
        }
        for (offset, item) in items.enumerated() {
            let index = cameraPhotos.count + offset
            if let movie = try? await item.loadTransferable(type: MovieTransfer.self) {
                let image = await Self.videoPreviewImage(url: movie.url)
                previews.append(SelectedMediaPreview(index: index, image: image, isVideo: true, label: "视频"))
                continue
            }
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                previews.append(SelectedMediaPreview(index: index, image: image, isVideo: false, label: "照片"))
            } else {
                previews.append(SelectedMediaPreview(index: index, image: nil, isVideo: false, label: "媒体"))
            }
        }
        selectedPreviews = previews
    }

    func removePickedItem(at index: Int) {
        if cameraPhotos.indices.contains(index) {
            cameraPhotos.remove(at: index)
        } else {
            let pickedIndex = index - cameraPhotos.count
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
        Task { await updatePreviews() }
    }

    private func persist(cameraPhoto: SelectedCameraPhoto) async -> (Media, PhotoAnalysis?)? {
        guard let data = cameraPhoto.image.jpegData(compressionQuality: 0.92),
              let fileName = try? mediaStore.savePhoto(data) else { return nil }
        let media = Media(type: .photo, localFileName: fileName)
        media.width = Int(cameraPhoto.image.size.width)
        media.height = Int(cameraPhoto.image.size.height)
        media.thumbnailFileName = mediaStore.makePhotoThumbnail(fromImage: cameraPhoto.image)
        analyzingHint = "正在看看这张照片里有什么…"
        let analysis = await analyzer.analyze(imageData: data, includeLocation: includeLocation)
        analyzingHint = nil
        return (media, analysis)
    }

    private static func videoPreviewImage(url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            if let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                return UIImage(cgImage: cg)
            }
            return nil
        }.value
    }

    /// 单个 PhotosPickerItem → 落沙盒 + 缩略图 + 端侧分析。
    private func persist(item: PhotosPickerItem) async -> (Media, PhotoAnalysis?)? {
        // 视频（暂不分析，仅缩略图）
        if let movie = try? await item.loadTransferable(type: MovieTransfer.self) {
            guard let fileName = try? mediaStore.importFile(from: movie.url, preferredExtension: "mov")
            else { return nil }
            let media = Media(type: .video, localFileName: fileName)
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
            let analysis = await analyzer.analyze(imageData: data, includeLocation: includeLocation)
            analyzingHint = nil
            return (media, analysis)
        }
        return nil
    }

    private func flashSaved() {
        savedFlash = true
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            savedFlash = false
        }
    }
}

// MARK: - 相机照片
struct SelectedCameraPhoto: Identifiable, Sendable {
    let id = UUID()
    let image: UIImage
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
