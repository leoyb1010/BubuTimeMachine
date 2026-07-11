import SwiftUI
import SwiftData

// MARK: - 高级 · 自托管（Wave L §5.1 二级页）
/// 服务器地址 / AI 服务 / 连接诊断。普通成员永远不必看见 URL 和密钥——这些全收进这里。
struct AdvancedSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @State private var testing = false
    @State private var testResult: String?
    @State private var testingAI = false
    @State private var aiTestResult: String?

    var body: some View {
        @Bindable var config = env.config
        Form {
            Section {
                LabeledContent("当前状态", value: connectionText)
                LabeledContent("还在等网络",
                               value: env.syncEngine.pendingCount == 0 ? "都同步好啦" : "\(env.syncEngine.pendingCount) 条")
                if let last = env.syncEngine.lastSyncedAt {
                    LabeledContent("上次同步", value: BubuDateFormat.shortTime(last))
                }
                if let failure = env.syncEngine.lastFailureReason {
                    Text(failure).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.danger)
                }
                Button("立即同步") { env.syncEngine.syncNow() }
                    .disabled(!config.isConfigured)
            } header: {
                Text("连接诊断")
            }

            Section {
                // 服务器地址：Debug 可随时改；Release 若打包时已注入内置地址则只读展示，
                // 没注入（或被清空）时必须放出输入框兜底——否则新装机永远登录不上。
                #if DEBUG
                TextField(ServerConfig.baseURLPlaceholder, text: $config.baseURLString)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                #else
                if config.baseURL != nil {
                    LabeledContent("服务器", value: "已内置 ✓")
                } else {
                    TextField(ServerConfig.baseURLPlaceholder, text: $config.baseURLString)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
                #endif
                TextField("家庭账户邮箱", text: $config.accountEmail)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                SecureField("账户密码", text: $config.accountPassword)
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("试试能不能连上")
                        Spacer()
                        if testing { ProgressView() }
                        else if let testResult { Text(testResult).foregroundStyle(BubuTheme.Color.secondaryText) }
                    }
                }
                .disabled(!config.isConfigured || testing)
            } header: {
                Text("家里的服务器（多设备同步）")
            } footer: {
                Text("填好后，爸爸妈妈姥姥三台手机的记录会自动汇到一起。没配也没关系——离线全功能可用。")
            }

            Section {
                Toggle("让 AI 帮忙写故事", isOn: $config.aiEnabled)
                if config.aiEnabled {
                    TextField(ServerConfig.aiBaseURLPlaceholder, text: $config.aiBaseURLString)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("AI 访问密钥（服务端 AI_API_KEY）", text: $config.aiAPIKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button {
                        Task { await testAIConnection() }
                    } label: {
                        HStack {
                            Text("试试 AI 服务")
                            Spacer()
                            if testingAI { ProgressView() }
                            else if let aiTestResult { Text(aiTestResult).foregroundStyle(BubuTheme.Color.secondaryText) }
                        }
                    }
                    .disabled(config.aiBaseURLString.isEmpty || testingAI)
                }
            } header: {
                Text("AI 服务（布布的故事）")
            } footer: {
                Text("关闭时用本地模拟。开启并填好地址和密钥后，改写、旁白、转写走你自托管的服务。密钥与服务器 .env 里的 AI_API_KEY 一致。")
            }
        }
        .navigationTitle("高级 · 自托管")
        .scrollContentBackground(.hidden)
        .background(BubuTheme.Color.background)
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
        guard env.config.isConfigured else { testResult = "先填账号密码"; return }
        env.reloadServices(context: context)
        let ok = (try? await env.apiClient.ping()) ?? false
        guard ok else { testResult = "连不上"; return }
        do {
            _ = try await env.apiClient.authenticate(role: env.config.currentRole.rawValue)
            testResult = "通啦 ✓"
            env.syncEngine.syncNow()
        } catch {
            testResult = "账号不对"
        }
    }

    private func testAIConnection() async {
        testingAI = true
        aiTestResult = nil
        defer { testingAI = false }
        env.reloadServices(context: context)
        let ok = (try? await env.aiService.ping()) ?? false
        aiTestResult = ok ? "通啦 ✓" : "连不上"
    }
}

// MARK: - 备份健康度卡（Wave L §5.5）
/// 四项体检：上次同步 / 待同步 / 上次全量导出距今 / 服务器状态。任一超阈值用 warning 色提醒。
struct BackupHealthCard: View {
    @Environment(AppEnvironment.self) private var env

    /// 上次全量导出时间戳（ExportView 完成后写入）。
    @AppStorage("bubu.lastExportAt") private var lastExportAtRaw: Double = 0

    private var daysSinceExport: Int? {
        guard lastExportAtRaw > 0 else { return nil }
        let last = Date(timeIntervalSince1970: lastExportAtRaw)
        return Calendar.current.dateComponents([.day], from: last, to: .now).day
    }

    /// 导出超 90 天或从未导出 → 提醒。
    private var exportStale: Bool {
        guard let d = daysSinceExport else { return true }
        return d > 90
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: exportStale ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(exportStale ? BubuTheme.Color.warning : BubuTheme.Color.success,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text("备份健康度").font(BubuTheme.Font.body)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer()
            }
            checkLine("上次同步", value: env.syncEngine.lastSyncedAt.map { BubuDateFormat.shortTime($0) } ?? "未同步",
                      warn: env.syncEngine.lastSyncedAt == nil)
            checkLine("还在等网络", value: env.syncEngine.pendingCount == 0 ? "都好啦" : "\(env.syncEngine.pendingCount) 条",
                      warn: env.syncEngine.pendingCount > 0)
            checkLine("上次存档", value: exportText, warn: exportStale)
        }
        .padding(14)
    }

    private var exportText: String {
        guard let d = daysSinceExport else { return "未存档" }
        if d == 0 { return "今天" }
        return "\(d) 天前"
    }

    private func checkLine(_ title: String, value: String, warn: Bool) -> some View {
        HStack {
            Text(title).font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            Spacer()
            Text(value).font(BubuTheme.Font.caption.weight(.medium))
                .foregroundStyle(warn ? BubuTheme.Color.warning : BubuTheme.Color.warmBrown)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 128, alignment: .trailing)
        }
        .padding(.leading, 42)
    }
}
