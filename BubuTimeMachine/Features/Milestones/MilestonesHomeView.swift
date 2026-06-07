import SwiftUI
import SwiftData

// MARK: - 里程碑 & 成就墙
/// 已达成（高亮）+ 待达成（待解锁）网格。可从预设库添加，也可完全自定义。
struct MilestonesHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query(sort: \Milestone.createdAt, order: .reverse) private var milestones: [Milestone]
    @Query private var profiles: [ChildProfile]

    @State private var showPicker = false
    @State private var showCustom = false
    @State private var ceremonyFor: Milestone?
    @State private var detailFor: Milestone?

    private var theme: Color { env.theme.theme.primary }
    private var profile: ChildProfile? { profiles.first }

    private var achieved: [Milestone] { milestones.filter(\.isAchieved) }
    private var pending: [Milestone] { milestones.filter { !$0.isAchieved } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                progressHeader
                if !achieved.isEmpty { achievedWall }
                if !pending.isEmpty { pendingWall }
                if milestones.isEmpty { emptyState }
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("里程碑")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showPicker = true } label: { Label("从清单选择", systemImage: "list.bullet") }
                    Button { showCustom = true } label: { Label("自定义里程碑", systemImage: "star.bubble") }
                } label: { Image(systemName: "plus.circle.fill") }
            }
        }
        .sheet(isPresented: $showPicker) { MilestonePickerSheet() }
        .sheet(isPresented: $showCustom) { MilestoneEditSheet(milestone: nil) }
        .sheet(item: $detailFor) { MilestoneEditSheet(milestone: $0) }
        .fullScreenCover(item: $ceremonyFor) { milestone in
            CeremonyAnimation(title: "🎉 \(milestone.title)",
                              subtitle: profile.map { AgeCalculator.ageDescription(birthday: $0.birthday, at: milestone.happenedAt ?? .now) }) {
                milestone.ceremonyPlayed = true
                try? context.save()
                ceremonyFor = nil
            }
        }
        .onChange(of: achieved.map { "\($0.id)\($0.ceremonyPlayed)" }) { _, _ in
            // 有新达成且未播放仪式 → 播放
            if ceremonyFor == nil,
               let pendingCeremony = achieved.first(where: { !$0.ceremonyPlayed }) {
                ceremonyFor = pendingCeremony
            }
        }
    }

    private var progressHeader: some View {
        let total = milestones.count
        let done = achieved.count
        return VStack(spacing: 12) {
            Text("\(done) / \(max(total, 1)) 个里程碑")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(BubuTheme.Color.warmBrown)
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(theme)
            Text("每一个第一次，都值得被郑重记住")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var achievedWall: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("已点亮", systemImage: "star.fill").font(BubuTheme.Font.headline).foregroundStyle(theme)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(achieved) { milestone in
                    medallion(milestone, lit: true)
                        .onTapGesture { detailFor = milestone }
                }
            }
        }
    }

    private var pendingWall: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("待点亮", systemImage: "star").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.secondaryText)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(pending) { milestone in
                    medallion(milestone, lit: false)
                        .onTapGesture { detailFor = milestone }
                }
            }
        }
    }

    private func medallion(_ milestone: Milestone, lit: Bool) -> some View {
        VStack(spacing: 8) {
            Text(milestone.emoji)
                .font(.system(size: 38))
                .grayscale(lit ? 0 : 1)
                .opacity(lit ? 1 : 0.45)
                .frame(width: 72, height: 72)
                .background(
                    Circle().fill(lit ? theme.opacity(0.15) : Color.gray.opacity(0.1))
                )
                .overlay { Circle().stroke(lit ? theme : .clear, lineWidth: 2) }
            Text(milestone.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(lit ? BubuTheme.Color.warmBrown : BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("✨").font(.system(size: 56))
            Text("还没有里程碑\n点右上角 + 号，从清单选或自定义布布的第一次")
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
