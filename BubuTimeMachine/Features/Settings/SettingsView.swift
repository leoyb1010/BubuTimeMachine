import SwiftUI
import SwiftData

// MARK: - 设置
/// 布布档案、家庭成员、主题外观、服务器配置、当前身份。
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var members: [FamilyMember]
    @State private var testing = false
    @State private var testResult: String?

    private var currentMember: FamilyMember? {
        members.first { $0.id == env.currentMemberId } ?? members.first
    }

    var body: some View {
        @Bindable var config = env.config
        Form {
            // 当前身份
            Section {
                NavigationLink {
                    MembersView()
                } label: {
                    HStack(spacing: 14) {
                        Text(currentMember?.avatarEmoji ?? "🙂")
                            .font(.system(size: 30))
                            .frame(width: 50, height: 50)
                            .background(Color(hex: currentMember?.themeColorHex ?? "#F28C9E").opacity(0.18), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentMember?.name ?? "未设置").font(BubuTheme.Font.headline)
                            Text("当前身份 · 点这里管理成员").font(BubuTheme.Font.caption)
                                .foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                    }
                }
            }

            Section("布布") {
                NavigationLink {
                    ChildProfileView()
                } label: {
                    Label("布布的档案", systemImage: "figure.child")
                }
            }

            Section("外观") {
                NavigationLink {
                    ThemeSettingsView()
                } label: {
                    Label("主题与外观", systemImage: "paintpalette")
                }
            }

            // 服务器
            Section {
                TextField("http://100.x.x.x:8090", text: $config.baseURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("连接测试")
                        Spacer()
                        if testing { ProgressView() }
                        else if let testResult { Text(testResult).foregroundStyle(BubuTheme.Color.secondaryText) }
                    }
                }
                .disabled(config.baseURLString.isEmpty || testing)
            } header: {
                Text("家里的服务器")
            } footer: {
                Text("还没配也没关系——布布时光机离线就能用，照片和视频都先存在手机里。")
            }

            Section("同步状态") {
                LabeledContent("当前状态", value: connectionText)
            }
        }
        .navigationTitle("设置")
    }

    private var connectionText: String {
        switch env.syncEngine.connectionState {
        case .offline:    return "离线（本地可用）"
        case .connecting: return "连接中…"
        case .online:     return "已连接"
        }
    }

    private func testConnection() async {
        testing = true
        testResult = nil
        defer { testing = false }
        let ok = (try? await env.apiClient.ping()) ?? false
        testResult = ok ? "通啦 ✓" : "连不上"
    }
}
