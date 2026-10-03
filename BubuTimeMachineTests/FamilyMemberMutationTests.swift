import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

@MainActor
struct FamilyMemberMutationTests {
    private enum Fault: Error { case diskFull }
    private func container() throws -> ModelContainer {
        try ModelContainer(for: FamilyMember.self, PendingDeletion.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    private let draft = FamilyMemberMutation.Draft(name: "  测试姥姥  ", relation: "姥姥", emoji: "👵", colorHex: "#5B8DEF")

    @Test("新增失败保留主 context 草稿，重试只提交一次")
    func addFailureThenRetry() throws {
        let store = try container()
        let main = store.mainContext
        main.autosaveEnabled = false
        let unrelated = FamilyMember(name: "尚未保存", relation: "其他")
        main.insert(unrelated)
        #expect(throws: Fault.self) {
            try FamilyMemberMutation.save(id: nil, draft: draft, container: store) { _ in throw Fault.diskFull }
        }
        #expect(try ModelContext(store).fetchCount(FetchDescriptor<FamilyMember>()) == 0)
        #expect(unrelated.name == "尚未保存")
        #expect(main.hasChanges)
        let id = try FamilyMemberMutation.save(id: nil, draft: draft, container: store)
        let saved = try ModelContext(store).fetch(FetchDescriptor<FamilyMember>())
        #expect(saved.count == 1)
        #expect(saved.first?.id == id)
        #expect(saved.first?.name == "测试姥姥")
        #expect(main.hasChanges)
    }

    @Test("编辑失败原身份保留，重试保持 ID 与本机私有字段")
    func editFailureThenRetry() throws {
        let store = try container()
        let main = store.mainContext
        let member = FamilyMember(name: "旧名字", relation: "爸爸")
        member.contactPhone = "synthetic-contact"
        member.canPickUpFromSchool = true
        main.insert(member); try main.save()
        #expect(throws: Fault.self) {
            try FamilyMemberMutation.save(id: member.id, draft: draft, container: store) { _ in throw Fault.diskFull }
        }
        #expect(try ModelContext(store).fetch(FetchDescriptor<FamilyMember>()).first?.name == "旧名字")
        try FamilyMemberMutation.save(id: member.id, draft: draft, container: store)
        let saved = try #require(ModelContext(store).fetch(FetchDescriptor<FamilyMember>()).first)
        #expect(saved.id == member.id && saved.name == "测试姥姥")
        #expect(saved.contactPhone == "synthetic-contact" && saved.canPickUpFromSchool)
    }

    @Test("删除失败不留墓碑，重试原子删除并给出有效后备身份")
    func deletionFailureThenRetry() throws {
        let store = try container(); let main = store.mainContext
        let first = FamilyMember(name: "爸爸", relation: "爸爸")
        first.remoteId = "synthetic-remote-member"
        let second = FamilyMember(name: "妈妈", relation: "妈妈")
        main.insert(first); main.insert(second); try main.save()
        #expect(throws: Fault.self) {
            try FamilyMemberMutation.delete(id: first.id, container: store) { _ in throw Fault.diskFull }
        }
        #expect(try ModelContext(store).fetchCount(FetchDescriptor<FamilyMember>()) == 2)
        #expect(try ModelContext(store).fetchCount(FetchDescriptor<PendingDeletion>()) == 0)
        let fallback = try FamilyMemberMutation.delete(id: first.id, container: store)
        #expect(fallback.id == second.id && fallback.relation == "妈妈")
        #expect(try ModelContext(store).fetchCount(FetchDescriptor<FamilyMember>()) == 1)
        #expect(try ModelContext(store).fetchCount(FetchDescriptor<PendingDeletion>()) == 1)
        #expect(throws: FamilyMemberMutation.MutationError.self) {
            try FamilyMemberMutation.delete(id: second.id, container: store)
        }
    }
    @Test("磁盘事务重开读回、稳定新增 ID 重复提交无重复成员")
    func diskReopenAndStableIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("members.store")
        let stableID = UUID()
        do {
            let store = try ModelContainer(for: FamilyMember.self, PendingDeletion.self,
                                           configurations: ModelConfiguration(url: url))
            try FamilyMemberMutation.save(id: nil, newID: stableID, draft: draft, container: store)
            try FamilyMemberMutation.save(id: nil, newID: stableID, draft: draft, container: store)
        }
        let reopened = try ModelContainer(for: FamilyMember.self, PendingDeletion.self,
                                          configurations: ModelConfiguration(url: url))
        let members = try reopened.mainContext.fetch(FetchDescriptor<FamilyMember>())
        #expect(members.count == 1 && members.first?.id == stableID)
        #expect(members.first?.name == "测试姥姥")
    }

    @Test("磁盘删除失败无墓碑；成功后主 context 再保存也不复活")
    func diskDeleteRollbackAndMainContextMirror() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("delete.store")
        let deletedID: UUID
        do {
            let store = try ModelContainer(for: FamilyMember.self, PendingDeletion.self,
                                           configurations: ModelConfiguration(url: url))
            let main = store.mainContext
            main.autosaveEnabled = false
            let first = FamilyMember(name: "原成员", relation: "爸爸")
            first.remoteId = "synthetic-remote"
            let other = FamilyMember(name: "原另一成员", relation: "妈妈")
            main.insert(first); main.insert(other); try main.save()
            deletedID = first.id
            other.name = "另一页面未提交草稿"
            #expect(throws: Fault.self) {
                try FamilyMemberMutation.delete(id: first.id, container: store) { _ in throw Fault.diskFull }
            }
            #expect(try ModelContext(store).fetchCount(FetchDescriptor<FamilyMember>()) == 2)
            #expect(try ModelContext(store).fetchCount(FetchDescriptor<PendingDeletion>()) == 0)
            #expect(other.name == "另一页面未提交草稿" && main.hasChanges)
            try FamilyMemberMutation.delete(id: first.id, container: store)
            let independent = try ModelContext(store).fetch(FetchDescriptor<FamilyMember>())
            #expect(independent.count == 1 && independent.first?.name == "原另一成员")
            // Match the successful UI mirror, then model a later independent main save.
            main.delete(first)
            try main.save()
        }
        let reopened = try ModelContainer(for: FamilyMember.self, PendingDeletion.self,
                                          configurations: ModelConfiguration(url: url))
        let saved = try reopened.mainContext.fetch(FetchDescriptor<FamilyMember>())
        #expect(saved.count == 1 && !saved.contains(where: { $0.id == deletedID }))
        #expect(saved.first?.name == "另一页面未提交草稿")
        let tombstones = try reopened.mainContext.fetch(FetchDescriptor<PendingDeletion>())
        #expect(tombstones.count == 1 && tombstones.first?.remoteId == "synthetic-remote")
    }

}
