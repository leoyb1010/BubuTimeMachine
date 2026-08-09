import CryptoKit
import Foundation
import SQLite3

// MARK: - 智能收件箱持久状态

nonisolated enum PhotoIntakeState: String, Sendable {
    case discovered
    case queued
    case accepted
    case ignored
    case failed
    case deleted
}

nonisolated enum PhotoIntakeMediaKind: Int, Sendable {
    case photo = 1
    case video = 2
}

/// PhotoKit 资产的轻量镜像，只保存摄取所需元数据，不复制照片字节。
nonisolated struct PhotoIntakeCandidate: Sendable, Equatable {
    let localIdentifier: String
    let creationDate: Date
    let mediaKind: PhotoIntakeMediaKind
    let latitude: Double?
    let longitude: Double?
    let width: Int
    let height: Int
    let duration: Double
    let burstIdentifier: String?
    let isLivePhoto: Bool
}

nonisolated struct PhotoIdentitySample: Sendable, Equatable {
    let label: Int
    let featureData: Data
}

nonisolated enum PhotoUploadJobState: String, Sendable {
    case queued
    case registered
    case retrying
    case succeeded
    case failed
    case acknowledged
}

nonisolated struct PhotoUploadJob: Sendable, Equatable {
    let assetKey: String
    let batchID: String
    let assetLocalIdentifier: String
    let resourceType: Int
    let resourceFilename: String
    let destinationURL: String
    let uploadToken: String
    let mimeType: String
    let state: PhotoUploadJobState
    let retryCount: Int
}

nonisolated struct PhotoUploadQueueSummary: Sendable, Equatable {
    let pendingBatches: Int
    let failedBatches: Int
}

