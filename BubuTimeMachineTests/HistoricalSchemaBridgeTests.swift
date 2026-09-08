import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

// 刻意缺少 2.13 增加的四个字段，不能用已经升级过的库冒充历史形状。
enum PreSchoolSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 3, 0)
    static var models: [any PersistentModel.Type] {
        BubuSchemaV1.models.filter { String(describing: $0) != "ChildProfile" } + [ChildProfile.self]
    }
    @Model
    final class ChildProfile {
        @Attribute(.unique) var id: UUID
        var remoteId: String?
        var name: String                  // "布布"
        var birthday: Date
        var gender: String?               // 可选
        var avatarMediaFileName: String?  // 布布头像（沙盒文件名）
        var avatarRemoteURL: String?      // 头像远端 URL（PocketBase childprofile.avatar；跨设备同步用）
        var heroBackgroundFileName: String? // 首页背景（布布的照片）
        var bloodType: String?
        var birthPlace: String?
        /// 小名/乳名（可选）。身份卡背面与问候语可展示，additive 字段走自动轻量迁移。
        /// 过敏源（可选，自由文本）。入园必填项之一，也是老师最需要知道的一条。
        /// 与 schoolStartDate 一样是纯 additive 可选字段。
        /// 需要老师知道的用药或健康备注（可选，自由文本）。
        /// 上幼儿园的第一天（可选）。填了之后全 App 多一条与「来到世界第 N 天」并列的
        /// 「上学第 N 天」，开学前则是倒计时。
        ///
        /// 为什么是 optional：BubuSchemaV1 目前引用的是活模型类而非冻结快照，破坏性变更
        /// 没有可用的迁移路径（见 App/BubuSchema.swift 与 2026-09-04 审计 §1.1）。
        /// 纯 additive 的可选字段走自动轻量迁移是安全的——Media 追加 remoteThumbURL /
        /// contentHash 时已经验证过。在 schema 真修复之前，新能力只能用这种形状。
        var syncStateRaw: String = SyncState.local.rawValue
        var createdAt: Date

        var syncState: SyncState {
            get { SyncState(rawValue: syncStateRaw) ?? .local }
            set { syncStateRaw = newValue.rawValue }
        }

        init(name: String = "布布", birthday: Date) {
            self.id = UUID()
            self.name = name
            // 生日归一化到当天 0 点：DatePicker(.date) 的初值会带当前时分秒，
            // 若原样入库会让全 App 年龄口径出现"当天忽早忽晚"的偏差（C-P1-5）。
            self.birthday = Calendar.current.startOfDay(for: birthday)
            self.createdAt = .now
        }
    }
}

@MainActor
struct HistoricalSchemaBridgeTests {
    @Test("缺少入园字段的历史 V1 可保留关系和正文升级到 V2")
    func preSchoolSchemaSurvivesUpgrade() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("legacy.store")
        let identifier = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema: PreSchoolSchema.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = container.mainContext
            context.insert(PreSchoolSchema.ChildProfile(name: "测试档案", birthday: Date(timeIntervalSince1970: 1_700_000_000)))
            let entry = BubuSchemaV1.Entry(authorRole: "audit", note: "旧版本的原文")
            entry.id = identifier
            let media = BubuSchemaV1.Media(type: .photo, localFileName: "original.jpg")
            media.entry = entry
            context.insert(entry)
            context.insert(media)
            try context.save()
        }
        let container = try BubuStoreLoader.open(at: url)
        let context = container.mainContext
        let entry = try #require(context.fetch(FetchDescriptor<Entry>()).first)
        #expect(entry.id == identifier)
        #expect(entry.note == "旧版本的原文")
        #expect(entry.media.first?.localFileName == "original.jpg")
        #expect(try context.fetch(FetchDescriptor<ChildProfile>()).first?.name == "测试档案")
        #expect(try context.fetchCount(FetchDescriptor<SyncCheckpoint>()) == 0)
        try StoreUpgradeBackup.validate(StoreUpgradeBackup.destination(for: url))
    }

    @Test("历史模型与活动模型的类型已经分离")
    func frozenTypesAreDistinct() {
        #expect(ObjectIdentifier(BubuSchemaV1.Entry.self) != ObjectIdentifier(Entry.self))
        #expect(BubuSchemaV2.models.count == 17)
        #expect(BubuMigrationPlan.stages.count == 1)
    }
}
