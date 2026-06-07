import Foundation

// MARK: - Mock API 客户端
/// M0/M1 阶段使用：无需真实 PocketBase，本地闭环即可跑通完整体验。
/// 所有方法返回合理的假数据，模拟网络延迟与上传进度。
final class MockAPIClient: APIClient {

    func authenticate(role: String) async throws -> AuthToken {
        try? await Task.sleep(for: .milliseconds(200))
        return AuthToken(token: "mock-token-\(role)", role: role, expiresAt: nil)
    }

    func createEntry(_ dto: EntryDTO) async throws -> EntryDTO {
        try? await Task.sleep(for: .milliseconds(200))
        var result = dto
        result.id = "mock-\(dto.localId)"
        return result
    }

    func fetchEntries(since: Date?) async throws -> [EntryDTO] {
        try? await Task.sleep(for: .milliseconds(200))
        return []   // 本地优先：M1 阶段时光轴只读本地 SwiftData
    }

    func uploadMedia(_ file: MediaUploadRequest) -> AsyncThrowingStream<UploadEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // 模拟分片上传进度
                for step in 1...10 {
                    try? await Task.sleep(for: .milliseconds(120))
                    continuation.yield(.progress(Double(step) / 10.0))
                }
                continuation.yield(.completed(
                    remoteId: "mock-media-\(file.mediaId)",
                    url: "https://mock.local/files/\(file.fileName)"
                ))
                continuation.finish()
            }
        }
    }

    func subscribeRealtime() -> AsyncStream<RealtimeEvent> {
        AsyncStream { continuation in
            continuation.yield(.connected)
            // Mock 不主动推送变更
        }
    }

    func ping() async throws -> Bool {
        try? await Task.sleep(for: .milliseconds(150))
        return true
    }
}
