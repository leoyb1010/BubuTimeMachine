import Foundation
import SwiftData

// MARK: - 小组件数据快照
/// Widget 在自己的进程里跑，需要从 App Group 共享 store 读出当前布布状态，
/// 打包成一个轻量、Sendable 的快照供各 family 渲染。读失败时返回占位快照（绝不崩、绝不空白）。
struct BubuSnapshot: Sendable {
    var name: String
    var birthday: Date?
    var ageText: String
    var daysSinceBirth: Int
    var daysUntilBirthday: Int
    var hasProfile: Bool
    /// 最近一张照片的本地文件名（成长墙/那年今日用），可空。
    var recentPhotoFileName: String?

    /// 无档案时的占位。
    static let placeholder = BubuSnapshot(
        name: "布布", birthday: nil, ageText: "等你记录",
        daysSinceBirth: 0, daysUntilBirthday: 0, hasProfile: false,
        recentPhotoFileName: nil
    )

    /// 预览/骨架用的样例。
    static let sample = BubuSnapshot(
        name: "布布", birthday: Calendar.current.date(byAdding: .month, value: -23, to: .now),
        ageText: "1岁11个月", daysSinceBirth: 709, daysUntilBirthday: 23,
        hasProfile: true, recentPhotoFileName: nil
    )
}

// MARK: - 快照读取
enum BubuWidgetData {
    /// 从共享 store 读当前布布快照。全部 try? 兜底，任何异常都退化为占位快照。
    @MainActor
    static func loadSnapshot() -> BubuSnapshot {
        let context = SharedModelContainer.shared.mainContext
        guard let profile = try? context.fetch(FetchDescriptor<ChildProfile>()).first else {
            return .placeholder
        }
        let now = Date.now
        // 最近一条带照片的记录（取其首张照片做封面）。
        var recentPhoto: String?
        var descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.happenedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 12
        if let entries = try? context.fetch(descriptor) {
            outer: for entry in entries {
                for media in entry.media where media.type == .photo {
                    if let fn = media.localFileName {
                        recentPhoto = fn
                        break outer
                    }
                }
            }
        }
        return BubuSnapshot(
            name: profile.name,
            birthday: profile.birthday,
            ageText: AgeCalculator.ageDescription(birthday: profile.birthday, at: now),
            daysSinceBirth: AgeCalculator.daysSinceBirth(birthday: profile.birthday, at: now),
            daysUntilBirthday: AgeCalculator.daysUntilNextBirthday(birthday: profile.birthday, from: now),
            hasProfile: true,
            recentPhotoFileName: recentPhoto
        )
    }

    /// 读共享容器里的照片数据（缩略图优先，没有再读原图）。
    static func photoData(fileName: String?) -> Data? {
        guard let fileName else { return nil }
        let thumb = BubuStorage.thumbnailDirectory.appendingPathComponent(fileName)
        if let d = try? Data(contentsOf: thumb) { return d }
        let full = BubuStorage.mediaDirectory.appendingPathComponent(fileName)
        return try? Data(contentsOf: full)
    }
}
