import Testing
import Foundation
import UIKit
@testable import BubuTimeMachine

// MARK: - 2.27 详情页与图片加载：分档、缓存、占位、错误分类

@MainActor
struct Media2_27Tests {

    // MARK: Size buckets

    @Test func bucketLeansToTheNearerSmallerSize() {
        // 370pt event card at 3× = 1110px: 1024, not the whole 1600px source at 2048.
        #expect(LearningImageDecoder.bucket(forPixels: 1110) == 1024)
        #expect(LearningImageDecoder.bucket(forPixels: 1331) == 1024)
        #expect(LearningImageDecoder.bucket(forPixels: 1400) == 2048)
        #expect(LearningImageDecoder.bucket(forPixels: 600) == 512)
        // Grid thumbs (~120pt at 3×) still get 512, not a blurry 256.
        #expect(LearningImageDecoder.bucket(forPixels: 360) == 512)
        #expect(LearningImageDecoder.bucket(forPixels: 100) == 256)
        // Full-screen detail on any phone or iPad tops out at the largest bucket.
        #expect(LearningImageDecoder.bucket(forPixels: 2622) == 2048)
        #expect(LearningImageDecoder.bucket(forPixels: 9999) == 2048)
    }

    // MARK: Decoded memory + placeholder lookup

    private func image(_ side: Int) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in }
    }

    @Test func cachedNeedsTheRequestedSizeOrSharper() {
        let scope = "test-\(UUID().uuidString)"
        let small = image(8)
        LearningImageMemory.shared.store(small, for: LearningImagePipeline.key(scope: scope, path: "/learning/p", bucket: 512))
        #expect(LearningImagePipeline.cached(scope: scope, path: "/learning/p", atLeast: 256) === small)
        #expect(LearningImagePipeline.cached(scope: scope, path: "/learning/p", atLeast: 512) === small)
        #expect(LearningImagePipeline.cached(scope: scope, path: "/learning/p", atLeast: 1024) == nil)
        #expect(LearningImagePipeline.cached(scope: "other", path: "/learning/p", atLeast: 256) == nil)
    }

    @Test func placeholderIsTheSharpestCopyOfAnySize() {
        let scope = "test-\(UUID().uuidString)"
        let low = image(4), high = image(16)
        LearningImageMemory.shared.store(low, for: LearningImagePipeline.key(scope: scope, path: "/learning/thumb", bucket: 256))
        LearningImageMemory.shared.store(high, for: LearningImagePipeline.key(scope: scope, path: "/learning/thumb", bucket: 512))
        #expect(LearningImagePipeline.anyCached(scope: scope, path: "/learning/thumb") === high)
        #expect(LearningImagePipeline.anyCached(scope: scope, path: "/learning/large") == nil)
    }

    @Test func thumbnailToLargeKeepsZoomOnlyForTheSamePicture() {
        #expect(ZoomingImageScrollView.sameAspect(CGSize(width: 480, height: 360), CGSize(width: 1600, height: 1200)))
        #expect(ZoomingImageScrollView.sameAspect(CGSize(width: 480, height: 361), CGSize(width: 1600, height: 1200)))
        #expect(!ZoomingImageScrollView.sameAspect(CGSize(width: 480, height: 480), CGSize(width: 1600, height: 1200)))
        #expect(!ZoomingImageScrollView.sameAspect(.zero, CGSize(width: 1600, height: 1200)))
    }

    // MARK: Disk cache trimming

    @Test func pruneDropsLeastRecentlyUsedFirst() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bubu-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("scope"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let names = ["old", "mid", "new"]
        for (offset, name) in names.enumerated() {
            let file = folder.appendingPathComponent("scope/\(name).bin")
            try Data(count: 64 * 1024).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: Double(offset - 10) * 3600)],
                                                  ofItemAtPath: file.path)
        }
        // A hit on the oldest file makes it the newest.
        LearningMediaCache.touch(folder.appendingPathComponent("scope/old.bin"))
        let kept = LearningMediaCache.prune(folder, limit: 150 * 1024)
        #expect(kept <= 150 * 1024)
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("scope").path))
        #expect(left == ["old.bin", "new.bin"])
    }

    @Test func pruneUnderTheLimitKeepsEverything() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bubu-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(count: 1024).write(to: folder.appendingPathComponent("a.bin"))
        LearningMediaCache.prune(folder, limit: 1_048_576)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.bin").path))
    }

    // MARK: Error classes

    private func client() -> BubuLearningClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MediaStatusStub.self]
        let session = URLSession(configuration: configuration)
        return BubuLearningClient(baseURL: URL(string: "https://bubu.test")!, scope: "test", token: { "token" },
                                  session: session, mediaSession: session)
    }

    private nonisolated struct Empty: Decodable, Sendable {}

    private func failure(_ path: String) async -> Error? {
        do { _ = try await client().get(path, as: Empty.self); return nil } catch { return error }
    }

    @Test func forbiddenIsNoPermissionNotAnExpiredLogin() async throws {
        let error = try #require(await failure("api/s403"))
        #expect(LearningErrorKind(error) != .unauthorized)
        #expect(learningErrorText(error) == "当前账号没有核对和发布课程的权限")
        // Framework English never reaches the parent.
        let english = try #require(await failure("api/s403en"))
        #expect(learningErrorText(english) == LearningErrorKind.forbiddenText)
    }

    @Test func unauthorizedStillAsksToReconnect() async throws {
        let error = try #require(await failure("api/s401"))
        #expect(LearningErrorKind(error) == .unauthorized)
        #expect(learningErrorText(error) == LearningErrorKind.unauthorizedText)
        #expect(LearningErrorKind.unauthorizedText.contains("服务器与 AI 配置"))
    }

    @Test func tooManyRequestsKeepsTheServersExplanation() async throws {
        let error = try #require(await failure("api/s429"))
        #expect(learningErrorText(error) == "问得有点多啦，休息一下再来")
        let bare = try #require(await failure("api/s429bare"))
        #expect(learningErrorText(bare) == LearningErrorKind.tooFrequentText)
    }

    @Test func droppedConnectionMeansTheServerNotThePhone() {
        #expect(LearningErrorKind(URLError(.networkConnectionLost)) == .serverUnreachable)
        #expect(LearningErrorKind(URLError(.notConnectedToInternet)) == .offline)
    }

    @Test func askWaitsLongerThanTheModel() {
        #expect(BubuLearningClient.requestTimeout(for: "api/ask") > 60)
        #expect(BubuLearningClient.requestTimeout(for: "api/recognition/1") == 30)
    }

    @Test func serverDetailOnlyWhenItIsChinese() {
        #expect(BubuLearningClient.detail(Data(#"{"detail":"素材库暂时读不到"}"#.utf8)) == "素材库暂时读不到")
        #expect(BubuLearningClient.detail(Data(#"{"detail":"Not authenticated"}"#.utf8)) == nil)
        #expect(BubuLearningClient.detail(Data(#"{"detail":[{"msg":"field required"}]}"#.utf8)) == nil)
    }

    @Test func systemErrorsBecomeParentSentences() {
        #expect(bubuErrorText(CocoaError(.fileWriteOutOfSpace), fallback: "兜底") == "手机存储空间不够了，清理一些空间后再试。")
        #expect(bubuErrorText(CocoaError(.coderInvalidValue), fallback: "兜底") == "兜底")
        #expect(bubuErrorText(URLError(.notConnectedToInternet), fallback: "兜底") == LearningErrorKind.offlineText)
        #expect(bubuErrorText(NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "Something failed"]),
                              fallback: "兜底") == "兜底")
        #expect(bubuErrorText(BubuLearningClientError.conflict, fallback: "兜底") == "内容刚刚更新过，请刷新后重新核对。")
    }
}

/// Answers by path, so parallel tests never share state.
private nonisolated final class MediaStatusStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body): (Int, String) = switch request.url?.lastPathComponent ?? "" {
        case "s401": (401, #"{"detail":"Not authenticated"}"#)
        case "s403": (403, #"{"detail":"当前账号没有核对和发布课程的权限"}"#)
        case "s403en": (403, #"{"detail":"Not authenticated"}"#)
        case "s429": (429, #"{"detail":"问得有点多啦，休息一下再来"}"#)
        case "s429bare": (429, "")
        default: (500, "{}")
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
