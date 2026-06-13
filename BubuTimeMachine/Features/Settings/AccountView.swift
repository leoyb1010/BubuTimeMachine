import SwiftUI

// MARK: - 登录 / 注册（单家庭多账号）
/// 家人各自登录自己的账号；注册需要家庭码。登录身份对应署名角色（爸爸/妈妈/姥姥）。
/// 登录成功后凭据写入 ServerConfig，同步层自动接管。
struct AccountView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var isRegister = false
    @State private var email = ""
    @State private var password = ""
    @State private var familyCode = ""
    @State private var roleIndex = 1     // 默认妈妈
    @State private var busy = false
    @State private var errorText: String?

    private let service = AccountService()
    private let roles = FamilyRole.allCases

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                segmented

                VStack(spacing: 12) {
                    field("邮箱", text: $email, keyboard: .emailAddress, secure: false)
                    field("密码（至少 6 位）", text: $password, keyboard: .default, secure: true)
                    if isRegister {
                        field("家庭码", text: $familyCode, keyboard: .default, secure: false)
                    }
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
                        Text(isRegister ? "注册并登录" : "登录")
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

    private var segmented: some View {
        Picker("", selection: $isRegister) {
            Text("登录").tag(false)
            Text("注册").tag(true)
        }
        .pickerStyle(.segmented)
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
            if isRegister {
                try await service.register(email: email, password: password,
                                           familyCode: familyCode, role: role, config: env.config)
            } else {
                try await service.login(email: email, password: password, role: role, config: env.config)
            }
            busy = false
            dismiss()
        } catch {
            errorText = error.localizedDescription
            busy = false
        }
    }
}
