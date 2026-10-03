import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

@MainActor
struct EntryMediaAppendCommitTests {
    private enum Failure: Error { case diskFull }
    private func context() throws -> (ModelContext, Entry) {
        let container = try ModelContainer(for: SharedModelContainer.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let parent = Entry(authorRole: "audit", note: "existing")
        context.insert(parent)
        try context.save()
        return (context, parent)
    }

    @Test("追加失败清理新副本，不留下挂起素材，不提交或回滚其他编辑")
    func failedAppendIsIsolated() throws {
        let (context, parent) = try context()
        parent.note = "未保存的编辑"
        let media = Media(type: .photo, localFileName: "new.jpg")
        media.thumbnailFileName = "new-thumb.jpg"
        var removed: [String] = []
        #expect(throws: Failure.self) {
            try EntryMediaAppendCommit.save([media], to: parent.id, in: context, persist: {
                #expect($0 !== context && !$0.autosaveEnabled)
                throw Failure.diskFull
            }, removeFiles: { file, thumb in removed += [file, thumb].compactMap { $0 } })
        }
        #expect(removed == ["new.jpg", "new-thumb.jpg"])
        #expect(try context.fetchCount(FetchDescriptor<Media>()) == 0)
        #expect(parent.note == "未保存的编辑" && context.hasChanges)
        try context.save()
        #expect(try ModelContext(context.container).fetchCount(FetchDescriptor<Media>()) == 0)
    }

    @Test("追加成功只提交新素材，主页面尚未完成的文字仍是草稿")
    func successfulAppendPreservesOtherDrafts() throws {
        let (context, parent) = try context()
        parent.note = "正在编辑的文字"
        let media = Media(type: .photo, localFileName: "new.jpg")
        try EntryMediaAppendCommit.save([media], to: parent.id, in: context,
                                        removeFiles: { _, _ in Issue.record("成功素材不能清理") })
        let fresh = ModelContext(context.container)
        #expect(try fresh.fetchCount(FetchDescriptor<Media>()) == 1)
        #expect(try fresh.fetch(FetchDescriptor<Entry>()).first?.note == "existing")
        #expect(parent.note == "正在编辑的文字")
    }

    @Test("归档或删除的父记录不接受新素材", arguments: [true, false])
    func unavailableParentRejectsMedia(archive: Bool) throws {
        let (context, parent) = try context()
        let id = parent.id
        if archive { parent.isArchived = true } else { context.delete(parent) }
        try context.save()
        var removed = false
        #expect(throws: EntryMediaAppendCommit.CommitError.self) {
            try EntryMediaAppendCommit.save([Media(type: .photo, localFileName: "new.jpg")], to: id,
                in: context, removeFiles: { _, _ in removed = true })
        }
        #expect(removed)
        #expect(try ModelContext(context.container).fetchCount(FetchDescriptor<Media>()) == 0)
    }
}
