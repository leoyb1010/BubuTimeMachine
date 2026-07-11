import Foundation
import SwiftData

// MARK: - 版本化 Schema（R4 G-3）
/// 30 年档案的底座：schema 从此有版本号。将来加字段/改结构时新增 V2 + MigrationStage，
/// SwiftData 按计划迁移，而不是"轻量迁移碰运气、失败就打不开全家的数据"。
enum BubuSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 3, 0)

    static var models: [any PersistentModel.Type] {
        [Entry.self, Media.self, Milestone.self, FirstTime.self,
         TimeCapsule.self, VoiceMemo.self, Comment.self, GrowthMovie.self,
         FamilyMember.self, ChildProfile.self, VoiceNote.self, HealthRecord.self,
         FeedEvent.self, VaccineRecord.self, GrowthMeasurement.self,
         PendingDeletion.self]
    }
}

enum BubuMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BubuSchemaV1.self]
        // 将来：[BubuSchemaV1.self, BubuSchemaV2.self]
    }
    static var stages: [MigrationStage] {
        []
        // 将来：[.lightweight(fromVersion: BubuSchemaV1.self, toVersion: BubuSchemaV2.self)] 等
    }
}

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
