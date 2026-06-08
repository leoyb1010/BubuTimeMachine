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

    func fetchMedia(since: Date?) async throws -> [MediaDTO] { [] }
    func upsertMilestone(_ dto: MilestoneDTO) async throws -> MilestoneDTO { var r = dto; r.id = "mock-\(dto.localId)"; return r }
    func fetchMilestones(since: Date?) async throws -> [MilestoneDTO] { [] }
    func upsertFirstTime(_ dto: FirstTimeDTO) async throws -> FirstTimeDTO { var r = dto; r.id = "mock-\(dto.localId)"; return r }
    func fetchFirstTimes(since: Date?) async throws -> [FirstTimeDTO] { [] }
    func upsertFamilyMember(_ dto: FamilyMemberDTO) async throws -> FamilyMemberDTO { var r = dto; r.id = "mock-\(dto.localId)"; return r }
    func fetchFamilyMembers(since: Date?) async throws -> [FamilyMemberDTO] { [] }
    func upsertChildProfile(_ dto: ChildProfileDTO) async throws -> ChildProfileDTO { var r = dto; r.id = "mock-\(dto.localId)"; return r }
    func fetchChildProfiles(since: Date?) async throws -> [ChildProfileDTO] { [] }
    func upsertHealthRecord(_ dto: HealthRecordDTO) async throws -> HealthRecordDTO { var r = dto; r.id = "mock-\(dto.localId)"; return r }
    func fetchHealthRecords(since: Date?) async throws -> [HealthRecordDTO] { [] }
    func upsertComment(_ dto: CommentDTO) async throws -> CommentDTO { var r = dto; r.id = "mock-\(dto.localId)"; return r }
    func fetchComments(since: Date?) async throws -> [CommentDTO] { [] }
    func uploadCommentVoice(commentId: UUID, entryLocalId: UUID, fileURL: URL, fileName: String) -> AsyncThrowingStream<UploadEvent, Error> { mockUpload(id: commentId, fileName: fileName) }
    func upsertVoiceNote(_ dto: VoiceNoteDTO) async throws -> VoiceNoteDTO { var r = dto; r.id = "mock-\(dto.localId)"; return r }
    func fetchVoiceNotes(since: Date?) async throws -> [VoiceNoteDTO] { [] }
    func uploadVoiceNote(voiceId: UUID, entryLocalId: UUID, fileURL: URL, fileName: String) -> AsyncThrowingStream<UploadEvent, Error> { mockUpload(id: voiceId, fileName: fileName) }
    func upsertVoiceMemo(_ dto: VoiceMemoDTO) async throws -> VoiceMemoDTO { var r = dto; r.id = "mock-\(dto.localId)"; return r }
    func fetchVoiceMemos(since: Date?) async throws -> [VoiceMemoDTO] { [] }
    func uploadVoiceMemo(memoId: UUID, fileURL: URL, fileName: String) -> AsyncThrowingStream<UploadEvent, Error> { mockUpload(id: memoId, fileName: fileName) }

    private func mockUpload(id: UUID, fileName: String) -> AsyncThrowingStream<UploadEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.progress(1))
                continuation.yield(.completed(remoteId: "mock-file-\(id)", url: "https://mock.local/files/\(fileName)"))
                continuation.finish()
            }
        }
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
