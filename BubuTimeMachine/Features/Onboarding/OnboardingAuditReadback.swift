#if DEBUG
import SwiftUI
import SwiftData

/// Synthetic first-launch diagnostics only; the actual onboarding and root route
/// remain in charge. Reading a fresh context does not save pending UI changes.
struct OnboardingAuditReadback: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query private var profiles: [ChildProfile]
    @Query private var members: [FamilyMember]

    private var readback: String {
        let fresh = ModelContext(context.container)
        fresh.autosaveEnabled = false
        do {
            let savedProfiles = try fresh.fetch(FetchDescriptor<ChildProfile>())
            let savedMembers = try fresh.fetch(FetchDescriptor<FamilyMember>())
            return "done=\(env.hasCompletedOnboarding)|identity=\(env.currentMemberId == nil ? "none" : "set")|profiles=\(profiles.count)|members=\(members.count)|storedProfiles=\(savedProfiles.count)|storedMembers=\(savedMembers.count)|role=\(env.config.currentRoleRaw)"
        } catch { return "readback-error" }
    }

    var body: some View {
        Text(readback)
            .font(.system(size: 8))
            .foregroundStyle(.primary)
            .padding(2)
            .background(.regularMaterial)
            .accessibilityIdentifier("onboarding.audit.readback")
            .allowsHitTesting(false)
    }
}

@MainActor
enum OnboardingUITestFault {
    private static var injected = false
    static func injectOnce(in container: ModelContainer) throws {
        let args = ProcessInfo.processInfo.arguments
        guard !injected, args.contains("-uitest-in-memory"),
              args.contains("-uitest-fresh-onboarding"), args.contains("-uitest-onboarding-fail-save"),
              !container.configurations.isEmpty,
              container.configurations.allSatisfy({ $0.isStoredInMemoryOnly }) else { return }
        injected = true
        throw CocoaError(.fileWriteOutOfSpace)
    }
}
#endif
