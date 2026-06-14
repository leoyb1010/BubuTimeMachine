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
    @State private var searchText = ""
    @State private var selectedCategory = "全部"
    @State private var isConstellation = false   // 展示方式：奖章墙 / 成长星座

    private var theme: Color { env.theme.theme.primary }
    private var profile: ChildProfile? { profiles.first }

    private var achieved: [Milestone] { filteredMilestones.filter(\.isAchieved) }
    private var allPending: [Milestone] { filteredMilestones.filter { !$0.isAchieved } }
    private var pending: [Milestone] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCategory == "全部" {
            return Array(allPending.prefix(12))
        }
        return allPending
    }
    private var filteredMilestones: [Milestone] {
        milestones.filter { milestone in
            let categoryOK = selectedCategory == "全部" || milestone.category == selectedCategory
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchOK = query.isEmpty || milestone.title.localizedCaseInsensitiveContains(query) || milestone.category.localizedCaseInsensitiveContains(query)
            return categoryOK && searchOK
        }
    }
    private var categoryOptions: [String] { ["全部"] + MilestoneTemplate.categories }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                progressHeader
                filters
                if isConstellation {
                    // 成长星座视图（复用同一份筛选后的里程碑）
                    BubuConstellationView(milestones: filteredMilestones, primary: theme) { m in
                        detailFor = m
                    }
                } else {
                    if !achieved.isEmpty { achievedWall }
                    if !pending.isEmpty { pendingWall }
                }
                if milestones.isEmpty { emptyState }
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("里程碑")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isConstellation.toggle() }
                } label: {
                    Image(systemName: isConstellation ? "square.grid.2x2.fill" : "sparkles")
                }
                .accessibilityLabel(isConstellation ? "切换到奖章墙" : "切换到成长星座")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showCustom = true } label: { Label("自定义里程碑", systemImage: "star.bubble") }
                    Button { showPicker = true } label: { Label("管理预设清单", systemImage: "list.bullet") }
                } label: { Image(systemName: "plus.circle.fill") }
                .accessibilityLabel("添加里程碑")
            }
        }
        .sheet(isPresented: $showPicker) { MilestonePickerSheet() }
        .sheet(isPresented: $showCustom) { MilestoneEditSheet(milestone: nil) }
        .sheet(item: $detailFor) { MilestoneEditSheet(milestone: $0) }
        .fullScreenCover(item: $ceremonyFor) { milestone in
            CeremonyAnimation(title: "🎉 \(milestone.title)",
                              subtitle: profile.map { AgeCalculator.ageDescription(birthday: $0.birthday, at: milestone.happenedAt ?? .now) }) {
                milestone.ceremonyPlayed = true
                milestone.syncState = .local
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
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("搜索里程碑，比如 走路、吃饭、睡觉", text: $searchText)
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .padding(12)
                .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous)
                        .stroke(BubuTheme.Color.hairline.opacity(0.7), lineWidth: 1)
                }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categoryOptions, id: \.self) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            Text(category)
                                .font(BubuTheme.Font.caption.weight(.semibold))
                                .foregroundStyle(selectedCategory == category ? .white : theme)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(selectedCategory == category ? theme : BubuTheme.Color.softFill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var achievedWall: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("已点亮", systemImage: "star.fill").font(BubuTheme.Font.headline).foregroundStyle(theme)
                // 点亮新里程碑时星标弹跳一下（交互/数据驱动，非持续动画）。
                .symbolEffect(.bounce, value: achieved.count)
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
            Label("适龄推荐 · 待点亮", systemImage: "star").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.secondaryText)
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCategory == "全部" {
                Text("先看最可能发生的 12 个。其它里程碑可以用搜索或分类找到，不把 100 多项都压在眼前。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
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
                    Circle().fill(lit ? theme.opacity(0.15) : BubuTheme.Color.softFill)
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
            BubuMascotBadge(size: 84, expression: .cheer)
            Text("还没有里程碑\n点右上角 + 号，从清单选或自定义布布的第一次")
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
