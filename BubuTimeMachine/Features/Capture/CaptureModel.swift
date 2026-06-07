import SwiftUI
import SwiftData
import PhotosUI
import Observation

// MARK: - 记录此刻 业务模型
/// @Observable + @MainActor。负责把 PhotosPicker 选中的媒体落本地：
/// 写入 SwiftData（Entry + Media，syncState=.local）→ 存沙盒 → 生成缩略图。
/// M1 本地闭环核心：选片即可见，不依赖任何后端。
@Observable
@MainActor
final class CaptureModel {
    var showQuickCapture = false
    var pickedItems: [PhotosPickerItem] = []
    var isSaving = false
    var note: String = ""
    var savedFlash = false      // 保存成功的轻提示

    private let mediaStore: MediaStore
    private let role: FamilyRole

    init(mediaStore: MediaStore, role: FamilyRole) {
        self.mediaStore = mediaStore
        self.role = role
    }

    func startQuickCapture() {
        note = ""
        pickedItems = []
        showQuickCapture = true
    }

    /// 将已选媒体保存为一个 Entry。返回是否成功保存了至少一项。
    @discardableResult
    func savePickedItems(into context: ModelContext) async -> Bool {
        guard !pickedItems.isEmpty else { return false }
        isSaving = true
        defer { isSaving = false }

        let entry = Entry(happenedAt: .now, authorRole: role.rawValue,
                          note: note.isEmpty ? nil : note)
        context.insert(entry)

        var savedCount = 0
        for item in pickedItems {
            if let media = await persist(item: item) {
                media.entry = entry
                context.insert(media)
                savedCount += 1
            }
        }

        guard savedCount > 0 else {
            context.delete(entry)
            return false
        }

        do {
            try context.save()
        } catch {
            return false
        }

        // 清理 + 轻提示
        pickedItems = []
        note = ""
        showQuickCapture = false
        flashSaved()
        return true
    }

    /// 单个 PhotosPickerItem → 落沙盒 + 生成缩略图 → 返回 Media（未关联 entry）。
    private func persist(item: PhotosPickerItem) async -> Media? {
        // 视频
        if let movie = try? await item.loadTransferable(type: MovieTransfer.self) {
            guard let fileName = try? mediaStore.importFile(from: movie.url, preferredExtension: "mov")
            else { return nil }
            let media = Media(type: .video, localFileName: fileName)
            media.thumbnailFileName = await mediaStore.makeVideoThumbnail(fromVideo: fileName)
            return media
        }
        // 图片
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            guard let fileName = try? mediaStore.savePhoto(data) else { return nil }
            let media = Media(type: .photo, localFileName: fileName)
            media.width = Int(image.size.width)
            media.height = Int(image.size.height)
            media.thumbnailFileName = mediaStore.makePhotoThumbnail(fromImage: image)
            return media
        }
        return nil
    }

    private func flashSaved() {
        savedFlash = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            savedFlash = false
        }
    }
}

// MARK: - 视频可传输类型
/// PhotosPicker 视频导出到临时文件，再由 MediaStore 拷入沙盒。
struct MovieTransfer: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // 拷到临时目录，避免系统清理 received.file
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: temp)
            try FileManager.default.copyItem(at: received.file, to: temp)
            return MovieTransfer(url: temp)
        }
    }
}
