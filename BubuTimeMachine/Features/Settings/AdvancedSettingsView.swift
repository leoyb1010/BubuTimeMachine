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
                NavigationLink { SyncCenterView() } label: {
                    Label("同步与备份中心", systemImage: "arrow.triangle.2.circlepath")
                }
            } footer: {
                Text("同步状态、进度与「重新拉取 / 重传」都在那里。")
            }

            Section {
                // 地址/账号一律走缓冲输入：这些字段的 setter 有副作用——写 UserDefaults、
                // 写钥匙串，主地址变化还会清空同步游标。逐键触发等于「打字过程中反复清同步状态」。
                // 缓冲后副作用只在用户输完（失焦/回车）发生一次。
                //
                // 服务器地址：始终显示实际值、始终可编辑。旧版「已内置 ✓」只读设计是黑箱——
                // 地址错了/残留旧值时用户既看不见也改不了（真机踩过：iPad 残留旧地址被藏住，同步彻底卡死）。
                BubuBufferedField(title: "服务器地址", placeholder: ServerConfig.baseURLPlaceholder,
                                  value: config.baseURLString,
                                  onCommit: { config.baseURLString = $0 },
                                  keyboard: .URL, autocapitalization: .never,
                                  disableAutocorrection: true, stacked: true)
                // 局域网直连（可选）：主地址走 Tailscale/隧道回落公网中继时，家里同一 Wi-Fi
                // 传照片会绕外网。填了这个，照片/视频传输自动与主地址赛跑择优。
                BubuBufferedField(title: "局域网直连（可选）", placeholder: "http://192.168.1.10:8090",
                                  value: config.lanBaseURLString,
                                  onCommit: { config.lanBaseURLString = $0 },
                                  keyboard: .URL, autocapitalization: .never,
                                  disableAutocorrection: true, stacked: true)
                BubuBufferedField(title: "家庭账户邮箱", placeholder: "family@example.com",
                                  value: config.accountEmail,
                                  onCommit: { config.accountEmail = $0 },
                                  keyboard: .emailAddress, autocapitalization: .never,
                                  disableAutocorrection: true, stacked: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("账户密码")
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                    SecureField("至少 8 位", text: $config.accountPassword)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
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
                // 只要填了地址就能测连通性——账号还没填时也该允许先验证服务器可达（原来要三项齐全才可点）。
                .disabled(config.baseURL == nil || testing)
            } header: {
                Text("家里的服务器（多设备同步）")
            } footer: {
                Text("填好后，爸爸妈妈姥姥三台手机的记录会自动汇到一起。没配也没关系——离线全功能可用。")
            }

            Section {
                Toggle("让 AI 帮忙写故事", isOn: $config.aiEnabled)
                if config.aiEnabled {
                    Toggle("搜索照片里的画面", isOn: $config.semanticSearchEnabled)
                    TextField(ServerConfig.aiBaseURLPlaceholder, text: $config.aiBaseURLString)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
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
                Text("照片搜索默认关闭；开启后只把搜索词发给家中自托管服务，照片本身仍留在家里的服务器。AI 复用家庭服务器登录态，不需要在 App 保存共享密钥；服务不可用时自动回到本地文字搜索。")
            }
        }
        .navigationTitle("高级 · 自托管")
        .navigationBarTitleDisplayMode(.inline)
        .bubuContentColumn(760)   // Form 宽屏收口：760 比正文列宽些，容得下右侧输入框
        .scrollContentBackground(.hidden)
        .background(BubuTheme.Color.background)
        // 打开能力的瞬间就切换到当前配置，避免后台时光轴短暂复用旧 host 的客户端。
        .onChange(of: env.config.aiEnabled) { _, _ in env.reloadAIService() }
        .onChange(of: env.config.semanticSearchEnabled) { _, _ in env.reloadAIService() }
        .onDisappear { env.reloadAIService() }
    }

    private var connectionText: String {
        switch env.syncEngine.connectionState {
        case .offline:    return "离线（本地可用）"
        case .connecting: return "连接中…"
        case .online:     return "已连接"
        }
    }

    /// 分两段测：先只验服务器可达（不需要账号），再验账号。
    /// 这样「地址填对了但账号还没填」能得到确切答复，而不是被按钮禁用挡在门外。
    private func testConnection() async {
        testing = true
        testResult = nil
        defer { testing = false }
        guard let baseURL = env.config.baseURL else { testResult = "先填地址"; return }
        // 直接探 /api/health：不依赖账号，也不受当前 apiClient 是否为 Mock 影响。
        var req = URLRequest(url: baseURL.appendingPathComponent("api/health"))
        req.timeoutInterval = 10
        let reachable: Bool
        if let (_, resp) = try? await URLSession.shared.data(for: req) {
            reachable = (resp as? HTTPURLResponse)?.statusCode == 200
        } else {
            reachable = false
        }
        guard reachable else { testResult = "连不上这个地址"; return }
        guard env.config.hasServerCredentials else { testResult = "地址通了，还差账号密码"; return }
        env.reloadServices(context: context)
        do {
            _ = try await env.apiClient.authenticate(role: env.config.currentRole.rawValue)
            testResult = "通啦 ✓"
            env.syncEngine.syncNow()
        } catch {
            testResult = "地址通了，账号或密码不对"
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
