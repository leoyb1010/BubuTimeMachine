import Foundation
import SwiftData

// MARK: - 共享 ModelContainer（App Intents / Widget / extension 复用）
/// App Intents 可能在 App 外（后台、extension 进程）执行，拿不到 SwiftUI 注入的容器，
/// 需要一个能独立构建、指向同一 App Group store 的容器入口。
/// 与 BubuTimeMachineApp 用同一份 schema + 同一个 BubuStorage.storeURL，保证读写同一份数据。
enum SharedModelContainer {
    /// 全实体 schema，必须与 BubuTimeMachineApp.init 中的 schema 完全一致。
    static let schema = Schema([
        Entry.self, Media.self, Milestone.self, FirstTime.self,
        TimeCapsule.self, VoiceMemo.self, Comment.self, GrowthMovie.self,
        FamilyMember.self, ChildProfile.self, VoiceNote.self, HealthRecord.self,
        FeedEvent.self, VaccineRecord.self, GrowthMeasurement.self,
        PendingDeletion.self
    ])

    /// 进程内单例容器，指向 App Group 共享 store。
    static let shared: ModelContainer = {
        let config = ModelConfiguration(schema: schema, url: BubuStorage.storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("无法创建共享 SwiftData 容器：\(error)")
        }
    }()
}
