import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

@MainActor
struct OnboardingMutationTests {
    private enum Fault: Error { case rejected }

    private func draft(profileID: UUID = UUID(), memberID: UUID = UUID()) -> OnboardingMutation.Draft {
        .init(profileID: profileID, memberID: memberID, childName: "Synthetic Child",
              birthday: Date(timeIntervalSince1970: 1_700_000_000), memberName: "Synthetic Parent",
              relation: "爸爸", emoji: "🙂", colorHex: "#5B8DEF")
    }

    @Test("首次建档失败不泄露未提交档案；稳定重试与磁盘重开只保留一份")
    func rejectionRetryAndReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = SharedModelContainer.schema, url = directory.appendingPathComponent("onboarding.store")
        let input = draft()
        do {
            let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            store.mainContext.autosaveEnabled = false
            #expect(throws: Fault.self) {
                try OnboardingMutation.complete(draft: input, container: store) { _ in throw Fault.rejected }
            }
            let afterFailure = ModelContext(store)
            #expect(try afterFailure.fetchCount(FetchDescriptor<ChildProfile>()) == 0)
            #expect(try afterFailure.fetchCount(FetchDescriptor<FamilyMember>()) == 0)
            #expect(!store.mainContext.hasChanges)
            let first = try OnboardingMutation.complete(draft: input, container: store)
            let second = try OnboardingMutation.complete(draft: input, container: store)
            #expect(first.profileID == input.profileID && second.profileID == first.profileID)
            #expect(first.memberID == input.memberID && second.memberID == first.memberID)
        }
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let profiles = try reopened.mainContext.fetch(FetchDescriptor<ChildProfile>())
        let members = try reopened.mainContext.fetch(FetchDescriptor<FamilyMember>())
        #expect(profiles.count == 1 && members.count == 1)
        #expect(profiles.first?.id == input.profileID && profiles.first?.name == input.childName)
        #expect(members.first?.id == input.memberID && members.first?.name == input.memberName)
        #expect(members.first?.isPrimary == true)
    }

    @Test("同步已有的档案与同关系成员被复用，别处未保存草稿不随建档提交")
    func existingFamilyAndUnrelatedDraftStayUntouched() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = SharedModelContainer.schema, url = directory.appendingPathComponent("existing.store")
        let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let main = store.mainContext; main.autosaveEnabled = false
        let child = ChildProfile(name: "Existing synthetic child", birthday: Date(timeIntervalSince1970: 1_600_000_000))
        let member = FamilyMember(name: "Existing synthetic parent", relation: "爸爸")
        member.remoteId = "synthetic-remote-member"
        member.contactPhone = "synthetic-local-contact"
        let entry = Entry(authorRole: "爸爸", note: "Committed note")
        main.insert(child); main.insert(member); main.insert(entry); try main.save()
        entry.note = "Unsaved unrelated note"
        let committed = try OnboardingMutation.complete(draft: draft(), container: store)
        #expect(committed.profileID == child.id && committed.childName == child.name)
        #expect(committed.memberID == member.id)
        #expect(entry.note == "Unsaved unrelated note" && main.hasChanges)
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let profiles = try reopened.mainContext.fetch(FetchDescriptor<ChildProfile>())
        let members = try reopened.mainContext.fetch(FetchDescriptor<FamilyMember>())
        let entries = try reopened.mainContext.fetch(FetchDescriptor<Entry>())
        #expect(profiles.count == 1 && profiles.first?.name == "Existing synthetic child")
        #expect(members.count == 1 && members.first?.name == "Existing synthetic parent")
        #expect(members.first?.remoteId == "synthetic-remote-member")
        #expect(members.first?.contactPhone == "synthetic-local-contact")
        #expect(entries.first?.note == "Committed note")
    }
}
