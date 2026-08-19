import Foundation
import OSLog
import SwiftData

// MARK: - 缩略图错位自愈
/// 修 v2.10.1 及更早版本留下的脏数据：同步的「预览秒出」通道把服务端小图落进了
/// **Media/** 目录，文件名却写进了 `Media.thumbnailFileName`。
/// 而缩略图的两个读取方——主 App `MediaStore.thumbnailURL(for:)` 与桌面小组件
/// `BubuWidgetData.imageData` ——都只查 **Thumbnails/**，于是：
/// 桌面照片整体消失、时光轴在原图下齐前一直是占位底色。
///
/// 增量已由 `MediaStore.importThumbnail` 修正；存量数据分布在全家三台设备上，
/// 必须自愈——所以这里做一次性扫描：凡是 `thumbnailFileName` 在缩略图目录里找不到、
/// 却能在媒体目录里找到的，把文件搬回缩略图目录（文件名不变，模型字段无需改动）。
///
/// 安全性：
/// - 只搬「被 thumbnailFileName 引用」的文件，绝不动 `localFileName` 指向的原片。
/// - 若同一条记录的 thumbnail 与 local 恰好同名（历史上不会出现，防御性处理），
///   改为拷贝，保证原片不被搬走。
/// - 搬不动（IO 失败/文件不在）就跳过，不抛错、不阻塞启动。
@MainActor
enum ThumbnailPathRepair {
    private static let log = Logger(subsystem: "com.bubu.timemachine", category: "ThumbnailRepair")

    static func perform(context: ModelContext) throws {
        let store = MediaStore()
        // 只取真的有缩略图字段的行：没有 thumbnailFileName 的记录（视频原片、还没生成缩略图的
        // 新照片）压根不可能错位，没必要 faulting 出来。大库启动时这一刀省的是实打实的时间。
        let descriptor = FetchDescriptor<Media>(predicate: #Predicate { $0.thumbnailFileName != nil })
        let candidates = try context.fetch(descriptor)
        var repaired = 0
        for media in candidates {
            guard let thumbName = media.thumbnailFileName, !thumbName.isEmpty else { continue }
            // 防御：历史上不会出现 thumbnail 与原片同名，真出现时改为拷贝，绝不把原片搬走。
            let keepSource = (media.localFileName == thumbName)
            if store.relocateStrayThumbnail(named: thumbName, keepSource: keepSource) {
                repaired += 1
            }
        }
        log.notice("缩略图错位自愈完成：扫描 \(candidates.count, privacy: .public) 条，搬回 \(repaired, privacy: .public) 个文件")
    }
}
