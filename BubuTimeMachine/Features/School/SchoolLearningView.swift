import SwiftUI

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
