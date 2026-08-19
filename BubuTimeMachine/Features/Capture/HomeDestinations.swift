import SwiftUI
import SwiftData

// 注：原「照片墙 PhotoWallView」已退役——首页照片入口改为相册（AlbumHomeView）后它再无任何入口，
// 「全部照片」系统相册完整覆盖其功能（AlbumDetailView 同为三列网格直开查看器）。

/// 全屏查看器路由（相册体系共用）。
struct MediaViewerRoute: Identifiable {
    let initialMediaID: UUID
    var id: UUID { initialMediaID }
}

