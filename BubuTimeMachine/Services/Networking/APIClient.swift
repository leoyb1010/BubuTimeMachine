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
    /// 软删除任意 PocketBase collection 里的远端记录。SyncEngine 用它消费本地删除队列。
    func deleteRecord(collection: String, remoteId: String) async throws
    /// 取消打卡/误录删除：远端写 tombstone，避免下轮拉取复活。
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

    /// 拉取自 since 以来被删除记录的墓碑（localId + 服务器 updated），用于把删除传播到本设备，
    /// 并让删除也能推进增量游标。
    func fetchDeletedTombstones(collection: String, since: Date?) async throws -> [RemoteTombstone]

    /// 实时变更流（SSE 长连）：远端有任何写入就产出一个信号。不支持的后端返回 nil。
    func realtimeStream() -> AsyncStream<Void>?
    func uploadTimeCapsuleBlob(capsuleId: UUID, dto: TimeCapsuleDTO, fileURL: URL, fileName: String) -> AsyncThrowingStream<UploadEvent, Error>
    func deleteTimeCapsule(remoteId: String) async throws
    func downloadFile(from remoteURL: String) async throws -> Data
    /// 大文件下载优先落到系统临时文件，避免照片/视频/音频同步时一次性把完整文件读进内存。
    func downloadFileToTemporaryURL(from remoteURL: String) async throws -> URL
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
    /// 403：权限/访问规则错误（非 token 过期）。不触发重登，避免每待推项每轮重登撞限流。
    case forbidden
    case network(String)
    case server(Int, String)
    case fileTooLarge(bytes: Int64, limit: Int64)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "还没有连接家里的服务器。"
        case .unauthorized:  return "账号状态需要重新确认，请到设置里重新连接服务器。"
        case .forbidden: return "没有访问权限，App 会保留本地内容，稍后重试。"
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


// MARK: - 默认实现（Mock / 旧后端无需支持 tombstone）
extension APIClient {
    func fetchDeletedTombstones(collection: String, since: Date?) async throws -> [RemoteTombstone] { [] }
    func realtimeStream() -> AsyncStream<Void>? { nil }
}
