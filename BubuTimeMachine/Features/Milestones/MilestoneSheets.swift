import SwiftUI
import SwiftData

// MARK: - 里程碑清单选择
/// 从出厂预设库批量挑选添加。按分类分组，已添加的标灰。
struct MilestonePickerSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [Milestone]

    @State private var selected: Set<String> = []

    private var theme: Color { env.theme.theme.primary }
    private var existingTitles: Set<String> { Set(existing.map(\.title)) }

    var body: some View {
        NavigationStack {
            List {
                ForEach(MilestoneTemplate.categories, id: \.self) { category in
                    Section(category) {
                        ForEach(presets(in: category)) { tpl in
                            row(tpl)
                        }
                    }
                }
            }
            .navigationTitle("从清单添加")
            .scrollContentBackground(.hidden)
            .background(BubuTheme.Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加\(selected.isEmpty ? "" : " \(selected.count)")") { addSelected() }
                        .fontWeight(.bold)
                        .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func presets(in category: String) -> [MilestoneTemplate] {
        MilestoneTemplate.presets.filter { $0.category == category }
    }

    private func row(_ tpl: MilestoneTemplate) -> some View {
        let added = existingTitles.contains(tpl.title)
        let isSelected = selected.contains(tpl.title)
        return HStack(spacing: 12) {
            Text(tpl.emoji).font(.system(size: 26))
            Text(tpl.title)
                .font(BubuTheme.Font.body)
                .foregroundStyle(added ? BubuTheme.Color.secondaryText : BubuTheme.Color.warmBrown)
            Spacer()
            if added {
                Text("已添加").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme)
            } else {
                Image(systemName: "circle").foregroundStyle(BubuTheme.Color.secondaryText.opacity(0.4))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !added else { return }
            if isSelected { selected.remove(tpl.title) } else { selected.insert(tpl.title) }
        }
    }

    private func addSelected() {
        for tpl in MilestoneTemplate.presets where selected.contains(tpl.title) {
            let m = Milestone(title: tpl.title, category: tpl.category, emoji: tpl.emoji)
            m.syncState = .local
            context.insert(m)
        }
        try? context.save()
        env.refreshWidgetSnapshot(context: context)
        WidgetRefresher.reload()
        dismiss()
    }
}

// MARK: - 里程碑编辑 / 点亮
/// 新建自定义里程碑，或编辑已有、标记达成（达成后由首页播放仪式）。
struct MilestoneEditSheet: View {
    let milestone: Milestone?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [ChildProfile]

    @State private var title = ""
    @State private var category = MilestoneTemplate.categories.first ?? "大运动"
    @State private var emoji = "🌟"
    @State private var detail = ""
    @State private var achieved = false
    @State private var happenedAt = Date.now

    private var profile: ChildProfile? { profiles.first }
    private var theme: Color { env.theme.theme.primary }
    private let emojiChoices = ["🌟","🍼","👣","🗣️","🦷","🚶","🏃","🎂","🥄","🚽","📚","🎨","🎵","💪","🧩","🌈"]

    // 已点亮详情头：hue 渐变 + 迸发星点 + macStarPop 图标 + 解锁信息（对照设计稿 MacMilestoneDetail）
    @ViewBuilder
    private var achievedHeader: some View {
        let hue = Double(abs((milestone?.title ?? title).hashValue) % 360)
        VStack(spacing: 0) {
            ZStack {
                BubuBurst(radius: 96)
                ZStack {
                    Circle().fill(.white.opacity(0.85)).frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
                    Text(milestone?.emoji ?? emoji).font(.system(size: 44))
                }
                .modifier(StarPop())
            }
            .frame(height: 120)
            Text(milestone?.title ?? title)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
            if let m = milestone, let d = m.happenedAt {
                Text("解锁于 \(BubuDateFormat.yearMonthDay(d))\(m.ageDescription.map { " · \($0)" } ?? "")")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(.white.opacity(0.85), in: Capsule())
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            LinearGradient(colors: [BubuTheme.Color.hue(hue, lightness: 0.84),
                                    BubuTheme.Color.hue((hue + 45).truncatingRemainder(dividingBy: 360), lightness: 0.80)],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.bottom, 4)
    }

    var body: some View {
        NavigationStack {
            Form {
                if milestone?.isAchieved == true {
                    achievedHeader
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section("里程碑") {
                    TextField("如：第一次自己走路", text: $title)
                    Picker("分类", selection: $category) {
                        ForEach(MilestoneTemplate.categories, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(emojiChoices, id: \.self) { e in
                            Text(e).font(.system(size: 26))
                                .frame(width: 38, height: 38)
                                .background(emoji == e ? theme.opacity(0.2) : .clear, in: Circle())
                                .overlay { Circle().stroke(emoji == e ? theme : .clear, lineWidth: 2) }
                                .onTapGesture { emoji = e }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Toggle("已经达成了", isOn: $achieved.animation())
                        .tint(theme)
                    if achieved {
                        DatePicker("达成那天", selection: $happenedAt,
                                   in: ...Date.now, displayedComponents: .date)
                        if let profile {
                            LabeledContent("那时的布布",
                                value: AgeCalculator.ageDescription(birthday: profile.birthday, at: happenedAt))
                        }
                    }
                }
                Section("当时的故事（可不填）") {
                    TextField("记下这一刻……", text: $detail, axis: .vertical)
                        .lineLimit(2...5)
                }
                if milestone != nil {
                    Section {
                        Button(role: .destructive) { deleteMilestone() } label: {
                            Label("删除这个里程碑", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(milestone == nil ? "自定义里程碑" : "编辑里程碑")
            .scrollContentBackground(.hidden)
            .background(BubuTheme.Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.fontWeight(.bold).disabled(title.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let m = milestone else { return }
        title = m.title
        category = m.category
        emoji = m.emoji
        detail = m.detail ?? ""
        achieved = m.isAchieved
        happenedAt = m.happenedAt ?? .now
    }

    private func save() {
        let m: Milestone
        if let existing = milestone {
            m = existing
            m.title = title
            m.category = category
            m.emoji = emoji
        } else {
            m = Milestone(title: title, category: category, emoji: emoji, isCustom: true)
            context.insert(m)
        }
        m.detail = detail.isEmpty ? nil : detail
        m.syncState = .local
        if achieved {
            let wasNewlyAchieved = m.happenedAt == nil
            m.happenedAt = happenedAt
            if let profile {
                m.ageDescription = AgeCalculator.ageDescription(birthday: profile.birthday, at: happenedAt)
            }
            if wasNewlyAchieved {
                BubuSound.play(.milestone)
                context.insert(FeedEvent(kind: .milestoneLit, actorRole: env.config.currentRole.rawValue,
                                         summary: "点亮了「\(m.title)」"))
            }
        } else {
            m.happenedAt = nil
            m.ageDescription = nil
        }
        try? context.save()
        env.refreshWidgetSnapshot(context: context)
        WidgetRefresher.reload()
        dismiss()
    }

    private func deleteMilestone() {
        if let m = milestone {
            PendingDeletion.enqueue(collection: "milestones", remoteId: m.remoteId, in: context)
            context.delete(m)
            try? context.save()
            env.refreshWidgetSnapshot(context: context)
            WidgetRefresher.reload()
            env.syncEngine.syncNow()
        }
        dismiss()
    }
}

// macStarPop：0 → 1.18 → 1 的弹出（reduceMotion 时不动）。
private struct StarPop: ViewModifier {
    @State private var scale: CGFloat = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : scale)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.1)) { scale = 1 }
            }
    }
}
