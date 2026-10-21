import Foundation
import Testing
#if !TIMELINE_HELPER_TESTS
@testable import BubuTimeMachine
#endif

@Suite(.serialized)
struct TimelineAnalysisSearchTests {
    @Test("空搜索和语音筛选不发送为全库图片请求")
    func ineligibleRequestsStayLocal() {
        let base = URL(string: "https://family.example")!
        #expect(throws: LearningServiceError.self) {
            try TimelineAnalysisSearchClient.makeRequest(baseURL: base, query: "  ", filters: .init(), sort: .capture, token: "token")
        }
        #expect(throws: LearningServiceError.self) {
            try TimelineAnalysisSearchClient.makeRequest(baseURL: base, query: "小熊", filters: .init(kind: .audio), sort: .capture, token: "token")
        }
    }

    @Test("缺items的坏响应不是成功的无结果")
    func malformedResponseIsNotEmpty() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TimelineAnalysisSearchResponse.self, from: Data("{}".utf8))
        }
    }

    @Test("服务失败与确实无结果通过真实URLSession路径区分")
    func networkFailureIsNotAnEmptySearch() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TimelineHTTPStub.self]
        let client = TimelineAnalysisSearchClient(baseURL: URL(string: "https://family.example")!,
                                                  session: URLSession(configuration: configuration))
        TimelineHTTPStub.state.set(status: 503)
        do {
            _ = try await client.search(query: "踢球", filters: .init(), sort: .capture, token: "token")
            Issue.record("服务失败不能转换为空列表")
        } catch { #expect(error as? LearningServiceError == .server(503)) }
        TimelineHTTPStub.state.set(status: 200)
        let response = try await client.search(query: "踢球", filters: .init(), sort: .capture, token: "token")
        #expect(response.items.isEmpty && response.total == 0)
    }
    @Test("解析搜索传递拍摄范围、类型与方向，Bearer不进入URL")
    func requestCarriesFilters() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let filters = TimelineFilters(kind: .video, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400))
        let request = try TimelineAnalysisSearchClient.makeRequest(baseURL: URL(string: "https://family.example")!,
            query: "玉米 & 南瓜", filters: filters, sort: .oldest, token: "private", calendar: calendar)
        let parts = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        let fields = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(parts.path == "/learning/api/timeline/search")
        #expect(fields["query"] == "玉米 & 南瓜")
        #expect(fields["kind"] == "video" && fields["order"] == "asc")
        #expect(fields["start"] == "1970-01-01" && fields["end"] == "1970-01-02")
        #expect(fields["limit"] == "50")
        #expect(!request.url!.absoluteString.contains("private"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer private")
        #expect(!request.httpShouldHandleCookies)
    }

    @Test("只接纳确认的人物归属，未同步与无命中是不同结果")
    func confirmedMappingSeparatesUnsynced() throws {
        let local = UUID(), missing = UUID(), pending = UUID()
        let payload = """
        {"items":[
          {"entry_local_id":"\(local)","media_id":"one","identity_status":"confirmed","source":"second-brain"},
          {"entry_local_id":"\(missing)","media_id":"two","identity_status":"confirmed","source":"second-brain"},
          {"entry_local_id":"\(pending)","media_id":"three","identity_status":"pending","source":"second-brain"}
        ],"total":3,"has_more":true}
        """
        let response = try JSONDecoder().decode(TimelineAnalysisSearchResponse.self, from: Data(payload.utf8))
        #expect(response.confirmedHits.count == 2)
        #expect(response.missingEntryCount(availableIDs: [local]) == 1)
        #expect(response.hasMore)
        let empty = try JSONDecoder().decode(TimelineAnalysisSearchResponse.self, from: Data(#"{"items":[],"total":0}"#.utf8))
        #expect(empty.confirmedHits.isEmpty && empty.missingEntryCount(availableIDs: []) == 0)
        #expect(!empty.hasMore)
    }
}

private nonisolated final class TimelineHTTPStub: URLProtocol, @unchecked Sendable {
    static let state = State()
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var code = 200
        func set(status: Int) { lock.lock(); defer { lock.unlock() }; code = status }
        var status: Int { lock.lock(); defer { lock.unlock() }; return code }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.state.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"items":[],"total":0,"has_more":false}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
