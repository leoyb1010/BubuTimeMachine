import AVFoundation
import Foundation
import OSLog
import Photos
import UIKit

// MARK: - 智能照片收件箱
/// 自动发现 PhotoKit 新增素材并按事件分组。候选状态持久存入独立 intake.sqlite，
/// 不污染 SwiftData 事实库；只有用户确认后才复制原片并进入时光轴。
@MainActor
@Observable
final class PhotoLibraryScanner {
    private static let log = Logger(subsystem: "com.bubu.timemachine", category: "PhotoIntake")

    /// 最近发现且尚未确认/忽略的照片与视频。
    private(set) var pendingAssets: [PHAsset] = []
    private(set) var eventGroups: [PhotoEventGroup] = []
    var authorized: Bool = false
    private(set) var hasFullAccess: Bool = false
    private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined
    private(set) var lastError: String?

    private let store: PhotoIntakeStore
    private let changeTokenKey = "photo-library-change-token"
    private let handledKey = "bubu.photoscan.handledIDs"
    private let handledDayKey = "bubu.photoscan.handledDay"
    private var isScanning = false
    private var rescanRequested = false

    private nonisolated struct ScanPayload: Sendable {
        let pendingCandidates: [PhotoIntakeCandidate]
    }

    init(store: PhotoIntakeStore = PhotoIntakeStore()) {
        self.store = store
    }

