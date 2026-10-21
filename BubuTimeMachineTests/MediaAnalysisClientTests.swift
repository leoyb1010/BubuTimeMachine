import Foundation
import Testing
#if !LEARNING_HELPER_TESTS
@testable import BubuTimeMachine
#endif

@Suite(.serialized)
struct MediaAnalysisClientTests {
    private func client(responses: [(Int, String)]) -> MediaAnalysisClient {
        AnalysisHTTPStub.state.reset(responses)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalysisHTTPStub.self]
        return MediaAnalysisClient(baseURL: URL(string: "https://family.example")!,
                                   session: URLSession(configuration: configuration))
    }

    @Test("读取解析带Bearer但不泄漏到URL，真实解码时间段和revision")
    func authenticatedRead() async throws {
        let service = client(responses: [(200, #"{"media_id":"m1","state":"ready","revision":4,"content_hash":"abc","provider":"second-brain","segments":[{"id":"one","start":13.3,"end":14.1,"text":"Corn."}]}"#)])
        let result = try await service.fetch(mediaID: "m1", token: "test-token")
        #expect(result.revision == 4)
        #expect(result.segments.first?.start == 13.3)
        let request = try #require(AnalysisHTTPStub.state.requests.first)
        #expect(request.url?.path == "/learning/api/media/m1/analysis")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(!request.httpShouldHandleCookies)
        #expect(request.url?.query == nil)
    }

    @Test("拒绝身份失败响应，不把失败当成空解析")
    func authorizationFailureIsExplicit() async {
        let service = client(responses: [(403, #"{"detail":"forbidden"}"#)])
        do {
            _ = try await service.fetch(mediaID: "m1", token: "expired")
            Issue.record("403 must not become an empty successful analysis")
        } catch {
            #expect((error as? LearningServiceError) == .unauthorized)
        }
    }

    @Test("请求的素材与响应不一致时拒绝展示")
    func wrongMediaIsRejected() async {
        let service = client(responses: [(200, #"{"media_id":"other","state":"ready"}"#)])
        do {
            _ = try await service.fetch(mediaID: "m1", token: "test-token")
            Issue.record("Wrong-media response must fail")
        } catch { #expect((error as? LearningServiceError) == .invalidResponse) }
    }

    @Test("重试是一次明确POST，不偷偷循环轮询")
    func retryUsesExplicitMutation() async throws {
        let service = client(responses: [(200, #"{"state":"queued"}"#)])
        let result = try await service.retry(mediaID: "m1", token: "test-token")
        #expect(result.mediaID == "m1" && result.state == "queued")
        let requests = AnalysisHTTPStub.state.requests
        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "POST")
        #expect(requests.first?.url?.path == "/learning/api/media/m1/analysis/retry")
        #expect(requests.first?.value(forHTTPHeaderField: "X-Bubu-Learning") == "1")
        #expect(requests.first?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }
}

private nonisolated final class AnalysisHTTPStub: URLProtocol, @unchecked Sendable {
    static let state = State()
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [(Int, String)] = []
        private var seen: [URLRequest] = []
        func reset(_ values: [(Int, String)]) {
            lock.lock(); defer { lock.unlock() }
            self.values = values; seen = []
        }
        func next(_ request: URLRequest) -> (Int, String) {
            lock.lock(); defer { lock.unlock() }
            seen.append(request)
            return values.isEmpty ? (500, "{}") : values.removeFirst()
        }
        var requests: [URLRequest] {
            lock.lock(); defer { lock.unlock() }
            return seen
        }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.state.next(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
