import Foundation
import Observation

// MARK: - 上传队列（后台、可恢复）
/// 序列化上传任务，驱动 Media.uploadProgress。M1 阶段仅本地，不实际上传；
/// 真实分片上传 + 后台 URLSession + 断点续传将在 M2 接入 PocketBaseClient。
@Observable
@MainActor
final class UploadQueue {
    /// mediaId -> 当前进度（0...1），供 UI 进度条观察。
    private(set) var activeTasks: [UUID: Double] = [:]

    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// 入队一个上传请求。M2 起会写入持久队列并由后台 URLSession 执行。
    func enqueue(_ request: MediaUploadRequest, onProgress: @escaping @MainActor (Double) -> Void,
                 onCompleted: @escaping @MainActor (_ remoteId: String, _ url: String) -> Void) {
        activeTasks[request.mediaId] = 0
        Task {
            do {
                for try await event in apiClient.uploadMedia(request) {
                    switch event {
                    case .progress(let p):
                        activeTasks[request.mediaId] = p
                        onProgress(p)
                    case .completed(let remoteId, let url):
                        activeTasks[request.mediaId] = 1
                        onCompleted(remoteId, url)
                        activeTasks[request.mediaId] = nil
                    }
                }
            } catch {
                // 失败保留在本地，等待重试（指数退避将在 M2 实现）
                activeTasks[request.mediaId] = nil
            }
        }
    }

    /// 重试所有失败任务（指数退避，M2 实现）。
    func retryFailed() {
        // M2：扫描 syncState == .failed 的 Media 重新入队
    }
}
