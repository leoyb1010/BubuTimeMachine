import SwiftUI
import SwiftData

// MARK: - App 入口
/// @main：装配 ModelContainer（全部 @Model）+ 注入全局 AppEnvironment（DI）。
@main
struct BubuTimeMachineApp: App {
    /// SwiftData 容器：唯一真相源。包含第 2 章全部实体。
    let modelContainer: ModelContainer

    /// 全局依赖容器。@State 持有，保证生命周期与 App 一致。
    @State private var env = AppEnvironment()

    init() {
        let schema = Schema([
            Entry.self, Media.self, Milestone.self, FirstTime.self,
            TimeCapsule.self, VoiceMemo.self, Comment.self, GrowthMovie.self,
            FamilyMember.self, ChildProfile.self, VoiceNote.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("无法创建 SwiftData 容器：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .tint(env.theme.theme.primary)
                .task {
                    #if DEBUG
                    seedForUITestingIfNeeded()
                    #endif
                    env.bootstrap()
                }
        }
        .modelContainer(modelContainer)
    }

    #if DEBUG
    /// 仅供截图/联调：以 `-uitest-seed` 启动时，注入一个布布档案 + 成员 + 几条记录，跳过引导。
    @MainActor
    private func seedForUITestingIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-uitest-seed") else { return }
        let context = modelContainer.mainContext
        let existing = (try? context.fetch(FetchDescriptor<ChildProfile>())) ?? []
        guard existing.isEmpty else { env.hasCompletedOnboarding = true; return }

        let birthday = Calendar.current.date(byAdding: .month, value: -19, to: .now) ?? .now
        let profile = ChildProfile(name: "布布", birthday: birthday)
        context.insert(profile)

        let mama = FamilyMember(name: "妈妈", relation: "妈妈", avatarEmoji: "👩", themeColorHex: "#F28C9E")
        mama.isPrimary = true
        context.insert(mama)
        let grandma = FamilyMember(name: "姥姥", relation: "姥姥", avatarEmoji: "👵", themeColorHex: "#F2B705")
        context.insert(grandma)

        let moods: [Mood] = [.happy, .curious, .proud, .sleepy]
        let notes = ["布布今天第一次自己扶着沙发站起来了！", "在公园看小鸟看了好久，眼睛亮亮的。",
                     "午睡醒来冲我笑，奶香奶香的。", "把积木叠到了三层，特别得意。"]
        for i in 0..<4 {
            let day = Calendar.current.date(byAdding: .day, value: -i * 9, to: .now) ?? .now
            let e = Entry(happenedAt: day, authorRole: i % 2 == 0 ? "妈妈" : "姥姥", note: notes[i])
            e.mood = moods[i]
            e.locationName = i == 1 ? "家附近的公园" : "家"
            context.insert(e)
        }

        for tpl in MilestoneTemplate.presets.prefix(6) {
            let m = Milestone(title: tpl.title, category: tpl.category, emoji: tpl.emoji)
            context.insert(m)
        }
        // 点亮一个
        if let walk = (try? context.fetch(FetchDescriptor<Milestone>()))?.first {
            walk.happenedAt = Calendar.current.date(byAdding: .day, value: -3, to: .now)
            walk.ageDescription = AgeCalculator.ageDescription(birthday: birthday, at: walk.happenedAt!)
        }

        try? context.save()
        env.currentMemberId = mama.id
        env.hasCompletedOnboarding = true
    }
    #endif
}

// MARK: - 根视图：首启引导 or 主界面
struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if env.hasCompletedOnboarding {
            RootTabView()
                .transition(.opacity)
        } else {
            OnboardingView()
                .transition(.opacity)
        }
    }
}
