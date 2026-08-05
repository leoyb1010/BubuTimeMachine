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
        return scan()
    }

    /// 首次回看最近 7 天；此后用 PhotoKit persistent change token 增量补入，
    /// 同时重载 intake.sqlite 中仍 pending 的旧候选，因此跨天/重启不会丢提示。
    @discardableResult
    func scan() -> Int {
        guard authorized else { return 0 }
        lastError = nil
        migrateLegacyHandledIDsIfNeeded()

        let library = PHPhotoLibrary.shared()
        var identifiers = Set((try? store.pendingIdentifiers()) ?? [])
        var needsRecentBootstrap = false

        if let token = loadChangeToken() {
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
                // change token 过期/不可用时只重扫近期窗口，正式状态仍由 intake.sqlite 去重。
                try? store.setData(nil, forMetadataKey: changeTokenKey)
                needsRecentBootstrap = true
            }
        } else {
            needsRecentBootstrap = true
        }

        var fetched: [PHAsset] = []
        if needsRecentBootstrap {
            let options = PHFetchOptions()
            let start = Calendar.current.date(byAdding: .day, value: -7,
                                              to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND (mediaType == %d OR mediaType == %d)",
                start as NSDate, PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(with: options)
            result.enumerateObjects { asset, _, _ in fetched.append(asset) }
            identifiers.formUnion(fetched.map(\.localIdentifier))
        }

        if !identifiers.isEmpty {
            let alreadyFetched = Set(fetched.map(\.localIdentifier))
            let missing = identifiers.subtracting(alreadyFetched)
            if !missing.isEmpty {
                let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(missing), options: nil)
                result.enumerateObjects { asset, _, _ in fetched.append(asset) }
            }
        }

        let candidates = fetched.compactMap(Self.candidate)
        do {
            try store.upsertDiscovered(candidates)
            let candidateIDs = Set(candidates.map(\.localIdentifier))
            let states = try store.states(for: Array(candidateIDs))
            pendingAssets = fetched.filter { asset in
                guard candidateIDs.contains(asset.localIdentifier) else { return false }
                let state = states[asset.localIdentifier] ?? .discovered
                return state == .discovered || state == .failed
            }.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            try saveChangeToken(library.currentChangeToken)
        } catch {
            // 状态库不可用时禁止展示：否则无法判断已收录/已忽略，可能重复发布。
            // PhotoKit 原片仍在，下次扫描可完整重建候选，不存在事实数据丢失。
            pendingAssets = []
            lastError = error.localizedDescription
        }

        rebuildGroups()
        Self.log.info("照片收件箱扫描完成：待处理 \(self.pendingAssets.count, privacy: .public) 个，分为 \(self.eventGroups.count, privacy: .public) 组")
        return pendingAssets.count
    }

    func assets(in group: PhotoEventGroup) -> [PHAsset] {
        let wanted = Set(group.assetIdentifiers)
        return pendingAssets.filter { wanted.contains($0.localIdentifier) }
    }

    func markAccepted(_ assets: [PHAsset]) {
        mark(assets, state: .accepted)
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

    private static func candidate(_ asset: PHAsset) -> PhotoIntakeCandidate? {
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

    private func loadChangeToken() -> PHPersistentChangeToken? {
        guard let data = try? store.data(forMetadataKey: changeTokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: PHPersistentChangeToken.self, from: data)
    }

    private func saveChangeToken(_ token: PHPersistentChangeToken) throws {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: token, requiringSecureCoding: true)
        try store.setData(data, forMetadataKey: changeTokenKey)
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
