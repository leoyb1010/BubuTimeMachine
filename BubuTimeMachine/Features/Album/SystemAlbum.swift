import Foundation
import SwiftData

// MARK: - 系统相册（纯计算，不建表）
/// V1 直接从 Entry + Media 动态生成；上传新照片后自动出现在对应相册。

/// 相册里的一项（媒体 + 所属记录），照片墙/相册详情共用。
struct AlbumMediaItem: Identifiable {
    let media: Media
    let entry: Entry
    var id: UUID { media.id }
}

struct SystemAlbum: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let items: [AlbumMediaItem]

    var cover: AlbumMediaItem? { items.first }
    var count: Int { items.count }
}

enum SystemAlbumFactory {

    /// 全部照片 / 最近上传 / 小视频 / 有地点（空相册不展示，「全部照片」始终保留）。
    static func featured(from items: [AlbumMediaItem]) -> [SystemAlbum] {
        let photos = items.filter { $0.media.type == .photo }
        let videos = items.filter { $0.media.type == .video }
        let recent = Array(items.prefix(60))
        let withLocation = items.filter {
            $0.entry.locationName?.isEmpty == false || $0.entry.latitude != nil
        }

        var albums: [SystemAlbum] = [
            SystemAlbum(id: "all-photos", title: "全部照片",
                        subtitle: "每一张长大的证据", icon: "photo.stack", items: photos)
        ]
        if !recent.isEmpty {
            albums.append(SystemAlbum(id: "recent", title: "最近上传",
                                      subtitle: "最新的 \(recent.count) 个瞬间", icon: "clock", items: recent))
        }
        if !videos.isEmpty {
            albums.append(SystemAlbum(id: "videos", title: "小视频",
                                      subtitle: "会动的回忆", icon: "video", items: videos))
        }
        if !withLocation.isEmpty {
            albums.append(SystemAlbum(id: "with-location", title: "有地点",
                                      subtitle: "去过的地方", icon: "mappin.and.ellipse", items: withLocation))
        }
        return albums
    }

    /// 按月份（2026年6月…），新月份在前。
    static func monthly(from items: [AlbumMediaItem]) -> [SystemAlbum] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: items) { item -> String in
            let c = cal.dateComponents([.year, .month], from: item.entry.happenedAt)
            return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        }
        return groups.keys.sorted(by: >).compactMap { key in
            guard let group = groups[key], !group.isEmpty else { return nil }
            let parts = key.split(separator: "-")
            let year = Int(parts.first ?? "0") ?? 0
            let month = Int(parts.last ?? "0") ?? 0
            return SystemAlbum(id: "month-\(key)",
                               title: "\(year)年\(month)月",
                               subtitle: "\(group.count) 个瞬间",
                               icon: "calendar",
                               items: group)
        }
    }

    /// 按月龄（12 个月、13 个月…），大月龄在前；没有生日时返回空。
    static func byAgeMonth(from items: [AlbumMediaItem], birthday: Date?) -> [SystemAlbum] {
        guard let birthday else { return [] }
        let cal = Calendar.current
        let groups = Dictionary(grouping: items) { item -> Int in
            max(0, cal.dateComponents([.month], from: birthday, to: item.entry.happenedAt).month ?? 0)
        }
        return groups.keys.sorted(by: >).compactMap { month in
            guard let group = groups[month], !group.isEmpty else { return nil }
            let title = month < 12 ? "\(month) 个月" : "\(month / 12) 岁\(month % 12 == 0 ? "" : " \(month % 12) 个月")"
            return SystemAlbum(id: "age-\(month)",
                               title: title,
                               subtitle: "\(group.count) 个瞬间",
                               icon: "birthday.cake",
                               items: group)
        }
    }
}
