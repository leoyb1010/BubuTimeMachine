import SwiftUI
import SwiftData

// MARK: - 家庭成员管理
/// 增删改成员、切换当前身份。每位成员有头像 emoji 与专属色。
struct MembersView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]

    @State private var editing: FamilyMember?
    @State private var showingAdd = false
    /// 待删成员（二次确认用）。删成员会连带同步删到全家设备，不能一划就走。
    @State private var pendingDelete: FamilyMember?
    @State private var notice: String?

    private var theme: BubuThemeDefinition { env.theme.theme }

    var body: some View {
        List {
            Section {
                ForEach(members) { member in
                    memberRow(member)
                }
            } header: {
                Text("谁在记录布布的成长")
            } footer: {
                Text("点头像切换当前身份。每条记录都会署上 TA 的名字。")
            }

            Section {
                Button {
                    showingAdd = true
                } label: {
                    Label("添加家庭成员", systemImage: "person.badge.plus")
                        .foregroundStyle(theme.primary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("家庭成员")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAdd) {
            MemberEditSheet(member: nil)
        }
        .sheet(item: $editing) { member in
            MemberEditSheet(member: member)
        }
        .confirmationDialog("要删除这位家人吗？", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible, presenting: pendingDelete) { member in
            Button("删除「\(member.name)」", role: .destructive) { confirmDelete(member) }
            Button("再想想", role: .cancel) { pendingDelete = nil }
        } message: { member in
            Text("「\(member.name)」会从全家所有设备上移除，TA 记录过的内容仍然保留。")
        }
        .alert("提示", isPresented: Binding(
            get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    /// 成员行：整行点击 = 切换身份；铅笔 = 编辑。
    /// 两个动作必须并列而不能嵌套——Button 套 Button 时内层命中区会被外层吞掉，
    /// 点铅笔常常变成「切换成了这个人」（同类问题在设置主页已修过一次）。
    private func memberRow(_ member: FamilyMember) -> some View {
        let isCurrent = member.id == env.currentMemberId
        return HStack(spacing: 14) {
            Button {
                withAnimation(.smooth) { env.currentMemberId = member.id }
                env.config.currentRoleRaw = member.relation
            } label: {
                HStack(spacing: 14) {
                    Text(member.avatarEmoji)
                        // 固定圆形头像内的单 emoji，随字号放大会溢出 54pt 圆，保持固定
                        .font(.system(size: 32))
                        .frame(width: 54, height: 54)
                        .background(Color(hex: member.themeColorHex).opacity(0.18), in: Circle())
                        .overlay { Circle().stroke(isCurrent ? Color(hex: member.themeColorHex) : .clear, lineWidth: 2.5) }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                        Text(member.relation).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    Spacer(minLength: 0)
                    if isCurrent {
                        Text("当前").font(BubuTheme.Font.scaled(13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color(hex: member.themeColorHex), in: Capsule())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换到\(member.name)")

            Button { editing = member } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(BubuTheme.Font.scaled(22))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("编辑\(member.name)")
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { requestDelete(member) } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    /// 划动删除 → 先做可行性检查，再走二次确认。
    private func requestDelete(_ member: FamilyMember) {
        guard members.count > 1 else {
            // 原来这里静默 return，用户以为 App 卡住了。
            notice = "至少要留一位家人。可以先添加新成员，再删除这一位。"
            return
        }
        pendingDelete = member
    }

    private func confirmDelete(_ member: FamilyMember) {
        pendingDelete = nil
        guard members.count > 1 else { return }
        if member.id == env.currentMemberId {
            let fallback = members.first { $0.id != member.id }
            env.currentMemberId = fallback?.id
            // 同步署名身份，否则会卡在已删成员的角色（长辈时还会卡在简单模式）。
            if let relation = fallback?.relation { env.config.currentRoleRaw = relation }
        }
        PendingDeletion.enqueue(collection: "members", remoteId: member.remoteId, in: context)
        context.delete(member)
        try? context.save()
        env.syncEngine.syncNow()
        BubuHaptics.success()
    }
}

// MARK: - 成员编辑
struct MemberEditSheet: View {
    let member: FamilyMember?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var relation: Relation = .mama
    @State private var emoji = "🙂"
    @State private var colorHex = "#F28C9E"
    @FocusState private var nameFocused: Bool

    private let emojiChoices = ["👩","👨","👵","👴","🧑","👧","🧒","🙂","🌷","⭐️","🐻","🦊"]
    private let colorChoices = ["#F28C9E","#5B8DEF","#F2B705","#5BB98C","#8E7CC3","#FF9F8E","#E08D79","#73C2FB"]

    var body: some View {
        NavigationStack {
            Form {
                Section("头像") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(emojiChoices, id: \.self) { e in
                            Text(e)
                                // 头像选择格内的单 emoji，随字号放大会溢出 44pt 格，保持固定
                                .font(.system(size: 30))
                                .frame(width: 44, height: 44)
                                .background(emoji == e ? Color(hex: colorHex).opacity(0.2) : .clear, in: Circle())
                                .overlay { Circle().stroke(emoji == e ? Color(hex: colorHex) : .clear, lineWidth: 2) }
                                .onTapGesture { emoji = e }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("专属颜色") {
                    HStack(spacing: 12) {
                        ForEach(colorChoices, id: \.self) { c in
                            Circle().fill(Color(hex: c)).frame(width: 34, height: 34)
                                .overlay { Circle().stroke(.white, lineWidth: colorHex == c ? 3 : 0) }
                                .overlay { Circle().stroke(Color(hex: c), lineWidth: colorHex == c ? 2 : 0).padding(-3) }
                                .onTapGesture { colorHex = c }
                        }
                    }
                }
                Section("身份") {
                    Picker("关系", selection: $relation) {
                        ForEach(Relation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    TextField("显示名字", text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { save() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BubuTheme.Color.background.ignoresSafeArea())
            .navigationTitle(member == nil ? "添加成员" : "编辑成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.fontWeight(.bold)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let member {
            name = member.name
            relation = Relation(rawValue: member.relation) ?? .other
            emoji = member.avatarEmoji
            colorHex = member.themeColorHex
        } else {
            emoji = relation.defaultEmoji
            colorHex = relation.defaultColorHex
        }
    }

    private func save() {
        // 去掉首尾空白：纯空格名字过去能存进去，成员列表会出现一行空白
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? relation.rawValue : trimmed
        if let member {
            member.name = finalName
            member.relation = relation.rawValue
            member.avatarEmoji = emoji
            member.themeColorHex = colorHex
            member.syncState = .local
        } else {
            let m = FamilyMember(name: finalName, relation: relation.rawValue,
                                 avatarEmoji: emoji, themeColorHex: colorHex)
            context.insert(m)
        }
        try? context.save()
        dismiss()
    }
}
