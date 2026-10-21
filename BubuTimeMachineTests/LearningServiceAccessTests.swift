import Foundation
import Testing
#if !LEARNING_HELPER_TESTS
@testable import BubuTimeMachine
#endif

struct LearningServiceAccessTests {
    private func access(aiEnabled: Bool = false, configured: Bool = true,
                        trustedURL: URL? = URL(string: "https://family.example/ai"),
                        requiresAIEnabled: Bool = true) -> LearningServiceAccess? {
        LearningServiceAccess(trustedServiceURL: trustedURL,
            serverURL: URL(string: "https://family.example"), accountEmail: "parent@example.com",
            revision: 3, serverConfigured: configured, aiEnabled: aiEnabled,
            requiresAIEnabled: requiresAIEnabled)
    }

    @Test("关闭故事写作仍可读取已连接家庭课程，默认分析权限不变")
    func learningDoesNotRequireStoryConsent() {
        #expect(access(requiresAIEnabled: false) != nil)
        #expect(access() == nil)
        #expect(access(aiEnabled: true) != nil)
    }

    @Test("课程仍要求家庭登录和可信服务地址")
    func learningPreservesConnectionAndTrustRequirements() {
        #expect(access(configured: false, requiresAIEnabled: false) == nil)
        #expect(access(trustedURL: nil, requiresAIEnabled: false) == nil)
    }

    @Test("课程与分析共享账号隔离身份，权限选择不改变存储命名空间")
    func consentPolicyDoesNotChangeAccountIdentity() {
        #expect(access(aiEnabled: true) == access(aiEnabled: true, requiresAIEnabled: false))
    }
}
