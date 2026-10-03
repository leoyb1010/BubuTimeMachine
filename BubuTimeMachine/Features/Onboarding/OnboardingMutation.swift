import Foundation
import SwiftData

@MainActor
enum OnboardingMutation {
    struct Draft {
        let profileID: UUID
        let memberID: UUID
        let childName: String
        let birthday: Date
        let memberName: String
        let relation: String
        let emoji: String
        let colorHex: String
    }
    struct Committed {
        let profileID: UUID
        let childName: String
        let memberID: UUID
        let relation: String
    }

    /// The first-launch completion flag is a receipt for a committed family,
    /// never for objects that only exist in the UI context's pending changes.
    static func complete(draft: Draft, container: ModelContainer,
                         persist: (ModelContext) throws -> Void = { try $0.save() }) throws -> Committed {
        let transaction = ModelContext(container)
        transaction.autosaveEnabled = false
        let profiles = try transaction.fetch(FetchDescriptor<ChildProfile>(sortBy: [SortDescriptor(\.createdAt)]))
        let members = try transaction.fetch(FetchDescriptor<FamilyMember>(sortBy: [SortDescriptor(\.createdAt)]))
        let profile: ChildProfile
        if let existing = profiles.first {
            profile = existing
        } else {
            let name = draft.childName.trimmingCharacters(in: .whitespacesAndNewlines)
            profile = ChildProfile(name: name.isEmpty ? "布布" : name, birthday: draft.birthday)
            profile.id = draft.profileID
            transaction.insert(profile)
        }
        let member: FamilyMember
        if let existing = members.first(where: { $0.id == draft.memberID || $0.relation == draft.relation }) {
            member = existing
        } else {
            let name = draft.memberName.trimmingCharacters(in: .whitespacesAndNewlines)
            member = FamilyMember(name: name.isEmpty ? draft.relation : name,
                                  relation: draft.relation, avatarEmoji: draft.emoji, themeColorHex: draft.colorHex)
            member.id = draft.memberID
            member.isPrimary = true
            transaction.insert(member)
        }
        let result = Committed(profileID: profile.id, childName: profile.name,
                               memberID: member.id, relation: member.relation)
        do { try persist(transaction) } catch { transaction.rollback(); throw error }
        // No fallible verification after commit that could misreport success.
        return result
    }
}
