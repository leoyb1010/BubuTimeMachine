import SwiftUI
import SwiftData
import WebKit

/// No credentials enter this identity; it also tears down old views when settings or accounts change.
struct LearningServiceAccess: Hashable {
    let baseURL: URL
    let account: String
    let revision: Int

    init?(_ env: AppEnvironment, requiresAIEnabled: Bool = true) {
        self.init(trustedServiceURL: env.config.aiBaseURL, serverURL: env.config.baseURL,
                  accountEmail: env.config.accountEmail, revision: env.aiServiceRevision,
                  serverConfigured: env.config.isConfigured, aiEnabled: env.config.aiEnabled,
                  requiresAIEnabled: requiresAIEnabled)
    }

    /// The service URL must already have passed ServerConfig's trusted-host validation.
    init?(trustedServiceURL: URL?, serverURL: URL?, accountEmail: String, revision: Int,
          serverConfigured: Bool, aiEnabled: Bool, requiresAIEnabled: Bool = true) {
        guard serverConfigured, !requiresAIEnabled || aiEnabled, let trustedURL = trustedServiceURL,
              var service = URLComponents(url: trustedURL, resolvingAgainstBaseURL: false),
              let pbURL = serverURL,
              var server = URLComponents(url: pbURL, resolvingAgainstBaseURL: false) else { return nil }
        service.query = nil; service.fragment = nil
        server.user = nil; server.password = nil; server.query = nil; server.fragment = nil
        guard let base = service.url else { return nil }
        baseURL = base
        account = (server.url?.absoluteString ?? "") + "\n" + accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.revision = revision
    }
}

struct SchoolLearningView: View {
    let day: Date
    var childID: String? = nil
    @Environment(AppEnvironment.self) private var env
    @Query private var profiles: [ChildProfile]

    var body: some View {
        Group {
            if let access = LearningServiceAccess(env, requiresAIEnabled: false) {
                let selectedChild = childID ?? profiles.first?.id.uuidString
                SchoolLearningSession(access: access, day: day, childID: selectedChild)
                    .id(PageIdentity(access: access, day: day, childID: selectedChild))
            } else {
                ContentUnavailableView {
                    Label("等待第二大脑同步素材", systemImage: "sparkles")
                } description: {
                    Text("请先在设置中连接家庭服务。第二大脑整理出的素材和互动课，会出现在这里。")
                }
            }
        }
        .navigationTitle("一起学")
        .navigationBarTitleDisplayMode(.inline)
        .background(BubuTheme.Color.background)
        .accessibilityIdentifier("school.learning")
    }
    private struct PageIdentity: Hashable { let access: LearningServiceAccess; let day: Date; let childID: String? }
}

private struct SchoolLearningSession: View {
    let access: LearningServiceAccess
    let day: Date
    let childID: String?
    @Environment(AppEnvironment.self) private var env
    @State private var request: URLRequest?
    @State private var loading = true
    @State private var errorText: String?
    @State private var authorizationID = UUID()

    var body: some View {
        ZStack {
            if let request {
                let attempt = authorizationID
                LearningWebView(request: request, routes: LearningServiceRoutes(baseURL: access.baseURL), storageScope: access,
                    onLoading: { if authorizationID == attempt { loading = $0 } },
                    onError: { if authorizationID == attempt { errorText = $0; loading = false } })
                    .id(authorizationID)
            }
            if let errorText {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                    Text(errorText).multilineTextAlignment(.center)
                    Button("重新连接") { Task { await authorize() } }.buttonStyle(.borderedProminent)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BubuTheme.Color.background)
            } else if loading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在打开这一天的学习空间…").font(.callout)
                }.padding(20).background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .task { await authorize() }
        .onDisappear { authorizationID = UUID(); request = nil }
    }

    private func authorize() async {
        let attempt = UUID()
        authorizationID = attempt
        request = nil; errorText = nil; loading = true
        guard LearningServiceAccess(env, requiresAIEnabled: false) == access else { loading = false; return }
        let api = env.apiClient
        do {
            let token = try await api.authenticate(role: "ai").token
            guard !Task.isCancelled, authorizationID == attempt, LearningServiceAccess(env, requiresAIEnabled: false) == access else { return }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd"
            request = try LearningServiceRoutes(baseURL: access.baseURL).pageRequest(
                day: formatter.string(from: day), childID: childID, token: token)
        } catch {
            guard !Task.isCancelled, authorizationID == attempt else { return }
            loading = false
            errorText = (error as? LearningServiceError)?.errorDescription ?? "暂时无法打开家庭学习空间，请检查网络后重试。"
        }
    }
}

private struct LearningWebView: UIViewRepresentable {
    let request: URLRequest
    let routes: LearningServiceRoutes
    let storageScope: LearningServiceAccess
    let onLoading: (Bool) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // AttemptQueue uses localStorage. Keep its account-scoped store when views close or credentials refresh.
        configuration.websiteDataStore = LearningWebsiteDataStore.make(
            serviceURL: storageScope.baseURL, account: storageScope.account)
        configuration.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.load(request)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.parent = self }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.active = false
        view.navigationDelegate = nil
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LearningWebView
        var active = true
        init(_ parent: LearningWebView) { self.parent = parent }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard active, let url = action.request.url, parent.routes.allowsNavigation(to: url) else {
                if active { parent.onError("学习页面跳转到了未允许的地址，请重新连接。") }
                return .cancel
            }
            if action.targetFrame == nil {
                webView.load(action.request)
                return .cancel
            }
            return .allow
        }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            guard active, let url = response.response.url, parent.routes.allowsNavigation(to: url) else {
                if active { parent.onError("学习服务返回了未允许的地址，请重新连接。") }
                return .cancel
            }
            if let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
                parent.onError((http.statusCode == 401 || http.statusCode == 403)
                    ? LearningServiceError.unauthorized.localizedDescription : "学习空间暂时不可用，请稍后重试。")
                return .cancel
            }
            return .allow
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if active { parent.onLoading(true) }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if active { parent.onLoading(false) }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if active { parent.onError("学习页面已暂停，点重新连接即可继续。") }
        }
        private func failed(_ error: Error) {
            guard active, (error as NSError).code != NSURLErrorCancelled else { return }
            parent.onError("连接暂时中断，请重新连接学习空间。")
        }
    }
}
