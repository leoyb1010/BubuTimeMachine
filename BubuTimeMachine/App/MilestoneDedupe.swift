import Foundation
import SwiftData

// MARK: - 历史重复里程碑的一次性清理
/// 以前这段逻辑挂在 `AppEnvironment.bootstrap` 里，**每次启动**都做一遍无上限的物理删除。
/// 两个问题：
/// 1. 物理删除不该是每次启动的常规动作——里程碑没有软删字段，删错不可逆。
/// 2. 旧的胜负打分里混了一项「距创建天数（封顶 19）」，两条近乎相同的记录在第 19 天之后
///    同时封顶，胜负改由无排序 fetch 的行序决定，同一份数据在不同时间可能保下不同的那条。
///
/// 现在：这里只跑一次（`DataMigration` 框架保证），清掉历史遗留的本地重复；
/// 日常重复（两台设备各记了同名里程碑）由 `SyncEngine.normalizeMilestonesByTitle`
/// 在每轮合并后处理——那条路径覆盖更全，还会顺手 trim 标题。
/// 保留优先级统一走 `Milestone.prefersKeeping`，全序且与时间无关。
@MainActor
enum MilestoneDedupe {

    static func perform(context: ModelContext) throws {
        let milestones = try context.fetch(FetchDescriptor<Milestone>())
        guard milestones.count > 1 else { return }

        var bestByTitle: [String: Milestone] = [:]
        var duplicates: [Milestone] = []

        for milestone in milestones {
            let key = milestone.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }   // 空标题不参与去重，也不删（宁可留着让用户自己处理）
            if let best = bestByTitle[key] {
                if Milestone.prefersKeeping(milestone, over: best) {
                    duplicates.append(best)
                    bestByTitle[key] = milestone
                } else {
                    duplicates.append(milestone)
                }
            } else {
                bestByTitle[key] = milestone
            }
        }

        // 未达成、无备注的出厂预设占位不需要往服务器推——标成 synced 免得占用推送队列。
        let presetTitles = Set(MilestoneTemplate.presets.map(\.title))
        for milestone in bestByTitle.values
        where presetTitles.contains(milestone.title)
            && !milestone.isCustom
            && !milestone.isAchieved
            && (milestone.detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            milestone.syncState = .synced
        }

        for duplicate in duplicates {
            context.delete(duplicate)
        }
        try context.save()
    }
}
