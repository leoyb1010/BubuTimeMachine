import Foundation
import Testing
#if !LEARNING_HELPER_TESTS
@testable import BubuTimeMachine
#endif

struct LearningAccessTests {
    @Test("网页身份只放请求头，日期和孩子通过正常查询参数传入")
    func initialRequestDoesNotLeakToken() throws {
        let routes = LearningServiceRoutes(baseURL: URL(string: "https://family.example/ai")!)
        let request = try routes.pageRequest(day: "2026-10-21", childID: "child 1", token: "private-token")
        #expect(request.url?.path == "/ai/learning")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer private-token")
        #expect(request.url?.absoluteString.contains("private-token") == false)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first(where: { $0.name == "child" })?.value == "child 1")
    }

    @Test("只允许同源学习路径，拒绝近似前缀、跨端口与路径穿越")
    func navigationStaysInLearningScope() {
        let routes = LearningServiceRoutes(baseURL: URL(string: "https://family.example")!)
        for url in ["https://family.example/learning", "https://family.example:443/learning/courses/one"] {
            #expect(routes.allowsNavigation(to: URL(string: url)!))
        }
        for url in ["https://other.example/learning", "http://family.example/learning",
                    "https://family.example:8000/learning", "https://family.example/learning-other",
                    "https://family.example/learning/../admin", "https://family.example/learning/%2e%2e/admin",
                    "https://family.example/learning/%252e%252e/admin", "javascript:alert(1)"] {
            #expect(!routes.allowsNavigation(to: URL(string: url)!))
        }
    }

    @Test("媒体路径不会把记录ID解释成路径或查询")
    func mediaRouteRejectsPathInjection() {
        let routes = LearningServiceRoutes(baseURL: URL(string: "https://family.example")!)
        for id in ["", "../other", "id/analysis", "id?token=x"] {
            #expect(throws: LearningServiceError.self) { try routes.analysisURL(mediaID: id) }
        }
    }

    @Test("草案响应的可选字段缺省兼容，缺状态不能冒充ready")
    func draftPayloadDefaults() throws {
        let dto = try JSONDecoder().decode(MediaAnalysisDTO.self, from: Data(#"{"media_id":"m1"}"#.utf8))
        #expect(dto.mediaID == "m1")
        #expect(dto.state == "unavailable")
        #expect(dto.segments.isEmpty && dto.tags.isEmpty && dto.warnings.isEmpty)
        #expect(dto.descriptionText.isEmpty && dto.ocr.isEmpty)
        #expect(dto.revision == nil)
    }

    @Test("解析缓存隔离服务、账号、媒体与原片hash，更新后不读旧版本")
    func cacheSeparatesOwnersAndSourceVersions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("analysis-cache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = MediaAnalysisCache(directory: directory)
        let key = MediaAnalysisCache.Key(service: "https://family.example", account: "account-a", mediaID: "m1", contentHash: "old")
        let old = try JSONDecoder().decode(MediaAnalysisDTO.self,
            from: Data(#"{"media_id":"m1","content_hash":"old","state":"ready","revision":1,"ocr":"原文"}"#.utf8))
        try await cache.save(old, for: key)
        #expect(await cache.load(for: key)?.analysis.ocr == "原文")
        for other in [
            MediaAnalysisCache.Key(service: "https://other.example", account: key.account, mediaID: "m1", contentHash: "old"),
            MediaAnalysisCache.Key(service: key.service, account: "account-b", mediaID: "m1", contentHash: "old"),
            MediaAnalysisCache.Key(service: key.service, account: key.account, mediaID: "m2", contentHash: "old"),
            MediaAnalysisCache.Key(service: key.service, account: key.account, mediaID: "m1", contentHash: "new")
        ] { #expect(await cache.load(for: other) == nil) }
        let newKey = MediaAnalysisCache.Key(service: key.service, account: key.account, mediaID: "m1", contentHash: "new")
        let updated = try JSONDecoder().decode(MediaAnalysisDTO.self,
            from: Data(#"{"media_id":"m1","content_hash":"new","state":"ready","revision":2}"#.utf8))
        try await cache.save(updated, for: newKey)
        #expect(await cache.load(for: key) == nil)
        #expect(await cache.load(for: newKey)?.analysis.revision == 2)
        await cache.remove(for: newKey)
        #expect(await cache.load(for: newKey) == nil)
    }
}
