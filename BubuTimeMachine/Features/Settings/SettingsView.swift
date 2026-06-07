import SwiftUI
import SwiftData

// MARK: - 设置
/// 布布档案、家庭成员、主题、服务器同步、AI 服务、成长之声、全量导出、提醒。
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
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
                NavigationLink { ChildProfileView() } label: {
                    Label("布布的档案", systemImage: "figure.child")
                }
                NavigationLink { VoiceArchiveView() } label: {
                    Label("成长之声", systemImage: "waveform.badge.mic")
                }
            }

            Section("外观") {
                NavigationLink { ThemeSettingsView() } label: {
                    Label("主题与外观", systemImage: "paintpalette")
                }
            }

            // 服务器（同步）
            Section {
                TextField("http://100.x.x.x:8090", text: $config.baseURLString)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("家庭账户邮箱", text: $config.accountEmail)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                SecureField("账户密码", text: $config.accountPassword)
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("连接测试并保存")
                        Spacer()
                        if testing { ProgressView() }
                        else if let testResult { Text(testResult).foregroundStyle(BubuTheme.Color.secondaryText) }
                    }
                }
                .disabled(config.baseURLString.isEmpty || testing)
            } header: {
                Text("家里的服务器（多设备同步）")
            } footer: {
                Text("填好后，爸爸妈妈姥姥三台手机的记录会自动汇到一起。没配也没关系——离线全功能可用。")
            }

            // AI 服务
            Section {
                Toggle("启用真实 AI", isOn: $config.aiEnabled)
                if config.aiEnabled {
                    TextField("http://100.x.x.x:8000", text: $config.aiBaseURLString)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
            } header: {
                Text("AI 服务（工坊）")
            } footer: {
                Text("关闭时，AI 工坊用本地模拟。开启并填好地址后，改写、旁白、转写走你自托管的服务。")
            }

            // 提醒
            Section {
                Toggle("那年今日 · 每日回忆提醒", isOn: $config.dailyReminderEnabled)
                    .onChange(of: config.dailyReminderEnabled) { _, on in
                        Task { await ReminderScheduler.shared.update(enabled: on, context: context) }
                    }
            } footer: {
                Text("每天提醒一次：往年的今天，布布在做什么。")
            }

            // 全量导出
            Section {
                NavigationLink { ExportView() } label: {
                    Label("导出布布的全量档案", systemImage: "square.and.arrow.up.on.square")
                }
            } footer: {
                Text("把一切打包成一个能直接打开的网页 + 媒体包。即使将来 App 不在了，硬盘里仍是布布完整的一生。")
            }

            // 同步状态
            Section("同步状态") {
                LabeledContent("当前状态", value: connectionText)
                if let last = env.syncEngine.lastSyncedAt {
                    LabeledContent("上次同步", value: last.formatted(date: .omitted, time: .shortened))
                }
                Button("立即同步") { env.syncEngine.syncNow() }
                    .disabled(!config.isConfigured)
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
        // 保存配置 → 重建客户端 → ping
        env.reloadServices(context: context)
        let ok = (try? await env.apiClient.ping()) ?? false
        testResult = ok ? "通啦 ✓" : "连不上"
    }
}