    /// 当前授权态（不主动弹窗；由 UI 在合适时机 requestAndScan）。
    func refreshAuthorizationState() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = status
        authorized = (status == .authorized || status == .limited)
        hasFullAccess = status == .authorized
        Self.log.info("照片库授权状态：\(status.rawValue, privacy: .public)")
    }

    /// 请求权限并扫描。返回尚待处理的素材数。
    @discardableResult
    func requestAndScan() async -> Int {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        authorized = (status == .authorized || status == .limited)
        hasFullAccess = status == .authorized
        guard authorized else {
            pendingAssets = []
            eventGroups = []
            return 0
        }
        return await scan()
    }

    /// 首次回看最近 7 天；此后用 PhotoKit persistent change token 增量补入，
    /// 同时重载 intake.sqlite 中仍 pending 的旧候选，因此跨天/重启不会丢提示。
    @discardableResult
    func scan() async -> Int {
        guard authorized else { return 0 }
        if isScanning {
            // 首页出现、回前台、服务器核对可能在同一秒触发；合并成当前轮后的至多一次补扫。
            rescanRequested = true
            return pendingAssets.count
        }
        isScanning = true
        defer { isScanning = false }

        repeat {
            rescanRequested = false
            lastError = nil
            migrateLegacyHandledIDsIfNeeded()
            let scanStore = store
            let tokenKey = changeTokenKey
            do {
                // PhotoKit 枚举、持久变化解析、SQLite upsert/grouping 都不再占用 MainActor。
                let payload = try await Task.detached(priority: .utility) {
                    try Self.buildScanPayload(store: scanStore, changeTokenKey: tokenKey)
                }.value
                let identifiers = payload.pendingCandidates.map(\.localIdentifier)
                let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
                var byIdentifier: [String: PHAsset] = [:]
                result.enumerateObjects { asset, _, _ in
                    byIdentifier[asset.localIdentifier] = asset
                }
                pendingAssets = identifiers.compactMap { byIdentifier[$0] }
                eventGroups = PhotoEventClusterer.cluster(payload.pendingCandidates)
            } catch {
                // 状态库不可用时禁止展示：否则无法判断已收录/已忽略，可能重复发布。
                // PhotoKit 原片仍在，下次扫描可完整重建候选，不存在事实数据丢失。
                pendingAssets = []
                eventGroups = []
                lastError = error.localizedDescription
            }
        } while rescanRequested

        Self.log.info("照片收件箱扫描完成：待处理 \(self.pendingAssets.count, privacy: .public) 个，分为 \(self.eventGroups.count, privacy: .public) 组")
        return pendingAssets.count
    }

    private nonisolated static func buildScanPayload(
        store: PhotoIntakeStore,
        changeTokenKey: String
    ) throws -> ScanPayload {
        let library = PHPhotoLibrary.shared()
        var identifiers = Set(try store.pendingIdentifiers())
        var needsRecentBootstrap = false

        if let data = try store.data(forMetadataKey: changeTokenKey),
           let token = try? NSKeyedUnarchiver.unarchivedObject(
               ofClass: PHPersistentChangeToken.self, from: data) {
            do {
                let changes = try library.fetchPersistentChanges(since: token)
                var deleted: [String] = []
                for change in changes {
                    let details = try change.changeDetails(for: .asset)
                    identifiers.formUnion(details.insertedLocalIdentifiers)
                    identifiers.formUnion(details.updatedLocalIdentifiers)
                    deleted.append(contentsOf: details.deletedLocalIdentifiers)
                }
                try store.mark(deleted, state: .deleted)
                identifiers.subtract(deleted)
            } catch {
                // token 过期/不可用时仅补扫近期窗口；正式状态仍由 intake.sqlite 去重。
                try? store.setData(nil, forMetadataKey: changeTokenKey)
                needsRecentBootstrap = true
            }
        } else {
            needsRecentBootstrap = true
        }

        var fetched: [PHAsset] = []
        if needsRecentBootstrap {
            let options = PHFetchOptions()
            let calendar = Calendar.current
            let start = calendar.date(
                byAdding: .day, value: -7, to: calendar.startOfDay(for: .now)) ?? .distantPast
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND (mediaType == %d OR mediaType == %d)",
                start as NSDate, PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(with: options)
            result.enumerateObjects { asset, _, _ in fetched.append(asset) }
            identifiers.formUnion(fetched.map(\.localIdentifier))
        }

        let alreadyFetched = Set(fetched.map(\.localIdentifier))
        let missing = identifiers.subtracting(alreadyFetched)
        if !missing.isEmpty {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(missing), options: nil)
            result.enumerateObjects { asset, _, _ in fetched.append(asset) }
        }

        let candidates = fetched.compactMap(Self.candidate)
        try store.upsertDiscovered(candidates)
        let candidateIDs = candidates.map(\.localIdentifier)
        let states = try store.states(for: candidateIDs)
        let pending = candidates.filter {
            let state = states[$0.localIdentifier] ?? .discovered
            return state == .discovered || state == .failed
        }.sorted { $0.creationDate > $1.creationDate }
        let tokenData = try NSKeyedArchiver.archivedData(
            withRootObject: library.currentChangeToken, requiringSecureCoding: true)
        try store.setData(tokenData, forMetadataKey: changeTokenKey)
        return ScanPayload(pendingCandidates: pending)
    }

    func assets(in group: PhotoEventGroup) -> [PHAsset] {
        let wanted = Set(group.assetIdentifiers)
        return pendingAssets.filter { wanted.contains($0.localIdentifier) }
    }

    func markAccepted(_ assets: [PHAsset]) {
        mark(assets, state: .accepted)
    }

    func markQueued(_ assets: [PHAsset]) {
        mark(assets, state: .queued)
    }

    func markIgnored(_ assets: [PHAsset]) {
        mark(assets, state: .ignored)
    }

    /// 旧调用兼容：历史上“已处理”无法区分收录或忽略，只保证不重复提示。
    func markHandled(_ assets: [PHAsset]) { markIgnored(assets) }

    func markAllHandled() { markIgnored(pendingAssets) }

    private func mark(_ assets: [PHAsset], state: PhotoIntakeState) {
        let ids = Set(assets.map(\.localIdentifier))
        do {
            try store.mark(Array(ids), state: state)
            pendingAssets.removeAll { ids.contains($0.localIdentifier) }
            rebuildGroups()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func rebuildGroups() {
        eventGroups = PhotoEventClusterer.cluster(pendingAssets.compactMap(Self.candidate))
    }

    private nonisolated static func candidate(_ asset: PHAsset) -> PhotoIntakeCandidate? {
        guard let creationDate = asset.creationDate else { return nil }
        let kind: PhotoIntakeMediaKind
        switch asset.mediaType {
        case .image: kind = .photo
        case .video: kind = .video
        default: return nil
        }
        return PhotoIntakeCandidate(
            localIdentifier: asset.localIdentifier,
            creationDate: creationDate,
            mediaKind: kind,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude,
            width: asset.pixelWidth,
            height: asset.pixelHeight,
            duration: asset.duration,
            burstIdentifier: asset.burstIdentifier,
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive)
        )
    }

    private func migrateLegacyHandledIDsIfNeeded() {
        let defaults = UserDefaults.standard
        let identifiers = defaults.stringArray(forKey: handledKey) ?? []
        guard !identifiers.isEmpty else { return }
        do {
            try store.mark(identifiers, state: .ignored)
            defaults.removeObject(forKey: handledKey)
            defaults.removeObject(forKey: handledDayKey)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 取资产的【原始字节】（保真导入用）：EXIF/GPS/拍摄时间原样保留，30 年档案不存压缩图。
    /// iCloud 未下载时允许联网取；失败返回 nil（调用方按失败处理，不静默）。
    nonisolated static func loadOriginalData(_ asset: PHAsset) async -> Data? {
        await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .original
            var resumed = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: data)
            }
        }
    }

    /// 视频原文件导出到临时目录（保真导入用）。失败返回 nil。
    nonisolated static func loadVideoFile(_ asset: PHAsset) async -> URL? {
        guard asset.mediaType == .video else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let res = resources.first(where: { $0.type == .video }) ?? resources.first else { return nil }
        let ext = (res.originalFilename as NSString).pathExtension.lowercased()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(ext.isEmpty ? "mov" : ext)")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        do {
            try await PHAssetResourceManager.default().writeData(for: res, toFile: tmp, options: options)
            return tmp
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return nil
        }
    }

    /// Live Photo 的动态原片资源。静态图与 paired video 必须一起成功才算保真收录。
    nonisolated static func loadLivePhotoPairedVideo(_ asset: PHAsset) async -> URL? {
        guard asset.mediaType == .image, asset.mediaSubtypes.contains(.photoLive) else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: {
            $0.type == .pairedVideo || $0.type == .fullSizePairedVideo
        }) else { return nil }
        let originalExtension = (resource.originalFilename as NSString).pathExtension.lowercased()
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(originalExtension.isEmpty ? "mov" : originalExtension)")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        do {
            try await PHAssetResourceManager.default().writeData(
                for: resource, toFile: temporaryURL, options: options)
            return temporaryURL
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            return nil
        }
    }

    /// 视频精选只抽有限关键帧，不逐帧推理。临时视频无论成功失败都会清理。
    nonisolated static func loadVideoKeyframes(
        _ asset: PHAsset,
        maximumCount: Int = 4,
        targetPixel: CGFloat = 900
    ) async -> [Data] {
        guard maximumCount > 0, let temporaryURL = await loadVideoFile(asset) else { return [] }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let videoAsset = AVURLAsset(url: temporaryURL)
        guard let duration = try? await videoAsset.load(.duration) else { return [] }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return [] }
        let count = min(maximumCount, max(1, Int(ceil(seconds / 8))))
        let generator = AVAssetImageGenerator(asset: videoAsset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: targetPixel, height: targetPixel)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.35, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.35, preferredTimescale: 600)

        var frames: [Data] = []
        for index in 0..<count {
            // 避开绝对首尾的黑帧；短视频至少取中点。
            let fraction = Double(index + 1) / Double(count + 1)
            let time = CMTime(seconds: seconds * fraction, preferredTimescale: 600)
            guard let generated = try? await generator.image(at: time),
                  let data = UIImage(cgImage: generated.image).jpegData(compressionQuality: 0.82) else {
                continue
            }
            frames.append(data)
        }
        return frames
    }

    /// 把资产加载成 UIImage（导入用）。失败返回 nil。
    nonisolated static func loadImage(_ asset: PHAsset, targetPixel: CGFloat = 2400) async -> UIImage? {
        await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .exact
            let target = CGSize(width: targetPixel, height: targetPixel)
            PHImageManager.default().requestImage(for: asset, targetSize: target,
                                                  contentMode: .aspectFit, options: options) { image, info in
                // 可能回调两次（低清占位 + 高清）；只在拿到非降级图时 resume。
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded { cont.resume(returning: image) }
            }
        }
    }
}
