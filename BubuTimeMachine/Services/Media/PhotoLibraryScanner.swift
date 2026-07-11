import Foundation
import Photos
import UIKit

// MARK: - 相册今日扫描（零操作记录：把今天拍的照片主动请你收进时光机）
/// 90% 的素材本就在系统相册。App 扫描「今天新增」的照片，首页主动弹卡请你一键挑选收录，
/// 不用再手动开相册选一遍。全程端侧，不上传。已收录/已忽略的不再重复提示。
@MainActor
@Observable
final class PhotoLibraryScanner {
    /// 今天新增、尚未处理过的照片资产。
    private(set) var todayAssets: [PHAsset] = []
    var authorized: Bool = false

    private let handledKey = "bubu.photoscan.handledIDs"
    private var handledIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: handledKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: handledKey) }
    }

    /// 当前授权态（不主动弹窗；由 UI 在合适时机 requestAndScan）。
    func refreshAuthorizationState() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorized = (status == .authorized || status == .limited)
    }

    /// 请求权限并扫描今天的照片。返回未处理的今日照片数。
    @discardableResult
    func requestAndScan() async -> Int {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorized = (status == .authorized || status == .limited)
        guard authorized else { todayAssets = []; return 0 }
        return scan()
    }

    /// 已授权时直接扫描（首页出现时调用）。
    @discardableResult
    func scan() -> Int {
        guard authorized else { return 0 }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: .now)

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND mediaType == %d",
                                        startOfDay as NSDate, PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        let handled = handledIDs
        result.enumerateObjects { asset, _, _ in
            if !handled.contains(asset.localIdentifier) { assets.append(asset) }
        }
        todayAssets = assets
        return assets.count
    }

    /// 标记为已处理（收录或忽略后调用），下次不再提示。
    func markHandled(_ assets: [PHAsset]) {
        var set = handledIDs
        assets.forEach { set.insert($0.localIdentifier) }
        handledIDs = set
        todayAssets.removeAll { assets.contains($0) }
    }

    func markAllHandled() { markHandled(todayAssets) }

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
