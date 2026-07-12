import Foundation
import WidgetKit

// MARK: - 小组件刷新（合并节流）
/// 主 App 改了会显示在小组件上的数据（布布档案/头像/记录）后，通知 WidgetKit 重载时间线，
/// 否则桌面小组件只会按系统的低频节奏更新，看起来「没反应」。
///
/// 为什么要节流：`reload()` 有 20+ 处调用点，其中不少是高频/成串触发——
/// 每次 scenePhase active、每条手表记录（App 后台也会触发）、每一轮同步。
/// WidgetKit 的重载有「每个 widget kind 当日预算」，后台把预算烧光后，
/// 桌面小组件当天就再也不更新了。这里把短时间内的多次 reload 合并成一次真正的重载，
/// 既保留「数据变了要刷」的正确性，又不至于把预算打爆。
///
/// 语义：首次调用立即刷新（前台单次编辑无延迟）；紧接着窗口期内的多次调用合并，
/// 窗口结束时再补刷一次以反映最新态（成串的后台/同步刷新塌缩为个位数次）。
enum WidgetRefresher {
    /// 合并窗口：窗口内的多次 reload 只落地一次真正的重载。
    private static let minInterval: TimeInterval = 2

    @MainActor private static var lastReload = Date.distantPast
    @MainActor private static var trailingScheduled = false

    /// 冗余去除：原来先 `reloadTimelines(ofKind:"BubuWidget")` 再 `reloadAllTimelines()`，
    /// 前者是后者的子集，纯冗余；现在只保留一次全量重载并做合并节流。
    static func reload() {
        Task { @MainActor in coalescedReload() }
    }

    @MainActor
    private static func coalescedReload() {
        // 已经有一次窗口末尾的补刷在排队：本次并入它，不再另排。
        guard !trailingScheduled else { return }

        let elapsed = Date.now.timeIntervalSince(lastReload)
        if elapsed >= minInterval {
            // 距上次真正重载已足够久：立即刷新（前台单次编辑无感延迟）。
            performReload()
        } else {
            // 仍在窗口内：安排窗口末尾补刷一次，把这段时间的多次触发塌缩为一次。
            trailingScheduled = true
            let delay = minInterval - elapsed
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                trailingScheduled = false
                performReload()
            }
        }
    }

    @MainActor
    private static func performReload() {
        lastReload = .now
        WidgetCenter.shared.reloadAllTimelines()
    }
}
