import Foundation
import WebKit
import Testing
#if !LEARNING_HELPER_TESTS
@testable import BubuTimeMachine
#endif

@MainActor
struct LearningWebsiteDataStoreTests {
    @Test("重开页面和升级仍定位同一个固定存储，不把服务查询参数当新账号")
    func stableIdentifier() {
        let account = "https://records.example\nmom@example.com"
        let expected = UUID(uuidString: "4E18609D-07D4-8D41-AC30-4380CF5DC72C")!
        for service in ["https://family.example/ai", "https://FAMILY.example:443/ai/",
                        "https://family.example/ai?token=synthetic#page"] {
            #expect(LearningWebsiteDataStore.identifier(serviceURL: URL(string: service)!, account: account) == expected)
        }
    }

    @Test("不同账号、PB账号作用域、服务路径、主机和端口分别隔离")
    func isolatedIdentifiers() {
        let scopes = [
            ("https://family.example/ai", "pb-a\nmom@example.com"),
            ("https://family.example/ai", "pb-a\ngrandma@example.com"),
            ("https://family.example/ai", "pb-b\nmom@example.com"),
            ("https://family.example/other", "pb-a\nmom@example.com"),
            ("https://other.example/ai", "pb-a\nmom@example.com"),
            ("https://family.example:8443/ai", "pb-a\nmom@example.com")
        ]
        let ids = scopes.map { LearningWebsiteDataStore.identifier(serviceURL: URL(string: $0.0)!, account: $0.1) }
        #expect(Set(ids).count == scopes.count)
    }

    @Test("课程WebView使用可恢复的命名持久库，不是临时库或全局default")
    func browserStoreIsPersistentAndScoped() async throws {
        let service = URL(string: "https://learning-test.invalid")!
        let account = "synthetic-store-test-" + UUID().uuidString
        let otherAccount = account + "-other"
        let id = LearningWebsiteDataStore.identifier(serviceURL: service, account: account)
        let otherID = LearningWebsiteDataStore.identifier(serviceURL: service, account: otherAccount)
        let first = autoreleasepool {
            let store = LearningWebsiteDataStore.make(serviceURL: service, account: account)
            return (persistent: store.isPersistent, id: store.identifier)
        }
        let reopened = autoreleasepool {
            let store = LearningWebsiteDataStore.make(serviceURL: service, account: account)
            return (persistent: store.isPersistent, id: store.identifier)
        }
        let other = autoreleasepool {
            LearningWebsiteDataStore.make(serviceURL: service, account: otherAccount).identifier
        }
        #expect(first.persistent && reopened.persistent)
        #expect(first.id == id && reopened.id == id)
        #expect(other == otherID && other != first.id)
        // Only synthetic, per-run namespaces are removed. Production account stores are never cleared on view dismissal.
        try? await WKWebsiteDataStore.remove(forIdentifier: id)
        try? await WKWebsiteDataStore.remove(forIdentifier: otherID)
    }
}
