import SwiftUI

// MARK: - 登录（单家庭多账号）
/// 家人各自登录自己的账号；新账号由 PocketBase 后台创建。登录身份对应署名角色（爸爸/妈妈/姥姥）。
/// 登录成功后凭据写入 ServerConfig，同步层自动接管。
struct AccountView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var username = ""
    @State private var password = ""
    @State private var roleIndex = 1     // 默认妈妈
    @State private var busy = false
    @State private var errorText: String?

    private let service = AccountService()
    private let roles = FamilyRole.allCases

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                VStack(spacing: 12) {
                    field("用户名（如 yuanbo）", text: $username, keyboard: .default, secure: false)
                    field("密码", text: $password, keyboard: .default, secure: true)
                    rolePicker
                }
                .padding(16)
                .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))

                if let errorText {
                    Text(errorText)
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.danger)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text("登录")
                            .font(BubuTheme.Font.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(env.theme.theme.primary, in: Capsule())
                }
                .disabled(busy)

                if env.config.hasServerCredentials {
                    Button(role: .destructive) {
                        service.logout(config: env.config)
                        // 立刻用清空后的配置重建客户端与同步引擎：旧实例还握着凭据会继续偷偷同步
                        env.reloadServices(context: modelContext)
                        dismiss()
                    } label: {
                        Text("退出当前账号").font(BubuTheme.Font.caption)
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
        }
        .background(BubuTheme.Color.cream.ignoresSafeArea())
        .navigationTitle("家人登录")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("👨‍👩‍👧").font(.system(size: 44))
            Text("一家人，各自登录")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text("大家看的是同一个布布，署名各自清楚")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .padding(.top, 8)
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

    private func field(_ placeholder: String, text: Binding<String>,
                       keyboard: UIKeyboardType, secure: Bool) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .padding(12)
        .background(BubuTheme.Color.softFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func submit() async {
        busy = true
        errorText = nil
        let role = roles[roleIndex]
        do {
            try await service.login(username: username, password: password, role: role, config: env.config)
            // 用新凭据重建 API 客户端 + 同步引擎，否则首次登录后仍是启动时的 Mock，什么都拉不下来
            env.reloadServices(context: modelContext)
            env.syncEngine.syncNow()
            busy = false
            dismiss()
        } catch {
            errorText = error.localizedDescription
            busy = false
        }
    }
}
