import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

/// Synthetic temporary stores only. Keep SQLite files until process/OS cleanup rather
/// than unlinking them while ModelContainer still has live file handles.
@MainActor
struct CommentVaccinePersistenceTests {
    private enum Failure: Error { case diskFull }

    private struct Fixture {
        let root: URL
        let container: ModelContainer
        var context: ModelContext { container.mainContext }
        var fresh: ModelContext { ModelContext(container) }
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("comment-vaccine-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: root.appendingPathComponent("synthetic.store"))
        ])
        container.mainContext.autosaveEnabled = false
        return Fixture(root: root, container: container)
    }

    private func parent(in f: Fixture) throws -> Entry {
        let parent = Entry(authorRole: "synthetic", note: "persisted parent")
        parent.syncState = .synced
        f.context.insert(parent)
        try f.context.save()
        return parent
    }

    @Test("评论失败不提交成功回调、不丢录音和其他草稿；同一草稿重试只有一条评论和动态")
    func commentFailureAndRetry() throws {
        let f = try fixture()
        let entry = try parent(in: f)
        entry.note = "unrelated pending correction"
        let unrelated = Entry(authorRole: "synthetic", note: "other unsaved draft")
        f.context.insert(unrelated)
        let voice = f.root.appendingPathComponent("original.m4a")
        try Data("synthetic original audio".utf8).write(to: voice)
        let draft = CommentPersistence.Draft(id: UUID(), parentID: entry.id, role: "synthetic",
                                              text: "new comment", voice: (voice.lastPathComponent, 2, []))
        var succeeded = 0
        var attempted: ModelContext?
        #expect(throws: Failure.self) {
            try CommentPersistence.save(draft, in: f.context, persist: { context in
                attempted = context
                #expect(context !== f.context && !context.autosaveEnabled)
                throw Failure.diskFull
            }, didCommit: { _ in succeeded += 1 })
        }
        #expect(attempted?.hasChanges == false && succeeded == 0)
        #expect(try f.fresh.fetchCount(FetchDescriptor<BubuTimeMachine.Comment>()) == 0)
        #expect(try f.fresh.fetchCount(FetchDescriptor<FeedEvent>()) == 0)
        #expect(try f.fresh.fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(entry.note == "unrelated pending correction" && f.context.hasChanges)
        #expect(try Data(contentsOf: voice) == Data("synthetic original audio".utf8))
        try CommentPersistence.save(draft, in: f.context)
        try CommentPersistence.save(draft, in: f.context)
        let comments = try f.fresh.fetch(FetchDescriptor<BubuTimeMachine.Comment>())
        #expect(comments.count == 1 && comments.first?.id == draft.id)
        #expect(comments.first?.entry?.id == entry.id)
        #expect(try f.fresh.fetchCount(FetchDescriptor<FeedEvent>()) == 1)
        #expect(try f.fresh.fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(try f.fresh.fetch(FetchDescriptor<Entry>()).first?.note == "persisted parent")
        #expect(entry.note == "unrelated pending correction")
    }

    @Test("未落盘、已删除或已归档父记录不能保存孤儿评论", arguments: ["unsaved", "deleted", "archived"])
    func commentRejectsUnavailableParent(_ state: String) throws {
        let f = try fixture()
        let entry = Entry(authorRole: "synthetic", note: "parent")
        f.context.insert(entry)
        if state != "unsaved" { try f.context.save() }
        if state == "deleted" { f.context.delete(entry) }
        if state == "archived" { entry.isArchived = true }
        var succeeded = false
        #expect(throws: CommentPersistence.SaveError.self) {
            try CommentPersistence.save(.init(id: UUID(), parentID: entry.id, role: "synthetic", text: "comment"),
                                        in: f.context, didCommit: { _ in succeeded = true })
        }
        #expect(!succeeded)
        #expect(try f.fresh.fetchCount(FetchDescriptor<BubuTimeMachine.Comment>()) == 0)
    }

    @Test("疫苗新增失败不刷新提醒、不退出；重试稳定ID并保留其他未提交草稿")
    func vaccineCreationFailureAndRetry() throws {
        let f = try fixture()
        let unrelated = Entry(authorRole: "synthetic", note: "other draft")
        f.context.insert(unrelated)
        let draft = VaccineQuickLogPersistence.Draft(id: UUID(), vaccineName: "synthetic vaccine",
            doseID: "synthetic-1", doseLabel: "first", injectedAt: Date(timeIntervalSince1970: 1_700_000_000), hospital: "test clinic")
        var succeeded = 0
        var attempted: ModelContext?
        #expect(throws: Failure.self) {
            try VaccineQuickLogPersistence.save(draft, in: f.context, persist: { context in
                attempted = context
                #expect(context !== f.context && !context.autosaveEnabled)
                throw Failure.diskFull
            }, didCommit: { _ in succeeded += 1 })
        }
        #expect(attempted?.hasChanges == false && succeeded == 0)
        #expect(try f.fresh.fetchCount(FetchDescriptor<VaccineRecord>()) == 0)
        #expect(try f.fresh.fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(unrelated.note == "other draft" && f.context.hasChanges)
        try VaccineQuickLogPersistence.save(draft, in: f.context)
        try VaccineQuickLogPersistence.save(draft, in: f.context)
        let records = try f.fresh.fetch(FetchDescriptor<VaccineRecord>())
        #expect(records.count == 1 && records.first?.id == draft.id)
        #expect(records.first?.doseId == "synthetic-1" && records.first?.hospital == "test clinic")
        #expect(try f.fresh.fetchCount(FetchDescriptor<Entry>()) == 0)
    }

    @Test("疫苗修改失败不改原记录；成功后才替换迁移占位信息")
    func vaccineEditFailureAndRetry() throws {
        let f = try fixture()
        let record = VaccineRecord(vaccineName: "synthetic", injectedAt: .distantPast, source: "migration")
        record.note = "日期待确认"; record.syncState = .synced
        f.context.insert(record)
        try f.context.save()
        let draft = VaccineQuickLogPersistence.Draft(id: record.id, editing: .init(record), vaccineName: record.vaccineName,
            injectedAt: Date(timeIntervalSince1970: 1_700_000_000), hospital: "new clinic", note: "confirmed date")
        var succeeded = false
        #expect(throws: Failure.self) {
            try VaccineQuickLogPersistence.save(draft, in: f.context, persist: { _ in throw Failure.diskFull },
                                                didCommit: { _ in succeeded = true })
        }
        #expect(!succeeded && record.note == "日期待确认" && record.hospital == nil)
        #expect(try f.fresh.fetch(FetchDescriptor<VaccineRecord>()).first?.note == "日期待确认")
        try VaccineQuickLogPersistence.save(draft, in: f.context)
        let saved = try #require(f.fresh.fetch(FetchDescriptor<VaccineRecord>()).first)
        #expect(saved.injectedAt == draft.injectedAt && saved.note == "confirmed date" && saved.hospital == "new clinic")
        #expect(saved.syncState == .local)
    }

    @Test("疫苗删除与墓碑原子提交；旧health-fallback删除真实远端与本机镜像", arguments: ["manual", "health-fallback"])
    func vaccineDeletionFailureAndRetry(_ source: String) throws {
        let f = try fixture()
        let record = VaccineRecord(vaccineName: "synthetic", injectedAt: .distantPast, source: source)
        record.remoteId = source == "manual" ? "vaccine-remote" : nil
        record.syncState = .synced
        f.context.insert(record)
        if source == "health-fallback" {
            let health = HealthRecord(kind: .checkup, title: "疫苗：synthetic")
            health.id = record.id; health.remoteId = "health-remote"; health.syncState = .synced
            health.tags = ["疫苗", "synthetic"]
            f.context.insert(health)
        }
        try f.context.save()
        let target = VaccineQuickLogPersistence.Target(record)
        let unrelated = Entry(authorRole: "synthetic", note: "other draft")
        f.context.insert(unrelated)
        var succeeded = 0
        var attempted: ModelContext?
        #expect(throws: Failure.self) {
            try VaccineQuickLogPersistence.delete(target, in: f.context, persist: { context in
                attempted = context
                #expect(context !== f.context && !context.autosaveEnabled)
                throw Failure.diskFull
            }, didCommit: { _ in succeeded += 1 })
        }
        #expect(attempted?.hasChanges == false && succeeded == 0)
        #expect(try f.fresh.fetchCount(FetchDescriptor<VaccineRecord>()) == 1)
        #expect(try f.fresh.fetchCount(FetchDescriptor<PendingDeletion>()) == 0)
        #expect(try f.fresh.fetchCount(FetchDescriptor<Entry>()) == 0)
        try VaccineQuickLogPersistence.delete(target, in: f.context, didCommit: { _ in succeeded += 1 })
        #expect(succeeded == 1)
        #expect(try f.fresh.fetchCount(FetchDescriptor<VaccineRecord>()) == 0)
        #expect(try f.fresh.fetchCount(FetchDescriptor<HealthRecord>()) == 0)
        let pending = try f.fresh.fetch(FetchDescriptor<PendingDeletion>())
        #expect(pending.count == 1)
        #expect(pending.first?.collection == (source == "manual" ? "vaccinerecords" : "healthrecords"))
        #expect(pending.first?.remoteId == (source == "manual" ? "vaccine-remote" : "health-remote"))
        #expect(unrelated.note == "other draft" && f.context.hasChanges)
        try f.context.save()
        #expect(try f.fresh.fetchCount(FetchDescriptor<VaccineRecord>()) == 0)
        #expect(try f.fresh.fetchCount(FetchDescriptor<HealthRecord>()) == 0)
    }

    @Test("疫苗删除拒绝已变化的远端身份，不排错墓碑")
    func vaccineDeletionRejectsStaleTarget() throws {
        let f = try fixture()
        let record = VaccineRecord(vaccineName: "synthetic", injectedAt: .distantPast)
        record.remoteId = "old-remote"
        f.context.insert(record)
        try f.context.save()
        let target = VaccineQuickLogPersistence.Target(record)
        record.remoteId = "new-remote"
        try f.context.save()
        #expect(throws: VaccineQuickLogPersistence.SaveError.self) {
            try VaccineQuickLogPersistence.delete(target, in: f.context)
        }
        #expect(try f.fresh.fetchCount(FetchDescriptor<VaccineRecord>()) == 1)
        #expect(try f.fresh.fetchCount(FetchDescriptor<PendingDeletion>()) == 0)
    }
}
