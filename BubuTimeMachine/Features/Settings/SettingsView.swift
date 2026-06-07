import SwiftUI

// MARK: - 设置
/// 服务器配置（Base URL + 连接测试）、当前身份切换、孩子名字。
/// M0 交付物：可填 Base URL + 连接测试。
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        @Bindable var config = env.config
        Form {
            Section("我是谁") {
                Picker("当前身份", selection: $config.currentRole) {
                    ForEach(FamilyRole.allCases, id: \.self) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("孩子的名字") {
                    TextField("布布", text: $config.childName)
                        .multilineTextAlignment(.trailing)
                }
            }

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