/// App 与未来 PhotoKit 后台扩展共享的独立摄取库。
/// 候选是可重建派生状态，绝不为它修改 SwiftData 事实 schema。
nonisolated struct PhotoIntakeStore: Sendable {
    enum StoreError: Error, LocalizedError {
        case open(String)
        case sqlite(String)

        var errorDescription: String? {
            switch self {
            case .open(let message): "无法打开照片摄取库：\(message)"
            case .sqlite(let message): "照片摄取库操作失败：\(message)"
            }
        }
    }

    let databaseURL: URL
    private let excludeFromBackup: Bool

    init(
        databaseURL: URL = BubuStorage.intakeDatabaseURL,
        excludeFromBackup: Bool = false
    ) {
        self.databaseURL = databaseURL
        self.excludeFromBackup = excludeFromBackup
    }

    func upsertDiscovered(_ candidates: [PhotoIntakeCandidate]) throws {
        guard !candidates.isEmpty else { return }
        try withDatabase { db in
            try execute("BEGIN IMMEDIATE", db: db)
            do {
                let sql = """
                INSERT INTO intake_assets(
                    local_identifier, state, created_at, media_type, latitude, longitude,
                    width, height, duration, burst_identifier, is_live_photo, last_seen_at, updated_at
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(local_identifier) DO UPDATE SET
                    created_at = excluded.created_at,
                    media_type = excluded.media_type,
                    latitude = excluded.latitude,
                    longitude = excluded.longitude,
                    width = excluded.width,
                    height = excluded.height,
                    duration = excluded.duration,
                    burst_identifier = excluded.burst_identifier,
                    is_live_photo = excluded.is_live_photo,
                    last_seen_at = excluded.last_seen_at,
                    updated_at = excluded.updated_at
                """
                let statement = try prepare(sql, db: db)
                defer { sqlite3_finalize(statement) }
                let now = Date().timeIntervalSince1970

                for item in candidates {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bind(item.localIdentifier, at: 1, to: statement)
                    bind(PhotoIntakeState.discovered.rawValue, at: 2, to: statement)
                    sqlite3_bind_double(statement, 3, item.creationDate.timeIntervalSince1970)
                    sqlite3_bind_int(statement, 4, Int32(item.mediaKind.rawValue))
                    bind(item.latitude, at: 5, to: statement)
                    bind(item.longitude, at: 6, to: statement)
                    sqlite3_bind_int64(statement, 7, Int64(item.width))
                    sqlite3_bind_int64(statement, 8, Int64(item.height))
                    sqlite3_bind_double(statement, 9, item.duration)
                    bind(item.burstIdentifier, at: 10, to: statement)
                    sqlite3_bind_int(statement, 11, item.isLivePhoto ? 1 : 0)
                    sqlite3_bind_double(statement, 12, now)
                    sqlite3_bind_double(statement, 13, now)
                    try stepDone(statement, db: db)
                }
                try execute("COMMIT", db: db)
            } catch {
                try? execute("ROLLBACK", db: db)
                throw error
            }
        }
    }

    func mark(_ identifiers: [String], state: PhotoIntakeState) throws {
        guard !identifiers.isEmpty else { return }
        try withDatabase { db in
            try execute("BEGIN IMMEDIATE", db: db)
            do {
                let sql = """
                INSERT INTO intake_assets(local_identifier, state, created_at, media_type,
                                          width, height, duration, is_live_photo,
                                          last_seen_at, updated_at)
                VALUES(?, ?, 0, 1, 0, 0, 0, 0, ?, ?)
                ON CONFLICT(local_identifier) DO UPDATE SET
                    state = excluded.state,
                    updated_at = excluded.updated_at
                """
                let statement = try prepare(sql, db: db)
                defer { sqlite3_finalize(statement) }
                let now = Date().timeIntervalSince1970
                for identifier in identifiers {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bind(identifier, at: 1, to: statement)
                    bind(state.rawValue, at: 2, to: statement)
                    sqlite3_bind_double(statement, 3, now)
                    sqlite3_bind_double(statement, 4, now)
                    try stepDone(statement, db: db)
                }
                try execute("COMMIT", db: db)
            } catch {
                try? execute("ROLLBACK", db: db)
                throw error
            }
        }
    }

    func pendingIdentifiers() throws -> [String] {
        try withDatabase { db in
            let statement = try prepare(
                """
                SELECT local_identifier FROM intake_assets
                WHERE state IN ('discovered', 'failed')
                ORDER BY created_at DESC
                """, db: db)
            defer { sqlite3_finalize(statement) }
            var result: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) {
                    result.append(String(cString: text))
                }
            }
            return result
        }
    }

    func states(for identifiers: [String]) throws -> [String: PhotoIntakeState] {
        guard !identifiers.isEmpty else { return [:] }
        let wanted = Set(identifiers)
        return try withDatabase { db in
            let statement = try prepare(
                "SELECT local_identifier, state FROM intake_assets", db: db)
            defer { sqlite3_finalize(statement) }
            var result: [String: PhotoIntakeState] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idText = sqlite3_column_text(statement, 0),
                      let stateText = sqlite3_column_text(statement, 1) else { continue }
                let identifier = String(cString: idText)
                guard wanted.contains(identifier),
                      let state = PhotoIntakeState(rawValue: String(cString: stateText)) else { continue }
                result[identifier] = state
            }
            return result
        }
    }

    func data(forMetadataKey key: String) throws -> Data? {
        try withDatabase { db in
            let statement = try prepare(
                "SELECT value FROM intake_metadata WHERE key = ? LIMIT 1", db: db)
            defer { sqlite3_finalize(statement) }
            bind(key, at: 1, to: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else { return Data() }
            return Data(bytes: bytes, count: count)
        }
    }

    func setData(_ data: Data?, forMetadataKey key: String) throws {
        try withDatabase { db in
            if let data {
                let statement = try prepare(
                    """
                    INSERT INTO intake_metadata(key, value) VALUES(?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """, db: db)
                defer { sqlite3_finalize(statement) }
                bind(key, at: 1, to: statement)
                _ = data.withUnsafeBytes { raw in
                    sqlite3_bind_blob(statement, 2, raw.baseAddress, Int32(raw.count), Self.transient)
                }
                try stepDone(statement, db: db)
            } else {
                let statement = try prepare(
                    "DELETE FROM intake_metadata WHERE key = ?", db: db)
                defer { sqlite3_finalize(statement) }
                bind(key, at: 1, to: statement)
                try stepDone(statement, db: db)
            }
        }
    }

    // MARK: - 可靠后台上传批次（主 App 与 Photos extension 共用）

    func saveUploadBatch(
        batchID: String,
        entryLocalID: String,
        assetIdentifiers: [String],
        jobs: [PhotoUploadJob]
    ) throws {
        guard !batchID.isEmpty, !jobs.isEmpty else { return }
        let assetData = try JSONEncoder().encode(assetIdentifiers.sorted())
        let assetJSON = String(data: assetData, encoding: .utf8) ?? "[]"
        try withDatabase { db in
            try execute("BEGIN IMMEDIATE", db: db)
            do {
                let now = Date().timeIntervalSince1970
                let batch = try prepare(
                    """
                    INSERT INTO upload_batches(batch_id, entry_local_id, asset_identifiers_json,
                                               state, created_at, updated_at)
                    VALUES(?, ?, ?, 'queued', ?, ?)
                    ON CONFLICT(batch_id) DO UPDATE SET updated_at=excluded.updated_at
                    """, db: db)
                defer { sqlite3_finalize(batch) }
                bind(batchID, at: 1, to: batch)
                bind(entryLocalID, at: 2, to: batch)
                bind(assetJSON, at: 3, to: batch)
                sqlite3_bind_double(batch, 4, now)
                sqlite3_bind_double(batch, 5, now)
                try stepDone(batch, db: db)

                let statement = try prepare(
                    """
                    INSERT INTO upload_jobs(
                        asset_key,batch_id,asset_local_identifier,resource_type,resource_filename,
                        destination_url,upload_token,mime_type,state,retry_count,updated_at
                    ) VALUES(?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(asset_key) DO UPDATE SET
                        batch_id=excluded.batch_id,
                        asset_local_identifier=excluded.asset_local_identifier,
                        resource_type=excluded.resource_type,
                        resource_filename=excluded.resource_filename,
                        destination_url=excluded.destination_url,
                        upload_token=excluded.upload_token,
                        mime_type=excluded.mime_type,
                        state=excluded.state,
                        retry_count=excluded.retry_count,
                        updated_at=excluded.updated_at
                    """, db: db)
                defer { sqlite3_finalize(statement) }
                for job in jobs {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bind(job.assetKey, at: 1, to: statement)
                    bind(job.batchID, at: 2, to: statement)
                    bind(job.assetLocalIdentifier, at: 3, to: statement)
                    sqlite3_bind_int64(statement, 4, Int64(job.resourceType))
                    bind(job.resourceFilename, at: 5, to: statement)
                    bind(job.destinationURL, at: 6, to: statement)
                    bind(job.uploadToken, at: 7, to: statement)
                    bind(job.mimeType, at: 8, to: statement)
                    bind(job.state.rawValue, at: 9, to: statement)
                    sqlite3_bind_int64(statement, 10, Int64(job.retryCount))
                    sqlite3_bind_double(statement, 11, now)
                    try stepDone(statement, db: db)
                }
                let queuedAssets = try prepare(
                    "UPDATE intake_assets SET state='queued',updated_at=? WHERE local_identifier=?",
                    db: db)
                defer { sqlite3_finalize(queuedAssets) }
                for identifier in assetIdentifiers {
                    sqlite3_reset(queuedAssets)
                    sqlite3_clear_bindings(queuedAssets)
                    sqlite3_bind_double(queuedAssets, 1, now)
                    bind(identifier, at: 2, to: queuedAssets)
                    try stepDone(queuedAssets, db: db)
                }
                try execute("COMMIT", db: db)
            } catch {
                try? execute("ROLLBACK", db: db)
                throw error
            }
        }
    }

    func uploadJobs(states: Set<PhotoUploadJobState>, limit: Int = 500) throws -> [PhotoUploadJob] {
        guard !states.isEmpty else { return [] }
        return try withDatabase { db in
            let statement = try prepare(
                """
                SELECT asset_key,batch_id,asset_local_identifier,resource_type,resource_filename,
                       destination_url,upload_token,mime_type,state,retry_count
                FROM upload_jobs ORDER BY updated_at ASC
                """, db: db)
            defer { sqlite3_finalize(statement) }
            var result: [PhotoUploadJob] = []
            while result.count < max(1, limit), sqlite3_step(statement) == SQLITE_ROW {
                guard let stateText = sqlite3_column_text(statement, 8),
                      let state = PhotoUploadJobState(rawValue: String(cString: stateText)),
                      states.contains(state) else { continue }
                func text(_ index: Int32) -> String {
                    sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
                }
                result.append(PhotoUploadJob(
                    assetKey: text(0), batchID: text(1), assetLocalIdentifier: text(2),
                    resourceType: Int(sqlite3_column_int64(statement, 3)),
                    resourceFilename: text(4), destinationURL: text(5), uploadToken: text(6),
                    mimeType: text(7), state: state,
                    retryCount: Int(sqlite3_column_int64(statement, 9))))
            }
            return result
        }
    }

    func updateUploadJob(
        batchID: String,
        assetKey: String,
        state: PhotoUploadJobState,
        retryCount: Int? = nil
    ) throws {
        try withDatabase { db in
            let statement = try prepare(
                """
                UPDATE upload_jobs SET state=?, retry_count=COALESCE(?,retry_count), updated_at=?
                WHERE batch_id=? AND asset_key=?
                """, db: db)
            defer { sqlite3_finalize(statement) }
            bind(state.rawValue, at: 1, to: statement)
            if let retryCount { sqlite3_bind_int64(statement, 2, Int64(retryCount)) }
            else { sqlite3_bind_null(statement, 2) }
            sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
            bind(batchID, at: 4, to: statement)
            bind(assetKey, at: 5, to: statement)
            try stepDone(statement, db: db)
        }
    }

    func markUploadBatch(_ batchID: String, state: String) throws {
        try withDatabase { db in
            let statement = try prepare(
                "UPDATE upload_batches SET state=?,updated_at=? WHERE batch_id=?", db: db)
            defer { sqlite3_finalize(statement) }
            bind(state, at: 1, to: statement)
            sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
            bind(batchID, at: 3, to: statement)
            try stepDone(statement, db: db)
        }
    }

    func discardUploadBatch(_ batchID: String, restoreCandidates: Bool) throws {
        try withDatabase { db in
            try execute("BEGIN IMMEDIATE", db: db)
            do {
                var identifiers: [String] = []
                let read = try prepare(
                    "SELECT asset_identifiers_json FROM upload_batches WHERE batch_id=?", db: db)
                defer { sqlite3_finalize(read) }
                bind(batchID, at: 1, to: read)
                if sqlite3_step(read) == SQLITE_ROW,
                   let text = sqlite3_column_text(read, 0),
                   let data = String(cString: text).data(using: .utf8) {
                    identifiers = (try? JSONDecoder().decode([String].self, from: data)) ?? []
                }
                let delete = try prepare("DELETE FROM upload_batches WHERE batch_id=?", db: db)
                defer { sqlite3_finalize(delete) }
                bind(batchID, at: 1, to: delete)
                try stepDone(delete, db: db)
                // job 行必须跟着批次一起删：uploadQueueSummary 按 upload_jobs 计数，
                // 孤儿 job 会让「正在回家/停住了」卡片在批次已取回后永远挂着。
                let deleteJobs = try prepare("DELETE FROM upload_jobs WHERE batch_id=?", db: db)
                defer { sqlite3_finalize(deleteJobs) }
                bind(batchID, at: 1, to: deleteJobs)
                try stepDone(deleteJobs, db: db)
                if restoreCandidates {
                    let restore = try prepare(
                        "UPDATE intake_assets SET state='discovered',updated_at=? WHERE local_identifier=? AND state='queued'",
                        db: db)
                    defer { sqlite3_finalize(restore) }
                    for identifier in identifiers {
                        sqlite3_reset(restore)
                        sqlite3_clear_bindings(restore)
                        sqlite3_bind_double(restore, 1, Date().timeIntervalSince1970)
                        bind(identifier, at: 2, to: restore)
                        try stepDone(restore, db: db)
                    }
                }
                try execute("COMMIT", db: db)
            } catch {
                try? execute("ROLLBACK", db: db)
                throw error
            }
        }
    }

    func uploadQueueSummary() throws -> PhotoUploadQueueSummary {
        try withDatabase { db in
            func count(_ states: [String]) throws -> Int {
                let placeholders = states.map { _ in "?" }.joined(separator: ",")
                // JOIN 批次表：批次行已删（取回/重新整理）的孤儿 job 不参与计数——
                // 修复取回后卡片不消失，也让旧版本遗留的孤儿立即失效。
                let statement = try prepare(
                    """
                    SELECT COUNT(DISTINCT j.batch_id) FROM upload_jobs j
                    JOIN upload_batches b ON b.batch_id = j.batch_id
                    WHERE j.state IN (\(placeholders))
                    """,
                    db: db)
                defer { sqlite3_finalize(statement) }
                for (index, state) in states.enumerated() {
                    bind(state, at: Int32(index + 1), to: statement)
                }
                guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
                return Int(sqlite3_column_int64(statement, 0))
            }
            return PhotoUploadQueueSummary(
                pendingBatches: try count(["queued", "registered", "retrying"]),
                failedBatches: try count(["failed"]))
        }
    }

    func resetFailedUploadBatches() throws {
        let batchIDs: [String] = try withDatabase { db in
            let statement = try prepare(
                "SELECT DISTINCT batch_id FROM upload_jobs WHERE state='failed'", db: db)
            defer { sqlite3_finalize(statement) }
            var result: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW,
                  let text = sqlite3_column_text(statement, 0) {
                result.append(String(cString: text))
            }
            return result
        }
        for batchID in batchIDs {
            try discardUploadBatch(batchID, restoreCandidates: true)
        }
    }

    func activeUploadBatchIDs() throws -> [String] {
        try withDatabase { db in
            let statement = try prepare(
                "SELECT batch_id FROM upload_batches WHERE state NOT IN ('committed','failed')",
                db: db)
            defer { sqlite3_finalize(statement) }
            var result: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW,
                  let text = sqlite3_column_text(statement, 0) {
                result.append(String(cString: text))
            }
            return result
        }
    }

    /// 该批次是否有任何一个 job 曾上传成功（succeeded/acknowledged）。
    /// 404 对账用：有成功记录的批次大概率服务端已 commit 后被清理周期删行，
    /// 此时还原候选箱会造成二次发布。
    func uploadBatchHasSucceededJobs(_ batchID: String) throws -> Bool {
        try withDatabase { db in
            let stmt = try prepare(
                "SELECT COUNT(*) FROM upload_jobs WHERE batch_id=? AND state IN ('succeeded','acknowledged')",
                db: db)
            defer { sqlite3_finalize(stmt) }
            bind(batchID, at: 1, to: stmt)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
            return sqlite3_column_int64(stmt, 0) > 0
        }
    }

    /// 用户主动取回卡住的上传批次：只取回一张都没传成功的批次
    /// （有 succeeded job 的批次可能服务端已 commit，取回会造成重复 Entry——
    /// 那些留给 reconcile 按服务器状态收口）。返回取回的批次数。
    func recallStalledUploadBatches() throws -> Int {
        var recalled = 0
        for batchID in try activeUploadBatchIDs() {
            guard try !uploadBatchHasSucceededJobs(batchID) else { continue }
            try discardUploadBatch(batchID, restoreCandidates: true)
            recalled += 1
        }
        return recalled
    }

    func finishUploadBatchFromServer(_ batchID: String) throws {
        let jobs = try uploadJobs(states: [.queued, .registered, .retrying, .failed])
            .filter { $0.batchID == batchID }
        for job in jobs {
            try updateUploadJob(batchID: batchID, assetKey: job.assetKey, state: .succeeded)
        }
        try reconcileUploadBatch(batchID)
    }

    /// 上传端点只有在 PocketBase 原子提交成功后才返回 2xx，所以 PhotoKit 的
    /// succeeded 可以安全收口为 accepted；失败则让候选重新出现在首页。
    func reconcileUploadBatch(_ batchID: String) throws {
        try withDatabase { db in
            try execute("BEGIN IMMEDIATE", db: db)
            do {
                // 【防重复 Entry】已 committed 的批次绝不允许被迟到的 job 结果降级：
                // 扩展在"Photos job 已提交、registered 未落库"间被杀会产生重复 job，
                // 第一个 job 成功让服务端 commit 后，迟到副本撞 409 判 failed——
                // 若在这里把批次拉回 failed，资产会回候选箱、用户再确认就是第二个 Entry。
                let stateStmt = try prepare(
                    "SELECT state FROM upload_batches WHERE batch_id=?", db: db)
                defer { sqlite3_finalize(stateStmt) }
                bind(batchID, at: 1, to: stateStmt)
                if sqlite3_step(stateStmt) == SQLITE_ROW,
                   let cState = sqlite3_column_text(stateStmt, 0),
                   String(cString: cState) == "committed" {
                    // 顺手把迟到的非终态 job 行中性化：summary 与"重新整理"都按
                    // job 状态数 failed——留一行 failed 会让已发布的批次显示可重试，
                    // 用户一点就把同一批照片再传一遍。
                    let neutralize = try prepare(
                        """
                        UPDATE upload_jobs SET state='acknowledged', updated_at=?
                        WHERE batch_id=? AND state NOT IN ('succeeded','acknowledged')
                        """, db: db)
                    defer { sqlite3_finalize(neutralize) }
                    sqlite3_bind_double(neutralize, 1, Date().timeIntervalSince1970)
                    bind(batchID, at: 2, to: neutralize)
                    try stepDone(neutralize, db: db)
                    try execute("COMMIT", db: db)
                    return
                }
                let counts = try prepare(
                    "SELECT state,COUNT(*) FROM upload_jobs WHERE batch_id=? GROUP BY state", db: db)
                defer { sqlite3_finalize(counts) }
                bind(batchID, at: 1, to: counts)
                var total = 0
                var succeeded = 0
                var failed = 0
                while sqlite3_step(counts) == SQLITE_ROW {
                    let state = sqlite3_column_text(counts, 0).map { String(cString: $0) } ?? ""
                    let count = Int(sqlite3_column_int64(counts, 1))
                    total += count
                    if state == "succeeded" || state == "acknowledged" { succeeded += count }
                    if state == "failed" { failed += count }
                }
                guard total > 0, succeeded + failed == total else {
                    try execute("COMMIT", db: db)
                    return
                }
                let batch = try prepare(
                    "SELECT asset_identifiers_json FROM upload_batches WHERE batch_id=?", db: db)
                defer { sqlite3_finalize(batch) }
                bind(batchID, at: 1, to: batch)
                guard sqlite3_step(batch) == SQLITE_ROW,
                      let text = sqlite3_column_text(batch, 0),
                      let data = String(cString: text).data(using: .utf8),
                      let identifiers = try? JSONDecoder().decode([String].self, from: data) else {
                    throw StoreError.sqlite("上传批次缺少素材清单")
                }
                let finalBatchState = failed > 0 ? "failed" : "committed"
                let finalAssetState = failed > 0 ? "failed" : "accepted"
                let now = Date().timeIntervalSince1970
                let updateBatch = try prepare(
                    "UPDATE upload_batches SET state=?,updated_at=? WHERE batch_id=?", db: db)
                defer { sqlite3_finalize(updateBatch) }
                bind(finalBatchState, at: 1, to: updateBatch)
                sqlite3_bind_double(updateBatch, 2, now)
                bind(batchID, at: 3, to: updateBatch)
                try stepDone(updateBatch, db: db)
                let updateAsset = try prepare(
                    "UPDATE intake_assets SET state=?,updated_at=? WHERE local_identifier=?", db: db)
                defer { sqlite3_finalize(updateAsset) }
                for identifier in identifiers {
                    sqlite3_reset(updateAsset)
                    sqlite3_clear_bindings(updateAsset)
                    bind(finalAssetState, at: 1, to: updateAsset)
                    sqlite3_bind_double(updateAsset, 2, now)
                    bind(identifier, at: 3, to: updateAsset)
                    try stepDone(updateAsset, db: db)
                }
                try execute("COMMIT", db: db)
            } catch {
                try? execute("ROLLBACK", db: db)
                throw error
            }
        }
    }

    // MARK: - 本机身份样本

    /// `label`: 1 = 这是布布，-1 = 不是布布。每类只保留最近 40 张脸，避免模型无限增长。
    func addIdentitySamples(_ featurePrints: [Data], label: Int) throws {
        guard !featurePrints.isEmpty, label == 1 || label == -1 else { return }
        try withDatabase { db in
            try execute("BEGIN IMMEDIATE", db: db)
            do {
                let statement = try prepare(
                    """
                    INSERT INTO identity_samples(id, label, feature_print, created_at)
                    VALUES(?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET label = excluded.label, created_at = excluded.created_at
                    """, db: db)
                defer { sqlite3_finalize(statement) }
                let now = Date().timeIntervalSince1970
                for feature in featurePrints {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    let digest = SHA256.hash(data: feature).map { String(format: "%02x", $0) }.joined()
                    bind(digest, at: 1, to: statement)
                    sqlite3_bind_int(statement, 2, Int32(label))
                    _ = feature.withUnsafeBytes { raw in
                        sqlite3_bind_blob(statement, 3, raw.baseAddress, Int32(raw.count), Self.transient)
                    }
                    sqlite3_bind_double(statement, 4, now)
                    try stepDone(statement, db: db)
                }
                let prune = try prepare(
                    """
                    DELETE FROM identity_samples
                    WHERE label = ? AND id NOT IN (
                        SELECT id FROM identity_samples WHERE label = ?
                        ORDER BY created_at DESC LIMIT 40
                    )
                    """, db: db)
                defer { sqlite3_finalize(prune) }
                sqlite3_bind_int(prune, 1, Int32(label))
                sqlite3_bind_int(prune, 2, Int32(label))
                try stepDone(prune, db: db)
                try execute("COMMIT", db: db)
            } catch {
                try? execute("ROLLBACK", db: db)
                throw error
            }
        }
    }

    func identitySamples() throws -> [PhotoIdentitySample] {
        try withDatabase { db in
            let statement = try prepare(
                "SELECT label, feature_print FROM identity_samples ORDER BY created_at DESC", db: db)
            defer { sqlite3_finalize(statement) }
            var result: [PhotoIdentitySample] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let label = Int(sqlite3_column_int(statement, 0))
                let count = Int(sqlite3_column_bytes(statement, 1))
                guard count > 0, let bytes = sqlite3_column_blob(statement, 1) else { continue }
                result.append(PhotoIdentitySample(
                    label: label,
                    featureData: Data(bytes: bytes, count: count)
                ))
            }
            return result
        }
    }

    func identitySampleCounts() throws -> (positive: Int, negative: Int) {
        let samples = try identitySamples()
        return (samples.count { $0.label == 1 }, samples.count { $0.label == -1 })
    }

    func clearIdentitySamples() throws {
        try withDatabase { db in try execute("DELETE FROM identity_samples", db: db) }
    }

    // MARK: SQLite

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var database: OpaquePointer?
        let code = sqlite3_open_v2(databaseURL.path, &database,
                                   SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                                   nil)
        guard code == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "未知错误"
            if let database { sqlite3_close(database) }
            throw StoreError.open(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 5_000)
        try execute("PRAGMA journal_mode=WAL", db: database)
        try execute("PRAGMA foreign_keys=ON", db: database)
        try createSchema(db: database)
        applyFileProtection()
        return try body(database)
    }

    /// 候选库含拍摄时间与可选 GPS，使用系统数据保护；后台任务在首次解锁后仍可继续。
    /// 身份库额外标记为不进入系统备份，保证人脸特征只留在当前设备。
    private func applyFileProtection() {
        #if os(iOS)
        let attributes: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        for suffix in ["", "-wal", "-shm"] {
            let path = databaseURL.path + suffix
            guard FileManager.default.fileExists(atPath: path) else { continue }
            try? FileManager.default.setAttributes(attributes, ofItemAtPath: path)
            if excludeFromBackup {
                var fileURL = URL(fileURLWithPath: path)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? fileURL.setResourceValues(values)
            }
        }
        #endif
    }

    private func createSchema(db: OpaquePointer) throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS intake_metadata(
                key TEXT PRIMARY KEY NOT NULL,
                value BLOB NOT NULL
            );
            CREATE TABLE IF NOT EXISTS intake_assets(
                local_identifier TEXT PRIMARY KEY NOT NULL,
                cloud_identifier TEXT,
                state TEXT NOT NULL,
                group_id TEXT,
                content_hash TEXT,
                created_at REAL NOT NULL,
                media_type INTEGER NOT NULL,
                latitude REAL,
                longitude REAL,
                width INTEGER NOT NULL,
                height INTEGER NOT NULL,
                duration REAL NOT NULL,
                burst_identifier TEXT,
                is_live_photo INTEGER NOT NULL DEFAULT 0,
                last_seen_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_intake_assets_state_created
                ON intake_assets(state, created_at DESC);
            CREATE TABLE IF NOT EXISTS upload_batches(
                batch_id TEXT PRIMARY KEY NOT NULL,
                entry_local_id TEXT NOT NULL,
                asset_identifiers_json TEXT NOT NULL,
                state TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS upload_jobs(
                asset_key TEXT PRIMARY KEY NOT NULL,
                batch_id TEXT NOT NULL REFERENCES upload_batches(batch_id) ON DELETE CASCADE,
                asset_local_identifier TEXT NOT NULL,
                resource_type INTEGER NOT NULL,
                resource_filename TEXT NOT NULL,
                destination_url TEXT NOT NULL,
                upload_token TEXT NOT NULL,
                mime_type TEXT NOT NULL,
                state TEXT NOT NULL,
                retry_count INTEGER NOT NULL DEFAULT 0,
                last_error TEXT,
                updated_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_upload_jobs_state_updated
                ON upload_jobs(state, updated_at);
            CREATE TABLE IF NOT EXISTS identity_samples(
                id TEXT PRIMARY KEY NOT NULL,
                label INTEGER NOT NULL CHECK(label IN (-1, 1)),
                feature_print BLOB NOT NULL,
                created_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_identity_samples_label_created
                ON identity_samples(label, created_at DESC);
            """, db: db)
    }

    private func execute(_ sql: String, db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw StoreError.sqlite(message)
        }
    }

    private func prepare(_ sql: String, db: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer, db: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        _ = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, Self.transient)
        }
    }

    private func bind(_ value: String?, at index: Int32, to statement: OpaquePointer) {
        if let value { bind(value, at: index, to: statement) }
        else { sqlite3_bind_null(statement, index) }
    }

    private func bind(_ value: Double?, at index: Int32, to statement: OpaquePointer) {
        if let value { sqlite3_bind_double(statement, index, value) }
        else { sqlite3_bind_null(statement, index) }
    }

    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
}
