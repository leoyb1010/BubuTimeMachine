import Foundation
import Testing
@testable import BubuTimeMachine

struct ServerConfigTrustTests {
    @Test("构建内置 AI 主机可以与 PocketBase 分域且仍受固定白名单约束")
    func packagedAIHostIsTrusted() throws {
        let server = try #require(URL(string: "https://bubu-api.leoyuan.top"))
        let packagedAI = try #require(URL(string: "https://bubu-ai.leoyuan.top"))

        #expect(ServerConfig.isTrustedAIURL(
            packagedAI,
            serverURL: server,
            packagedAIURL: packagedAI,
            allowLoopback: false
        ))
        #expect(!ServerConfig.isTrustedAIURL(
            try #require(URL(string: "https://example.com")),
            serverURL: server,
            packagedAIURL: packagedAI,
            allowLoopback: false
        ))
    }
}
