import Foundation
import SwiftData

// MARK: - 无 UI 记录写入层
/// App Intents（Siri / 小组件按钮 / Controls / Action Button）需要在没有 UI、甚至在 extension
/// 进程里直接把一条记录落库。`CaptureModel` 绑定 @MainActor + UI 状态，不能在那些场景复用，
/// 故把「写一条文字瞬间」的核心逻辑提炼成这个纯函数式、无 UI 依赖的写入层。
///
/// 与 CaptureModel 的关系：
/// - App 内完整记录流程（选图/分析/语音）仍走 CaptureModel；
/// - 快速文字记录（Intent）走 EntryWriter，二者落库结构一致（Entry + FeedEvent）。
///
/// 并发：所有写操作都在传入的 `ModelContext` 上同步完成；调用方负责在正确的 actor/context 上调用，
/// 不与 SyncEngine 并发写同一 context。
enum EntryWriter {

    /// 写一条纯文字瞬间。返回新建 Entry 的 id；失败抛错（Intent 层据此给用户反馈）。
    @discardableResult
    static func quickTextEntry(
        note: String,
        mood: Mood? = nil,
        role: FamilyRole,
        in context: ModelContext
    ) throws -> UUID {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw EntryWriterError.emptyNote
        }

        let entry = Entry(happenedAt: .now, authorRole: role.rawValue, note: trimmed)
        entry.mood = mood
        context.insert(entry)

        // 与 CaptureModel.savePickedItems 同构：记录后写一条家庭动态。
        let event = FeedEvent(kind: .entryCreated,
                              actorRole: role.rawValue,
                              summary: "记录了：\(trimmed)",
                              targetLocalId: entry.id.uuidString,
                              happenedAt: entry.happenedAt)
        context.insert(event)

        try context.save()
        return entry.id
    }

    /// 读取当前布布档案（Intent 念年龄 / 小组件取生日用）。无档案返回 nil。
    static func currentChildProfile(in context: ModelContext) -> ChildProfile? {
        try? context.fetch(FetchDescriptor<ChildProfile>()).first
    }
}

enum EntryWriterError: LocalizedError {
    case emptyNote

    var errorDescription: String? {
        switch self {
        case .emptyNote: return "记录内容是空的"
        }
    }
}
