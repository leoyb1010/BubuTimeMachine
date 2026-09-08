import Foundation
import SwiftData

// 版本号属于持久化格式，不随 App 营销版本变化。
// V1 的实体定义冻结在 BubuSchemaV1Snapshot.swift；不再引用当前活动模型。
enum BubuSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 3, 0)
    static var models: [any PersistentModel.Type] {
        [Entry.self, Media.self, Milestone.self, FirstTime.self, TimeCapsule.self, VoiceMemo.self, Comment.self, GrowthMovie.self, FamilyMember.self, ChildProfile.self, VoiceNote.self, HealthRecord.self, FeedEvent.self, VaccineRecord.self, GrowthMeasurement.self, PendingDeletion.self]
    }
}

// V2 保留全部业务字段，新增可与业务数据一起提交的同步进度。
// 今后的破坏性变更必须另立历史快照和迁移阶段，并验证已装机数据库。
enum BubuSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Entry.self, Media.self, Milestone.self, FirstTime.self, TimeCapsule.self, VoiceMemo.self, Comment.self, GrowthMovie.self, FamilyMember.self, ChildProfile.self, VoiceNote.self, HealthRecord.self, FeedEvent.self, VaccineRecord.self, GrowthMeasurement.self, PendingDeletion.self, SyncCheckpoint.self]
    }
}

enum BubuMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [BubuSchemaV1.self, BubuSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: BubuSchemaV1.self, toVersion: BubuSchemaV2.self)]
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
