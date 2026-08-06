import CryptoKit
import Foundation
import Photos
import UniformTypeIdentifiers

/// iOS 26.1+ reliable path: confirmed PhotoKit resources are registered with the
/// system background uploader and tracked in the App Group intake database.
@MainActor
struct ReliablePhotoIntakeService {
    enum IntakeError: LocalizedError {
        case unavailable
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "系统后台照片上传暂不可用，已保留原来的前台导入方式。"
            case .invalidResponse: "家里的服务器没有返回完整上传清单。"
            case .server(let message): message
            }
        }
    }

    private struct ResourceSpec {
        let assetKey: String
        let assetGroupID: String
        let asset: PHAsset
        let resource: PHAssetResource
        let mediaType: String
        let role: String
    }

    private struct Destination: Decodable {
        let assetKey: String
        let url: String
        let uploadToken: String

        enum CodingKeys: String, CodingKey {
            case assetKey = "asset_key"
            case url
            case uploadToken = "upload_token"
        }
    }

    private struct CreateResponse: Decodable {
        let destinations: [Destination]
    }

    let baseURL: URL
    let tokenProvider: @Sendable () async throws -> String
    let store: PhotoIntakeStore

    init(
        baseURL: URL,
        store: PhotoIntakeStore = PhotoIntakeStore(),
        tokenProvider: @escaping @Sendable () async throws -> String
    ) {
        self.baseURL = baseURL
        self.store = store
        self.tokenProvider = tokenProvider
    }

    func enqueue(
        assets: [PHAsset],
        note: String?,
        authorRole: String
    ) async throws {
        guard #available(iOS 26.4, *),
              PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            throw IntakeError.unavailable
        }
        let batchID = UUID().uuidString
        let resources = assets.flatMap { Self.resourceSpecs(for: $0, batchID: batchID) }
        guard !resources.isEmpty else { throw IntakeError.unavailable }

        let entryLocalID = UUID().uuidString
        let happenedAt = assets.compactMap(\.creationDate).min() ?? .now
        let iso = ISO8601DateFormatter()
        let items: [[String: Any]] = resources.map { spec in
            [
                "asset_key": spec.assetKey,
                "asset_group_id": spec.assetGroupID,
                "file_name": spec.resource.originalFilename,
                "media_type": spec.mediaType,
                "captured_at": iso.string(from: spec.asset.creationDate ?? happenedAt),
                // PHAssetResource intentionally exposes no preflight byte count.
                "expected_size": 0,
                "expected_mime": spec.resource.contentType.preferredMIMEType
                    ?? "application/octet-stream",
                "resource_role": spec.role,
            ]
        }
        let body: [String: Any] = [
            "batch_id": batchID,
            "entry": [
                "local_id": entryLocalID,
                "happened_at": iso.string(from: happenedAt),
                "author_role": authorRole,
                "note": note ?? "",
                "source": "iphone-photo-library",
            ],
            "items": items,
        ]
        var request = URLRequest(url: baseURL.appendingPathComponent("intake/batches"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw IntakeError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw IntakeError.server(detail ?? "家里的服务器暂时没能建立上传批次。")
        }
        let destinations = try JSONDecoder().decode(CreateResponse.self, from: data).destinations
        let byKey = Dictionary(uniqueKeysWithValues: destinations.map { ($0.assetKey, $0) })
        guard byKey.count == resources.count else { throw IntakeError.invalidResponse }

        let jobs = try resources.map { spec -> PhotoUploadJob in
            guard let destination = byKey[spec.assetKey] else { throw IntakeError.invalidResponse }
            return PhotoUploadJob(
                assetKey: spec.assetKey,
                batchID: batchID,
                assetLocalIdentifier: spec.asset.localIdentifier,
                resourceType: spec.resource.type.rawValue,
                resourceFilename: spec.resource.originalFilename,
                destinationURL: destination.url,
                uploadToken: destination.uploadToken,
                mimeType: spec.resource.contentType.preferredMIMEType ?? "application/octet-stream",
                state: .queued,
                retryCount: 0)
        }
        try store.saveUploadBatch(
            batchID: batchID,
            entryLocalID: entryLocalID,
            assetIdentifiers: assets.map(\.localIdentifier),
            jobs: jobs)

        do {
            try PHPhotoLibrary.shared().setUploadJobExtensionEnabled(true)
        } catch {
            // 扩展未启用时绝不能保留 queued job 再回退前台导入；否则未来扩展
            // 恢复会把同一批又上传一次，形成两个 Entry。
            try? store.discardUploadBatch(batchID, restoreCandidates: true)
            throw IntakeError.unavailable
        }
    }

    /// 修复 Photos 与共享 SQLite 在进程终止边界上的短暂不一致：事实层是最终真相。
    /// committed 收口本地；服务端已清理/取消的批次重新回到候选箱；staged 主动续提交。
    func reconcilePendingBatches() async {
        guard let token = try? await tokenProvider(), !token.isEmpty,
              let batchIDs = try? store.activeUploadBatchIDs() else { return }
        for batchID in batchIDs {
            var statusRequest = URLRequest(
                url: baseURL.appendingPathComponent("intake/batches/\(batchID)"))
            statusRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            statusRequest.timeoutInterval = 20
            guard let (data, response) = try? await URLSession.shared.data(for: statusRequest),
                  let http = response as? HTTPURLResponse else { continue }
            if http.statusCode == 404 {
                try? store.discardUploadBatch(batchID, restoreCandidates: true)
                continue
            }
            guard (200..<300).contains(http.statusCode),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let state = object["state"] as? String else { continue }
            if state == "committed" {
                try? store.finishUploadBatchFromServer(batchID)
            } else if state == "failed" || state == "cancelled" {
                try? store.discardUploadBatch(batchID, restoreCandidates: true)
            } else if state == "staged" {
                var commit = URLRequest(url: baseURL.appendingPathComponent("intake/commit"))
                commit.httpMethod = "POST"
                commit.setValue("application/json", forHTTPHeaderField: "Content-Type")
                commit.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                commit.httpBody = try? JSONSerialization.data(withJSONObject: ["batch_id": batchID])
                if let (_, response) = try? await URLSession.shared.data(for: commit),
                   let http = response as? HTTPURLResponse,
                   (200..<300).contains(http.statusCode) {
                    try? store.finishUploadBatchFromServer(batchID)
                }
            }
        }
    }

    private static func resourceSpecs(for asset: PHAsset, batchID: String) -> [ResourceSpec] {
        let all = PHAssetResource.assetResources(for: asset)
        let groupID = stableUUID("asset:" + asset.localIdentifier)
        let selected: [(PHAssetResource, String, String)]
        switch asset.mediaType {
        case .image:
            selected = selectImageResources(all)
        case .video:
            selected = selectVideoResources(all)
        case .audio:
            selected = all.filter { $0.type == .audio }.map { ($0, "audio", "display") }
        default:
            selected = []
        }
        return selected.enumerated().map { index, value in
            let resource = value.0
            let key = stableUUID(
                "resource:\(batchID):\(asset.localIdentifier):\(resource.type.rawValue):\(resource.originalFilename):\(index)"
            )
            return ResourceSpec(
                assetKey: key, assetGroupID: groupID, asset: asset, resource: resource,
                mediaType: value.1, role: value.2)
        }
    }

    private static func selectImageResources(
        _ resources: [PHAssetResource]
    ) -> [(PHAssetResource, String, String)] {
        // 可靠后台路径每个 PHAsset 只提交一个可见原片，避免同一资产的
        // display/original/paired 被各消费面重复统计。Live Photo 由成熟前台路径
        // 同时保存静态图与配对视频，不进入本路径。
        guard let original = resources.first(where: { $0.type == .fullSizePhoto })
            ?? resources.first(where: { $0.type == .photo })
            ?? resources.first(where: { $0.type == .alternatePhoto }) else { return [] }
        return [(original, "photo", "display")]
    }

    private static func selectVideoResources(
        _ resources: [PHAssetResource]
    ) -> [(PHAssetResource, String, String)] {
        guard let original = resources.first(where: { $0.type == .fullSizeVideo })
            ?? resources.first(where: { $0.type == .video }) else { return [] }
        return [(original, "video", "display")]
    }

    nonisolated private static func stableUUID(_ value: String) -> String {
        var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: uuid).uuidString
    }
}
