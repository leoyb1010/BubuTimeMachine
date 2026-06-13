import SwiftUI
import SwiftData

// MARK: - 首次启动引导
/// 温暖的开场：欢迎 → 设置布布生日 → 创建第一个家庭成员（你是谁）。
/// 完成后写入 ChildProfile + FamilyMember，标记 onboarding 完成。
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context

    @State private var step = 0
    @State private var childName = "布布"
    @State private var birthday = Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .now
    @State private var selectedRelation: Relation = .mama
    @State private var memberName = ""

    private var theme: BubuThemeDefinition { env.theme.theme }

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            VStack {
                progressDots
                Spacer()
                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: birthdayStep
                    default: memberStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))
                Spacer()
                primaryButton
            }
            .padding(28)
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(colors: [theme.primary.opacity(0.18), theme.secondary.opacity(0.12)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i == step ? theme.primary : theme.primary.opacity(0.25))
                    .frame(width: i == step ? 22 : 8, height: 8)
                    .animation(.smooth, value: step)
            }
        }
        .padding(.top, 12)
    }

    // MARK: Steps

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image("BubuLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: theme.primary.opacity(0.3), radius: 16, y: 8)
            VStack(spacing: 12) {
                Text("欢迎来到布布时光机")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("为布布留住每一个值得记住的此刻，\n陪她长大，等她某天亲手翻开。")
                    .font(BubuTheme.Font.body)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
    }

    private var birthdayStep: some View {
        VStack(spacing: 22) {
            Text("👶")
                .font(.system(size: 64))
            Text("布布是哪天来到世界的？")
                .font(BubuTheme.Font.title)
                .foregroundStyle(BubuTheme.Color.warmBrown)

            VStack(spacing: 16) {
                HStack {
                    Text("名字").font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
                    Spacer()
                    TextField("布布", text: $childName)
                        .multilineTextAlignment(.trailing)
                        .font(BubuTheme.Font.headline)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                }
                Divider()
                DatePicker("生日", selection: $birthday, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .font(BubuTheme.Font.body)
            }
            .padding(20)
            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .bubuCardShadow()

            // 实时年龄预览
            Text("现在的布布：\(AgeCalculator.ageDescription(birthday: birthday, at: .now))")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(theme.primary)
        }
    }

    private var memberStep: some View {
        VStack(spacing: 22) {
            Text(selectedRelation.defaultEmoji)
                .font(.system(size: 64))
            Text("你是布布的……")
                .font(BubuTheme.Font.title)
                .foregroundStyle(BubuTheme.Color.warmBrown)

            // 关系选择
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(Relation.allCases, id: \.self) { rel in
                    Button {
                        withAnimation(.smooth) { selectedRelation = rel }
                    } label: {
                        VStack(spacing: 4) {
                            Text(rel.defaultEmoji).font(.system(size: 28))
                            Text(rel.rawValue).font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedRelation == rel ? theme.primary.opacity(0.18) : BubuTheme.Color.softFill,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selectedRelation == rel ? theme.primary : .clear, lineWidth: 2)
                        }
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("也可以填你的名字（选填）", text: $memberName)
                .multilineTextAlignment(.center)
                .font(BubuTheme.Font.body)
                .padding()
                .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
        }
    }

    // MARK: Button

    private var primaryButton: some View {
        Button {
            advance()
        } label: {
            Text(step < 2 ? "继续" : "开始记录布布的成长")
                .font(BubuTheme.Font.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(theme.primary, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.button, style: .continuous))
                .bubuCardShadow()
        }
        .buttonStyle(.plain)
    }

    private func advance() {
        if step < 2 {
            withAnimation(.smooth) { step += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        // 创建布布档案
        let profile = ChildProfile(name: childName.isEmpty ? "布布" : childName, birthday: birthday)
        context.insert(profile)

        // 创建第一个成员（主账号）
        let displayName = memberName.isEmpty ? selectedRelation.rawValue : memberName
        let member = FamilyMember(name: displayName, relation: selectedRelation.rawValue,
                                  avatarEmoji: selectedRelation.defaultEmoji,
                                  themeColorHex: selectedRelation.defaultColorHex)
        member.isPrimary = true
        context.insert(member)

        try? context.save()

        env.currentMemberId = member.id
        env.config.childName = profile.name
        env.config.currentRoleRaw = selectedRelation.rawValue
        env.refreshWidgetSnapshot(context: context)
        WidgetRefresher.reload()
        withAnimation(.smooth) {
            env.hasCompletedOnboarding = true
        }
    }
}
