import SwiftUI
import SwiftData

// MARK: - 账号与安全（单家庭多账号）
/// 未登录：登录表单。已登录：显示「我是谁、连着哪台服务器」+ 修改密码 + 家庭恢复码 + 退出。
///
/// 旧版登录成功后仍是一张空白表单，用户无从确认自己登的是哪个账号——
/// 账号页的第一职责是「让人看清当前状态」，其次才是操作。
struct AccountView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var welcomeSync = false

    @State private var username = ""
    @State private var password = ""
    @State private var roleIndex = 1     // 默认妈妈
    @State private var busy = false
    @State private var errorText: String?
    @State private var showLogoutConfirm = false
    @State private var showChangePassword = false
    @State private var showRecovery = false
    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    private let service = AccountService()
    private let roles = FamilyRole.allCases

    private var isLoggedIn: Bool { env.config.hasServerCredentials }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if isLoggedIn {
                    signedInCard
                    accountActions
                } else {
                    header
                    loginForm
                    if let errorText { errorBanner(errorText) }
                    loginButton
                }
            }
            .padding()
            .bubuContentColumn()   // 宽屏收进居中内容列，窄屏原样
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .overlay { if welcomeSync { welcomeOverlay } }
        .navigationTitle("账号与安全")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showChangePassword) { ChangePasswordSheet() }
        .sheet(isPresented: $showRecovery) { CapsuleRecoveryView() }
        .confirmationDialog("要退出这个账号吗？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { performLogout() }
            Button("再想想", role: .cancel) {}
        } message: {
            Text("退出后这台设备不再同步，已经存在本机的照片和记录都还在，随时可以重新登录。")
        }
    }

    // MARK: 已登录

    private var signedInCard: some View {
        VStack(spacing: 14) {
            Text("🏡").font(BubuTheme.Font.scaled(42))
            Text(AccountService.usernameFrom(email: env.config.accountEmail))
                .font(BubuTheme.Font.title)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text("当前署名：\(env.config.currentRole.displayName)")
                .font(BubuTheme.Font.caption.weight(.semibold))
                .foregroundStyle(env.theme.theme.primary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(env.theme.theme.primary.opacity(0.12), in: Capsule())

            VStack(spacing: 8) {
                infoLine("账号", env.config.accountEmail)
                infoLine("服务器", env.config.baseURLString.isEmpty ? "未配置" : env.config.baseURLString)
                infoLine("连接", connectionText)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func infoLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(BubuTheme.Font.caption.weight(.medium))
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }

    private var connectionText: String {
        switch env.syncEngine.connectionState {
        case .offline:    return "离线（本地可用）"
        case .connecting: return "连接中…"
        case .online:     return "已连接"
        }
    }

    private var accountActions: some View {
        VStack(spacing: 0) {
            actionRow("修改密码", icon: "key.fill", tint: env.theme.theme.primary) {
                showChangePassword = true
            }
            Divider().padding(.leading, 54)
            actionRow("家庭恢复码", icon: "lock.rotation", tint: BubuTheme.Color.info,
                      subtitle: "换手机时用它打开加密的时间胶囊") {
                showRecovery = true
            }
            Divider().padding(.leading, 54)
            actionRow("退出登录", icon: "rectangle.portrait.and.arrow.right",
                      tint: BubuTheme.Color.danger, isDestructive: true) {
                showLogoutConfirm = true
            }
        }
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func actionRow(_ title: String, icon: String, tint: Color,
                           subtitle: String? = nil, isDestructive: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(BubuTheme.Font.scaled(15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small * 0.6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BubuTheme.Font.body.weight(.medium))
                        .foregroundStyle(isDestructive ? BubuTheme.Color.danger : BubuTheme.Color.warmBrown)
                    if let subtitle {
                        Text(subtitle)
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(BubuTheme.Font.scaled(12, weight: .bold))
                    .foregroundStyle(BubuTheme.Color.secondaryText.opacity(0.6))
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func performLogout() {
        service.logout(config: env.config)
        // 立刻用清空后的配置重建客户端与同步引擎：旧实例还握着凭据会继续偷偷同步
        env.reloadServices(context: modelContext)
        dismiss()
    }

    // MARK: 未登录

    private var header: some View {
        VStack(spacing: 6) {
            Text("👨‍👩‍👧").font(BubuTheme.Font.scaled(44))
            Text("一家人，各自登录")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text("大家看的是同一个布布，署名各自清楚")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .padding(.top, 8)
    }

    private var loginForm: some View {
        VStack(spacing: 12) {
            // textContentType 让 iOS 认出这是账号密码框：钥匙串自动填充与「保存密码」才会工作。
            TextField("用户名（如 yuanbo）", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .username)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }
                .fieldBox()
            SecureField("密码（至少 8 位）", text: $password)
                .textContentType(.password)
                // SecureField 也要关自动大写：原来这两个修饰符只加在 TextField 分支上，
                // 密码首字母被自动大写、用户反复登录失败。
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { Task { await submit() } }
                .fieldBox()
            rolePicker
        }
        .padding(16)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(BubuTheme.Font.caption)
            .foregroundStyle(BubuTheme.Color.danger)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(BubuTheme.Color.danger.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
    }

    private var loginButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack {
                if busy { ProgressView().tint(.white) }
                Text("登录").font(BubuTheme.Font.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(env.theme.theme.primary, in: Capsule())
        }
        .disabled(busy)
    }

    private var rolePicker: some View {
        HStack {
            Text("我是").font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
            Spacer()
            Picker("我是", selection: $roleIndex) {
                ForEach(roles.indices, id: \.self) { i in
                    Text(roles[i].displayName).tag(i)
                }
            }
            .pickerStyle(.menu)
            .tint(env.theme.theme.primary)
        }
    }

    // MARK: 首登等待

    private var welcomeOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("🏠").font(BubuTheme.Font.scaled(44))
                Text("正在把布布接回家…")
                    .font(BubuTheme.Font.scaled(17, weight: .heavy))
                    .foregroundStyle(.white)
                if let label = env.syncEngine.currentSyncLabel {
                    Text(label)
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                ProgressView().tint(.white)
                Text("全家的时光正在同步过来，第一次会久一点")
                    .font(BubuTheme.Font.scaled(12))
                    .foregroundStyle(.white.opacity(0.7))
                // 等待可随时收起：同步在后台继续，不该把用户锁在遮罩里干等。
                Button("先进去看看") {
                    welcomeSync = false
                }
                .font(BubuTheme.Font.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.white.opacity(0.18), in: Capsule())
                .padding(.top, 4)
            }
            .padding(30)
            .background(BubuTheme.Color.warmBrown.opacity(0.95),
                        in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        }
    }

    private func submit() async {
        busy = true
        errorText = nil
        focusedField = nil
        let role = roles[roleIndex]
        do {
            try await service.login(username: username, password: password, role: role, config: env.config)
            // 用新凭据重建 API 客户端 + 同步引擎，否则首次登录后仍是启动时的 Mock，什么都拉不下来
            env.reloadServices(context: modelContext)
            env.syncEngine.syncNow()
            // 新设备（本地还没有任何时光）：展示「接布布回家」进度，等首轮同步拉完再进（R4 G-4）
            let entryCount = (try? modelContext.fetchCount(FetchDescriptor<Entry>())) ?? 0
            if entryCount == 0 {
                welcomeSync = true
                let start = Date.now
                while welcomeSync, Date.now.timeIntervalSince(start) < 90 {
                    try? await Task.sleep(for: .seconds(1))
                    if env.syncEngine.lastSyncedAt != nil { break }
                }
                welcomeSync = false
            }
            busy = false
            password = ""
            dismiss()
        } catch {
            errorText = AccountService.friendlyMessage(error)
            busy = false
        }
    }
}

// MARK: - 修改密码
private struct ChangePasswordSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var done = false
    @FocusState private var focused: Field?

    private enum Field { case old, new, confirm }
    private let service = AccountService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        SecureField("当前密码", text: $oldPassword)
                            .textContentType(.password)
                            .focused($focused, equals: .old)
                            .submitLabel(.next)
                            .onSubmit { focused = .new }
                            .fieldBox()
                        SecureField("新密码（至少 8 位）", text: $newPassword)
                            .textContentType(.newPassword)
                            .focused($focused, equals: .new)
                            .submitLabel(.next)
                            .onSubmit { focused = .confirm }
                            .fieldBox()
                        SecureField("再输一次新密码", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .focused($focused, equals: .confirm)
                            .submitLabel(.done)
                            .onSubmit { Task { await submit() } }
                            .fieldBox()
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(16)
                    .background(BubuTheme.Color.card,
                                in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                    .bubuCardShadow()

                    if let errorText {
                        Text(errorText)
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.danger)
                            .multilineTextAlignment(.center)
                    }
                    if done {
                        Label("密码已更新", systemImage: "checkmark.circle.fill")
                            .font(BubuTheme.Font.body.weight(.semibold))
                            .foregroundStyle(BubuTheme.Color.success)
                    }

                    Text("改完之后，这台设备会自动用新密码继续同步。其他家人的设备需要各自重新登录一次。")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding()
            }
            .background(BubuTheme.Color.background.ignoresSafeArea())
            .navigationTitle("修改密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await submit() } } label: {
                        if busy { ProgressView() } else { Text("保存").fontWeight(.bold) }
                    }
                    .disabled(busy || oldPassword.isEmpty || newPassword.isEmpty)
                }
            }
        }
    }

    private func submit() async {
        busy = true
        errorText = nil
        focused = nil
        do {
            try await service.changePassword(old: oldPassword, new: newPassword,
                                             confirm: confirmPassword, config: env.config)
            // 新密码已落钥匙串，必须重建客户端：旧实例握着旧密码，token 过期后重登会失败。
            env.reloadServices(context: modelContext)
            done = true
            BubuHaptics.success()
            busy = false
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        } catch {
            errorText = AccountService.friendlyMessage(error)
            busy = false
        }
    }
}

// MARK: - 输入框统一外观
private extension View {
    func fieldBox() -> some View {
        padding(12)
            .background(BubuTheme.Color.softFill,
                        in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
    }
}
