import Foundation

// MARK: - API 客户端协议（PocketBaseClient 实现）
/// 接口先行：UI 与同步层只依赖此协议，先 Mock 后接真实 PocketBase。
protocol APIClient: Sendable {
    func authenticate(role: String) async throws -> AuthToken
    func createEntry(_ dto: EntryDTO) async throws -> EntryDTO
    func fetchEntries(since: Date?) async throws -> [EntryDTO]
    func fetchMedia(since: Date?) async throws -> [MediaDTO]
    func upsertMilestone(_ dto: MilestoneDTO) async throws -> MilestoneDTO
    func fetchMilestones(since: Date?) async throws -> [MilestoneDTO]
    func upsertFirstTime(_ dto: FirstTimeDTO) async throws -> FirstTimeDTO
    func fetchFirstTimes(since: Date?) async throws -> [FirstTimeDTO]
    func upsertFamilyMember(_ dto: FamilyMemberDTO) async throws -> FamilyMemberDTO
    func fetchFamilyMembers(since: Date?) async throws -> [FamilyMemberDTO]
    func upsertChildProfile(_ dto: ChildProfileDTO) async throws -> ChildProfileDTO
    func fetchChildProfiles(since: Date?) async throws -> [ChildProfileDTO]
    /// 布布头像上传（childprofile.avatar file 字段），身份卡跨设备同步。
    func uploadChildAvatar(profileLocalId: UUID, fileURL: URL, fileName: String) -> AsyncThrowingStream<UploadEvent, Error>
    func upsertHealthRecord(_ dto: HealthRecordDTO) async throws -> HealthRecordDTO
    func fetchHealthRecords(since: Date?) async throws -> [HealthRecordDTO]
    func upsertVaccineRecord(_ dto: VaccineRecordDTO) async throws -> VaccineRecordDTO
    func fetchVaccineRecords(since: Date?) async throws -> [VaccineRecordDTO]
    /// 取消打卡/误录删除：远端删掉，避免下轮拉取复活。
    func deleteVaccineRecord(remoteId: String) async throws
    func upsertGrowthMeasurement(_ dto: GrowthMeasurementDTO) async throws -> GrowthMeasurementDTO
    func fetchGrowthMeasurements(since: Date?) async throws -> [GrowthMeasurementDTO]
    func upsertComment(_ dto: CommentDTO) async throws -> CommentDTO
    func fetchComments(since: Date?) async throws -> [CommentDTO]
    func uploadCommentVoice(commentId: UUID, entryLocalId: UUID, fileURL: URL, fileName: String) -> AsyncThrowingStream<UploadEvent, Error>
    func upsertVoiceNote(_ dto: VoiceNoteDTO) async throws -> VoiceNoteDTO
    func fetchVoiceNotes(since: Date?) async throws -> [VoiceNoteDTO]
    func uploadVoiceNote(voiceId: UUID, entryLocalId: UUID, fileURL: URL, fileName: String) -> AsyncThrowingStream<UploadEvent, Error>
    func upsertVoiceMemo(_ dto: VoiceMemoDTO) async throws -> VoiceMemoDTO
    func fetchVoiceMemos(since: Date?) async throws -> [VoiceMemoDTO]
    func uploadVoiceMemo(memoId: UUID, fileURL: URL, fileName: String) -> AsyncThrowingStream<UploadEvent, Error>
    func upsertTimeCapsule(_ dto: TimeCapsuleDTO) async throws -> TimeCapsuleDTO
    func fetchTimeCapsules(since: Date?) async throws -> [TimeCapsuleDTO]
    func uploadTimeCapsuleBlob(capsuleId: UUID, dto: TimeCapsuleDTO, fileURL: URL, fileName: String) -> AsyncThrowingStream<UploadEvent, Error>
    func deleteTimeCapsule(remoteId: String) async throws
    func downloadFile(from remoteURL: String) async throws -> Data
    /// 分片上传：返回可观察进度的异步流。
    func uploadMedia(_ file: MediaUploadRequest) -> AsyncThrowingStream<UploadEvent, Error>
    func subscribeRealtime() -> AsyncStream<RealtimeEvent>
    /// 连接测试：设置页「连接测试」按钮调用。
    func ping() async throws -> Bool
}

// MARK: - 客户端错误
enum APIError: LocalizedError, Sendable {
    case notConfigured
    case unauthorized
    case network(String)
    case server(Int, String)
    case fileTooLarge(bytes: Int64, limit: Int64)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "还没有连接家里的服务器。"
        case .unauthorized:  return "账号状态需要重新确认，请到设置里重新连接服务器。"
        case .network: return "网络暂时不稳定，App 会保留本地内容并继续重试。"
        case .server(let code, _): return "服务器暂时没响应（\(code)），App 会继续自动补传。"
        case .fileTooLarge(let bytes, let limit):
            return "这个文件有 \(Self.megabytes(bytes))MB，公网建议压到 \(Self.megabytes(limit))MB 以内"
        }
    }

    private static func megabytes(_ bytes: Int64) -> Int64 {
        max(1, bytes / 1_048_576)
    }
}
