import Foundation
import SwiftData

// MARK: - 生日归一化迁移（birthday-normalize-v1）
/// 存量数据修复：早期版本 DatePicker(.date) 的初值带当前时分秒，
/// 生日被原样写库（例如 2024-03-05 14:37:12），导致全 App 年龄口径出现"当天忽早忽晚"的偏差
/// （两周岁生日早上显示"1岁11个月"却又触发"生日快乐🎂"；出生当天早于出生时刻显示"即将出生"）。
/// 本迁移把所有已存在的 `ChildProfile.birthday` 归一化到当天 0 点。
/// 幂等：已是 0 点的记录不改动；重复执行结果一致。
enum BirthdayNormalizationMigrator {

    /// 迁移框架入口：save 失败抛出 → DataMigrationRunner 不落完成标记、下次启动重试。
    @MainActor
    static func perform(context: ModelContext) throws {
        let profiles = (try? context.fetch(FetchDescriptor<ChildProfile>())) ?? []
        let cal = Calendar.current
        var changed = false
        for profile in profiles {
            let normalized = cal.startOfDay(for: profile.birthday)
            // 只在确有偏差时写入：保证幂等，且不无谓地把整档标脏。
            if profile.birthday != normalized {
                profile.birthday = normalized
                changed = true
            }
        }
        if changed { try context.save() }
    }
}
