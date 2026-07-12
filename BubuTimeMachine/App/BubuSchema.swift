import Foundation
import SwiftData

// MARK: - 版本化 Schema 纪律（30 年家庭档案·最高底线：store 永远打得开）
//
// 这是全家 30 年数据的底座。历史上模型变更全是"就地改 V1"、versionIdentifier 还跟着
// App 版本号乱涨（一路涨到 1.3.0），但始终只有一个 V1、stages 为空——旧 schema 定义已丢失，
// 将来任何非轻量变更会直接打不开 store 且无法补迁移 stage。本文件把"当前实际模型形状"
// 显式固化为一个稳定的 V1 快照，并立下三条铁律：
//
//   铁律 1 · schema 版本 ≠ App marketing 版本。App 可以发 1.4 / 2.0，schema 版本只在
//           @Model 字段/结构真正变化时才动。versionIdentifier 不再跟随 App 版本号。
//   铁律 2 · V1 的 versionIdentifier 冻结在 (1, 3, 0)——这正是现有用户 store 里已经戳好的
//           版本号。绝不下调（下调 = 让 SwiftData 以为"store 来自更新的未来版本"，有拒绝打开
//           的风险），也不空涨。它就是 V1 快照的永久编号。
//   铁律 3 · 永不"就地改 V1"。任何 @Model 字段/结构变更 = 新增 BubuSchemaV2 + 迁移 stage
//           （见文件底部模板），让 SwiftData 按计划迁移，而不是"轻量迁移碰运气、失败就打不开
//           全家的数据"。
//
/// V1 快照：当前 on-disk schema 的显式命名。models 必须列全所有 @Model 实体。
enum BubuSchemaV1: VersionedSchema {
    /// 冻结在 (1,3,0)：现有 store 里已戳的版本号。见上方铁律 2——不下调、不空涨。
    /// 与 App marketing 版本解耦：App 升级不改这里，只有新增 V2 时才出现新号。
    static let versionIdentifier = Schema.Version(1, 3, 0)

    /// 全部 @Model 实体（16 个，与工程内 `@Model final class` 一一对应）。
    /// 新增/删除 @Model 时，这里要同步——但那已属于"模型变更"，必须走 V2 流程（铁律 3）。
    static var models: [any PersistentModel.Type] {
        [Entry.self, Media.self, Milestone.self, FirstTime.self,
         TimeCapsule.self, VoiceMemo.self, Comment.self, GrowthMovie.self,
         FamilyMember.self, ChildProfile.self, VoiceNote.self, HealthRecord.self,
         FeedEvent.self, VaccineRecord.self, GrowthMeasurement.self,
         PendingDeletion.self]
    }
}

/// 迁移计划：当前只有 V1 一个版本，故 stages 为空。SharedModelContainer 与 App 均用它建容器。
enum BubuMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BubuSchemaV1.self]
        // 将来：[BubuSchemaV1.self, BubuSchemaV2.self]
    }
    static var stages: [MigrationStage] {
        []
        // 将来：[BubuSchemaV1toV2] 等（见文件底部模板）
    }
}

// MARK: - 【下一次改模型必读】新增 V2 的标准做法（照抄改名即可）
//
// 场景 A · 只是加/删字段、或改可选性等 SwiftData 能自动推断的变更 → 轻量迁移：
//
//   enum BubuSchemaV2: VersionedSchema {
//       static let versionIdentifier = Schema.Version(2, 0, 0)   // 只有真正改模型才涨大版本
//       static var models: [any PersistentModel.Type] { /* V2 的全实体列表 */ }
//   }
//   // BubuMigrationPlan.schemas = [BubuSchemaV1.self, BubuSchemaV2.self]
//   // BubuMigrationPlan.stages  = [
//   //     .lightweight(fromVersion: BubuSchemaV1.self, toVersion: BubuSchemaV2.self)
//   // ]
//
// 场景 B · 需要搬数据/拆合字段等自动推断做不到的 → 自定义迁移（willMigrate 里搬数据）：
//
//   static let BubuSchemaV1toV2 = MigrationStage.custom(
//       fromVersion: BubuSchemaV1.self,
//       toVersion:   BubuSchemaV2.self,
//       willMigrate: { context in /* 读旧字段、写新字段、context.save() */ },
//       didMigrate:  nil
//   )
//   // BubuMigrationPlan.stages = [BubuSchemaV1toV2]
//
// 铁律复述：① 绝不再动 BubuSchemaV1 的任何定义（它是历史快照）；② 新版本另起 V2/V3…；
// ③ 每次都补上 schemas + stages，让升级走计划迁移。改完务必在真机/模拟器上用"装了旧版
// 数据的 store"验证能无损打开。

// MARK: - 数据保护模式标志
/// 容器打开失败时置位：App 以内存容器运行（不崩、不清数据），
/// 磁盘上的 store 原样保留等待修复/导出，设置页给出明确提示。
nonisolated enum BubuStoreHealth {
    private static let key = "bubu.store.loadFailedAt"

    static var loadFailed: Bool {
        UserDefaults.standard.object(forKey: key) != nil
    }
    static func markFailed() {
        UserDefaults.standard.set(Date.now, forKey: key)
    }
    static func markHealthy() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
