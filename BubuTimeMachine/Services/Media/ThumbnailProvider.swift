import Foundation
import UIKit
import ImageIO

// MARK: - 缩略图提供者（Wave I 流畅度工程核心）
/// 统一的图片解码与缓存层，替代 `MediaThumbnail` 里「每次复用重读磁盘 + 全尺寸解码」的裸奔管线。
///
/// 四件事一次解决：
/// 1. **内存缓存**：`NSCache<NSString, UIImage>`，key = `mediaId + 像素档位`，按字节记账（约 150MB 上限，
///    收到内存警告自动清）——cell 复用命中即返回，零磁盘 IO。
/// 2. **降采样解码**：ImageIO `CGImageSourceCreateThumbnailAtIndex` 直接解到目标像素，
///    解完 `byPreparingForDisplay()` 预解码位图，杜绝首帧绘制卡顿。
/// 3. **缺缩略图落盘补齐**：第一次遇到缺失的缩略图，后台生成并写回约定路径，下次直接命中。
/// 4. **预取**：列表对下一屏 `prefetch(_:)`，滚动到时已在缓存。
///
/// actor 隔离：所有解码在后台执行，不阻塞 MainActor。
actor ThumbnailProvider {

    // MARK: 像素档位
    /// 同图不同尺寸分开缓存：时光轴大卡片用 `.card`，照片墙网格用 `.grid`。
    enum SizeClass: String, Sendable {
        case grid       // 照片墙网格 cell（小）
        case card       // 时光轴卡片大图（中）
        case detail     // 详情/查看器（大）

        var maxPixel: CGFloat {
            switch self {
            case .grid: return 320
            case .card: return 900
            case .detail: return 1800
            }
        }
    }

    private let store: MediaStore

    /// 内存缓存：key = "<mediaId>|<sizeClass>"，cost = 解码后位图字节数估算。
    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 150 * 1_048_576   // ~150MB
        return c
    }()

    /// 同一 key 正在进行的解码任务，避免同图并发重复解码（cell 快速复用时常见）。
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init(store: MediaStore) {
        self.store = store
        // NSCache 在系统内存压力下自动驱逐；落盘缩略图仍在，下次重解很快。
    }

    // MARK: 取图

    /// 取一张缩略图：内存命中 → 落盘缩略图 → 原图降采样（并补齐落盘）。
    func image(mediaId: UUID, thumbnailFileName: String?, localFileName: String?,
               isPhoto: Bool, size: SizeClass) async -> UIImage? {
        let key = cacheKey(mediaId: mediaId, size: size)
        if let cached = cache.object(forKey: key as NSString) { return cached }

        if let running = inFlight[key] { return await running.value }

        let store = self.store
        let maxPixel = size.maxPixel
        // MediaStore 路径方法是纯路径拼接；先解析出 URL 再进后台解码。
        let thumbURL = thumbnailFileName.map { store.thumbnailURL(for: $0) }
        let mediaURL = localFileName.map { store.mediaURL(for: $0) }

        let task = Task<UIImage?, Never>.detached(priority: .userInitiated) {
            // 1) 已有落盘缩略图：降采样解码（缩略图本身已小，这步几乎零成本）。
            if let thumbURL, let img = Self.downsample(url: thumbURL, maxPixel: maxPixel) {
                return img.preparingForDisplay() ?? img
            }
            // 2) 无缩略图：从原图降采样到目标档位。
            guard let mediaURL, let img = Self.downsample(url: mediaURL, maxPixel: maxPixel) else { return nil }
            return img.preparingForDisplay() ?? img
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil

        if let result {
            cache.setObject(result, forKey: key as NSString, cost: estimatedCost(result))
            // 缺缩略图时后台补齐落盘，下次命中（不阻塞本次返回）。
            if thumbnailFileName == nil, let localFileName, isPhoto {
                backfillThumbnail(mediaId: mediaId, mediaName: localFileName)
            }
        }
        return result
    }

    /// 预取：列表对下一屏的 media 调用，滚动到时已在缓存。入参为 Sendable 快照。
    struct Ref: Sendable {
        let mediaId: UUID
        let thumbnailFileName: String?
        let localFileName: String?
        let isPhoto: Bool
    }

    func prefetch(_ refs: [Ref], size: SizeClass) {
        for r in refs {
            let key = cacheKey(mediaId: r.mediaId, size: size)
            guard cache.object(forKey: key as NSString) == nil, inFlight[key] == nil else { continue }
            Task {
                _ = await image(mediaId: r.mediaId, thumbnailFileName: r.thumbnailFileName,
                                localFileName: r.localFileName, isPhoto: r.isPhoto, size: size)
            }
        }
    }

    // MARK: 落盘补齐

    /// 同图去重：grid/card/detail 三档位并发未命中时只补一次，避免生成孤儿缩略图（P3-33）。
    /// 只增不删：成功后模型回填 thumbnailFileName 不会再进来；失败本次会话不重试（下次冷启动再试）。
    private var backfillInFlight: Set<UUID> = []

    /// 后台为缺失缩略图的老数据生成缩略图并写回沙盒。
    /// 注意：仅写文件；`Media.thumbnailFileName` 字段的回填需在 MainActor 侧（SwiftData）完成，
    /// 这里通过通知把文件名带出去，由调用方更新模型。
    private func backfillThumbnail(mediaId: UUID, mediaName: String) {
        guard backfillInFlight.insert(mediaId).inserted else { return }
        let store = self.store
        let mediaURL = store.mediaURL(for: mediaName)
        Task.detached(priority: .background) {
            guard let img = Self.downsample(url: mediaURL, maxPixel: 600) else { return }
            guard let name = store.makePhotoThumbnail(fromImage: img, maxPixel: 600) else { return }
            await ThumbnailBackfillBus.shared.record(mediaId: mediaId, thumbnailFileName: name)
        }
    }

    // MARK: 工具

    private func cacheKey(mediaId: UUID, size: SizeClass) -> String {
        "\(mediaId.uuidString)|\(size.rawValue)"
    }

    private func estimatedCost(_ image: UIImage) -> Int {
        let scale = image.scale
        return Int(image.size.width * scale * image.size.height * scale * 4)
    }

    /// ImageIO 降采样：直接解到 maxPixel，不在内存里展开全尺寸位图。
    nonisolated static func downsample(url: URL, maxPixel: CGFloat) -> UIImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOpts) else { return nil }
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - 缩略图补齐回传总线
/// 后台补齐的缩略图文件名通过它回到 MainActor，由订阅方更新 SwiftData 的 `Media.thumbnailFileName`。
/// 用轻量内存队列而非通知中心，避免引入观察者生命周期问题。
@MainActor
final class ThumbnailBackfillBus {
    static let shared = ThumbnailBackfillBus()
    private(set) var pending: [(mediaId: UUID, thumbnailFileName: String)] = []
    var onRecord: ((UUID, String) -> Void)?

    func record(mediaId: UUID, thumbnailFileName: String) {
        if let onRecord {
            onRecord(mediaId, thumbnailFileName)
        } else {
            pending.append((mediaId, thumbnailFileName))
        }
    }

    /// 订阅方就绪后排空积压。
    func drain(_ handler: (UUID, String) -> Void) {
        for item in pending { handler(item.mediaId, item.thumbnailFileName) }
        pending.removeAll()
    }
}
