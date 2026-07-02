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

    private var theme: BubuThemeDefinition { env.theme.theme }

    var body: some View {
        List {
            Section {
                ForEach(members) { member in
                    memberRow(member)
                }
                .onDelete(perform: deleteMembers)
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
        .navigationTitle("家庭成员")
        .sheet(isPresented: $showingAdd) {
            MemberEditSheet(member: nil)
        }
        .sheet(item: $editing) { member in
            MemberEditSheet(member: member)
        }
    }

    private func memberRow(_ member: FamilyMember) -> some View {
        let isCurrent = member.id == env.currentMemberId
        return Button {
            withAnimation(.smooth) { env.currentMemberId = member.id }
            env.config.currentRoleRaw = member.relation
        } label: {
            HStack(spacing: 14) {
                Text(member.avatarEmoji)
                    .font(.system(size: 32))
                    .frame(width: 54, height: 54)
                    .background(Color(hex: member.themeColorHex).opacity(0.18), in: Circle())
                    .overlay { Circle().stroke(isCurrent ? Color(hex: member.themeColorHex) : .clear, lineWidth: 2.5) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                    Text(member.relation).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
                Spacer()
                if isCurrent {
                    Text("当前").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color(hex: member.themeColorHex), in: Capsule())
                }
                Button { editing = member } label: {
                    Image(systemName: "pencil.circle").foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func deleteMembers(_ offsets: IndexSet) {
        // 不允许删光：至少保留一个
        guard members.count > 1 else { return }
        for i in offsets {
            let m = members[i]
            if m.id == env.currentMemberId {
                env.currentMemberId = members.first { $0.id != m.id }?.id
            }
            PendingDeletion.enqueue(collection: "members", remoteId: m.remoteId, in: context)
            context.delete(m)
        }
        try? context.save()
        env.syncEngine.syncNow()
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

    private let emojiChoices = ["👩","👨","👵","👴","🧑","👧","🧒","🙂","🌷","⭐️","🐻","🦊"]
    private let colorChoices = ["#F28C9E","#5B8DEF","#F2B705","#5BB98C","#8E7CC3","#FF9F8E","#E08D79","#73C2FB"]

    var body: some View {
        NavigationStack {
            Form {
                Section("头像") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(emojiChoices, id: \.self) { e in
                            Text(e).font(.system(size: 30))
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
                }
            }
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
        let finalName = name.isEmpty ? relation.rawValue : name
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
